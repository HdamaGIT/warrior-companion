local addonName, ns = ...

-- Warrior Workshop Probe (M1, extended in M3: SPEC_V2 §12). Deliberately crude and throwaway: it records
-- what the Forever client exposes so docs/PROBE_RESULTS.md can answer V-01..V-33.
--
-- This file holds the shared helpers, the event recorder and the slash dispatcher. Dumps.lua, Combat.lua and
-- Actions.lua add commands and listeners through ns.Listen / ns.AddCommand / ns.onInit / ns.onClear.
--
-- SECRET-VALUE SAFETY (D-007): event arguments and combat API returns are never used in arithmetic,
-- comparisons, concatenation or as table keys. For each value we record type() and the result of
-- issecretvalue(); the raw value is stored by plain assignment ONLY when issecretvalue exists and returns
-- false. Classification runs inside pcall, so an unexpected secret cannot break the recorder.
--
-- Output lives in WarriorWorkshopProbeDB, written to disk on /reload or logout.

ns.PROBE_VERSION = 2

local EVENT_CAP = 3000
local DUMP_MAX_DEPTH = 6
local DEFAULT_RECIPE_DUMPS = 10
local ADDON_MSG_PREFIX = "WWPROBE"
local CHAT_PREFIX = "|cffc79c6eWWProbe|r: "
local HANDLER_ERROR_CAP = 50

local db -- WarriorWorkshopProbeDB once PLAYER_LOGIN fires
local registrations = {} -- [event or event@units] = true | error string
local sessionCounts = {} -- [listener key] = events seen this session (for per-session caps)
ns.registrations = registrations

-- Our own flags. Encounter state comes from the event NAME only (arguments are never read).
local state = { inEncounter = false, inInstance = false, inCombat = false, pingSeq = 0 }
ns.state = state

-- Lists other files extend before the first /wwprobe run.
ns.onInit = {}  -- functions(db) run once after the saved table is ready
ns.onClear = {} -- functions(db) run by /wwprobe clear

---------------------------------------------------------------------------
-- Helpers (operate on our own values only, never on event arguments)
---------------------------------------------------------------------------

local function out(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(CHAT_PREFIX .. msg)
    else
        print(CHAT_PREFIX .. msg)
    end
end
ns.out = out

--- Looks up a dotted global path such as "C_Item.GetItemStats". Returns nil if absent.
local function resolve(path)
    local node = _G
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end
        node = node[part]
    end
    return node
end
ns.resolve = resolve

local function pack(...)
    return { n = select("#", ...), ... }
end
ns.pack = pack

--- Recursively copies a value into SavedVariables-safe form (out-of-combat API data, not event args).
local function dump(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local valueType = type(value)
    if valueType == "table" then
        if seen[value] then
            return "<cycle>"
        end
        if depth >= DUMP_MAX_DEPTH then
            return "<max depth>"
        end
        seen[value] = true
        local copy = {}
        for key, inner in pairs(value) do
            local keyType = type(key)
            local safeKey = (keyType == "string" or keyType == "number") and key or ("<" .. keyType .. "key>")
            copy[safeKey] = dump(inner, depth + 1, seen)
        end
        seen[value] = nil
        return copy
    elseif valueType == "function" or valueType == "userdata" or valueType == "thread" then
        return "<" .. valueType .. ">"
    end
    return value
end
ns.dump = dump

--- Calls an API by path inside pcall. Returns { exists, ok, error | returns (dumped) }.
-- Only for calls whose results cannot be secret (out-of-combat data). Use probeCallSafe otherwise.
local function probeCall(path, ...)
    local fn = resolve(path)
    if type(fn) ~= "function" then
        return { exists = false }
    end
    local results = pack(pcall(fn, ...))
    if not results[1] then
        return { exists = true, ok = false, error = tostring(results[2]) }
    end
    local returns = { n = results.n - 1 }
    for i = 2, results.n do
        returns[i - 1] = dump(results[i])
    end
    return { exists = true, ok = true, returns = returns }
end
ns.probeCall = probeCall

--- Describes one value that may be secret, without operating on it (D-007).
-- @return { type, secret = true|false|"nochecker"|"checkerror"|"unexpected:<type>", value (only if not secret) }
local function classify(value)
    local info = { type = type(value) }
    local isSecretValue = resolve("issecretvalue")
    if type(isSecretValue) ~= "function" then
        info.secret = "nochecker"
        return info
    end
    local ok, isSecret = pcall(isSecretValue, value)
    if not ok then
        info.secret = "checkerror"
    elseif isSecret == true then
        info.secret = true
    elseif isSecret == false then
        info.secret = false
        local valueType = info.type
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            info.value = value
        end
    else
        info.secret = "unexpected:" .. type(isSecret)
    end
    return info
end
ns.classify = classify

--- Like probeCall, but returns are classified instead of copied, because they might be secret.
local function probeCallSafe(path, ...)
    local fn = resolve(path)
    if type(fn) ~= "function" then
        return { exists = false }
    end
    local results = pack(pcall(fn, ...))
    local report = { exists = true, ok = results[1], returns = { n = results.n - 1 } }
    if not results[1] then
        report.error = tostring(results[2]) -- engine error message, not a game value
        return report
    end
    for i = 2, results.n do
        local ok, info = pcall(classify, results[i])
        report.returns[i - 1] = ok and info or { error = "classify failed" }
    end
    return report
end
ns.probeCallSafe = probeCallSafe

--- Calls an API and reports whether its first return is exactly true. The comparison runs inside pcall,
-- so a secret return gives nil (unknown) rather than an error.
-- @return true | false | nil (missing API, error or secret)
function ns.CallIsTrue(path, ...)
    local fn = resolve(path)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(function(...)
        return fn(...) == true
    end, ...)
    if ok then
        return result
    end
    return nil
end

--- Returns the first return of an API only if it is confirmed not secret (and is a string, number or boolean).
-- @return value or nil
function ns.SafeFirst(path, ...)
    local report = probeCallSafe(path, ...)
    local first = report.ok and report.returns[1]
    if type(first) == "table" and first.secret == false then
        return first.value
    end
    return nil
end

--- Schedules fn after delay seconds through C_Timer.After. fn runs inside pcall; an error is recorded in
-- handlerErrors instead of reaching the error popup. Returns false if no timer API exists.
function ns.After(delay, fn)
    local after = resolve("C_Timer.After")
    if type(after) ~= "function" then
        return false
    end
    return (pcall(after, delay, function()
        local ok, err = pcall(fn)
        if not ok and ns.RecordError then
            ns.RecordError("timer", err)
        end
    end))
end

--- Returns "encounter", "instance" or "openWorld" from our own flags.
function ns.Context()
    if state.inEncounter then
        return "encounter"
    elseif state.inInstance then
        return "instance"
    end
    return "openWorld"
end

local function updateInstance()
    state.inInstance = ns.CallIsTrue("IsInInstance") == true
end

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
end
ns.sortedKeys = sortedKeys

--- Appends a value to a list, dropping the oldest entries above cap.
function ns.PushCapped(list, value, cap)
    list[#list + 1] = value
    while #list > cap do
        table.remove(list, 1)
    end
end

---------------------------------------------------------------------------
-- Static checks (V-01..V-05, V-10; extended by Dumps.lua for M3)
---------------------------------------------------------------------------

-- Functions the Adapter surface and the V-items may rely on. Other files append to these lists.
ns.FUNCTION_CHECKS = {
    -- build / combat
    "GetBuildInfo", "InCombatLockdown", "UnitAffectingCombat", "IsEncounterInProgress",
    -- bags and bank
    "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
    "C_Container.GetContainerItemID", "C_Container.GetContainerItemLink", "C_Container.GetBagName",
    "C_Bank.CanViewBank", "C_Bank.FetchPurchasedBankTabData",
    -- equipped and durability
    "GetInventoryItemLink", "GetInventoryItemID", "GetInventoryItemDurability", "GetInventorySlotInfo",
    -- items (V-04)
    "C_Item.GetItemStats", "GetItemStats", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant",
    "C_Item.IsUsableItem", "C_Item.GetDetailedItemLevelInfo", "C_Item.RequestLoadItemDataByID",
    "C_Item.IsItemDataCachedByID", "Item.CreateFromItemID", "C_PlayerInfo.CanUseItem",
    -- professions (V-02)
    "GetProfessions", "GetProfessionInfo",
    "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetChildProfessionInfo",
    "C_TradeSkillUI.GetChildProfessionInfos", "C_TradeSkillUI.GetProfessionInfoBySkillLineID",
    "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetFilteredRecipeIDs",
    "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic",
    "C_TradeSkillUI.GetRecipeOutputItemData", "C_TradeSkillUI.GetRecipeItemLink",
    "C_TradeSkillUI.GetCraftableCount", "C_TradeSkillUI.IsTradeSkillReady",
    "C_TradeSkillUI.IsTradeSkillLinked", "C_TradeSkillUI.GetTradeSkillDisplayName",
    -- equipment sets (V-05)
    "C_EquipmentSet.GetEquipmentSetIDs", "C_EquipmentSet.GetEquipmentSetInfo",
    "C_EquipmentSet.GetItemIDs", "C_EquipmentSet.GetNumEquipmentSets", "C_EquipmentSet.CanUseEquipmentSets",
    -- comms (V-08, V-09)
    "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix",
    "C_ChatInfo.IsAddonMessagePrefixRegistered", "C_ChatInfo.SendChatMessage", "SendChatMessage",
    -- metadata
    "C_AddOns.GetAddOnMetadata",
}

-- Secret-value API candidates (V-10). Names beyond issecretvalue are unconfirmed guesses.
ns.SECRET_CHECKS = {
    "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
    "canaccessallvalues", "hasanysecretvalues", "scrubsecretvalues",
}

-- Classic-only globals we expect to be ABSENT on the Mainline API.
ns.CLASSIC_CHECKS = {
    "GetTradeSkillInfo", "GetNumTradeSkills", "GetTradeSkillReagentInfo", "GetCraftInfo",
    "GetContainerItemInfo", "GetContainerNumSlots",
}

-- Namespaces whose full key lists are recorded, so real function names are visible.
ns.NAMESPACES = {
    "C_TradeSkillUI", "C_Item", "C_Container", "C_Bank", "C_EquipmentSet", "C_ChatInfo", "C_PlayerInfo",
}

--- Appends every item of items to the list named listName on ns.
function ns.Extend(listName, items)
    local list = ns[listName]
    for _, item in ipairs(items) do
        list[#list + 1] = item
    end
end

local function checkPaths(paths)
    local result = {}
    for _, path in ipairs(paths) do
        result[path] = type(resolve(path))
    end
    return result
end

local function countFunctions(result)
    local found, missing = 0, 0
    for _, valueType in pairs(result) do
        if valueType == "function" then
            found = found + 1
        else
            missing = missing + 1
        end
    end
    return found, missing
end

local function runStatic()
    local static = { at = time() }
    static.buildInfo = probeCall("GetBuildInfo")
    static.functions = checkPaths(ns.FUNCTION_CHECKS)
    static.secretApis = checkPaths(ns.SECRET_CHECKS)
    static.classicGlobals = checkPaths(ns.CLASSIC_CHECKS)
    static.namespaces = {}
    for _, name in ipairs(ns.NAMESPACES) do
        local namespace = resolve(name)
        static.namespaces[name] = type(namespace) == "table" and sortedKeys(namespace) or type(namespace)
    end
    static.bagIndex = dump(resolve("Enum.BagIndex"))
    static.registrations = registrations
    db.static = static

    local returns = static.buildInfo.returns or {}
    local found, missing = countFunctions(static.functions)
    local classicFound = countFunctions(static.classicGlobals)
    out(string.format("version %s, build %s, interface %s",
        tostring(returns[1]), tostring(returns[2]), tostring(returns[4])))
    out(string.format("API functions: %d found, %d missing; Classic globals present: %d",
        found, missing, classicFound))
    out("issecretvalue: " .. static.secretApis.issecretvalue)

    local regOk, regFailed = 0, 0
    for _, status in pairs(registrations) do
        if status == true then
            regOk = regOk + 1
        else
            regFailed = regFailed + 1
        end
    end
    out(string.format("events registered: %d ok, %d failed; recorded so far: %d (recording %s)",
        regOk, regFailed, #db.events, db.recording and "on" or "off"))
    out("Saved to WarriorWorkshopProbeDB. /reload or log out to write it to disk.")
end

---------------------------------------------------------------------------
-- Profession dump (V-02)
---------------------------------------------------------------------------

local function scalarFields(tbl)
    if type(tbl) ~= "table" then
        return type(tbl)
    end
    local copy = {}
    for key, value in pairs(tbl) do
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            copy[key] = value
        else
            copy[key] = "<" .. valueType .. ">"
        end
    end
    return copy
end

local function runProf(maxDeep)
    if type(resolve("C_TradeSkillUI")) ~= "table" then
        out("C_TradeSkillUI is missing.")
        db.prof = { at = time(), error = "C_TradeSkillUI missing" }
        return
    end
    local prof = { at = time(), inEncounter = state.inEncounter }
    prof.isReady = probeCall("C_TradeSkillUI.IsTradeSkillReady")
    prof.baseProfession = probeCall("C_TradeSkillUI.GetBaseProfessionInfo")
    prof.childProfession = probeCall("C_TradeSkillUI.GetChildProfessionInfo")
    prof.childProfessions = probeCall("C_TradeSkillUI.GetChildProfessionInfos")
    prof.professions = probeCall("GetProfessions")

    local allIds = probeCall("C_TradeSkillUI.GetAllRecipeIDs")
    local ids = allIds.ok and allIds.returns[1] or nil
    if type(ids) ~= "table" then
        prof.error = "GetAllRecipeIDs returned no table"
        db.prof = prof
        out("No recipe IDs. Is a profession window open?")
        return
    end
    prof.recipeCount = #ids

    -- Full recursive dump of the first N recipes.
    prof.recipes = {}
    for i = 1, math.min(maxDeep, #ids) do
        local recipeID = ids[i]
        prof.recipes[i] = {
            recipeID = recipeID,
            info = probeCall("C_TradeSkillUI.GetRecipeInfo", recipeID),
            schematic = probeCall("C_TradeSkillUI.GetRecipeSchematic", recipeID, false),
            outputItemData = probeCall("C_TradeSkillUI.GetRecipeOutputItemData", recipeID),
            itemLink = probeCall("C_TradeSkillUI.GetRecipeItemLink", recipeID),
            craftableCount = probeCall("C_TradeSkillUI.GetCraftableCount", recipeID),
        }
    end

    -- Compact scalar-only view of every recipe, to see difficulty spread and learned flags.
    local getRecipeInfo = resolve("C_TradeSkillUI.GetRecipeInfo")
    prof.allRecipesCompact = {}
    for i, recipeID in ipairs(ids) do
        local ok, info = pcall(getRecipeInfo, recipeID)
        prof.allRecipesCompact[i] = ok and scalarFields(info) or { recipeID = recipeID, error = tostring(info) }
    end

    db.prof = prof
    out(string.format("Profession dump: %d recipe IDs, %d dumped in full.", #ids, #prof.recipes))
end

---------------------------------------------------------------------------
-- Item, gear, sets and bag dumps (V-04, V-05, bank layout)
---------------------------------------------------------------------------

local function itemReport(itemRef)
    return {
        ref = itemRef,
        statsCItem = probeCall("C_Item.GetItemStats", itemRef),
        statsGlobal = probeCall("GetItemStats", itemRef),
        info = probeCall("C_Item.GetItemInfo", itemRef),
        infoInstant = probeCall("C_Item.GetItemInfoInstant", itemRef),
        itemLevel = probeCall("C_Item.GetDetailedItemLevelInfo", itemRef),
        usable = probeCall("C_Item.IsUsableItem", itemRef),
    }
end

local function runItem(arg)
    -- arg is our own slash input, not an event argument.
    local link = arg:match("|c.-|r") or arg:match("item:[%-%d:]+")
    local itemRef = link or tonumber(arg)
    if not itemRef then
        out("Usage: /wwprobe item <shift-click an item link> (or an itemID)")
        return
    end
    local report = itemReport(itemRef)
    report.at = time()
    db.items[#db.items + 1] = report
    local cached = report.info.ok and report.info.returns.n > 0 and report.info.returns[1] ~= nil
    out(string.format("Item dump #%d saved.%s", #db.items,
        cached and "" or " Item info not cached yet: run the same command again."))
end

local function runGear()
    local gear = { at = time(), slots = {} }
    for slot = 1, 19 do
        local link = probeCall("GetInventoryItemLink", "player", slot)
        local entry = {
            slot = slot,
            itemID = probeCall("GetInventoryItemID", "player", slot),
            link = link,
            durability = probeCall("GetInventoryItemDurability", slot),
        }
        local itemLink = link.ok and link.returns[1] or nil
        if type(itemLink) == "string" then
            entry.item = itemReport(itemLink)
        end
        gear.slots[slot] = entry
    end
    gear.sets = { canUse = probeCall("C_EquipmentSet.CanUseEquipmentSets"),
        count = probeCall("C_EquipmentSet.GetNumEquipmentSets"),
        ids = probeCall("C_EquipmentSet.GetEquipmentSetIDs"), details = {} }
    local ids = gear.sets.ids.ok and gear.sets.ids.returns[1] or nil
    if type(ids) == "table" then
        for i, setID in ipairs(ids) do
            gear.sets.details[i] = {
                setID = setID,
                info = probeCall("C_EquipmentSet.GetEquipmentSetInfo", setID),
                itemIDs = probeCall("C_EquipmentSet.GetItemIDs", setID),
            }
        end
    end
    db.gear = gear
    out(string.format("Gear dump saved: 19 slots, %d equipment set(s).", #gear.sets.details))
end

local function runBags()
    local bagIndex = resolve("Enum.BagIndex")
    local bags = { at = time(), containers = {} }
    if type(bagIndex) ~= "table" then
        bags.error = "Enum.BagIndex missing"
    else
        for name, bagID in pairs(bagIndex) do
            local slots = probeCall("C_Container.GetContainerNumSlots", bagID)
            local entry = { name = name, bagID = bagID, numSlots = slots, filled = 0 }
            local numSlots = slots.ok and slots.returns[1] or 0
            if type(numSlots) == "number" then
                for slot = 1, numSlots do
                    local ok, info = pcall(resolve("C_Container.GetContainerItemInfo"), bagID, slot)
                    if ok and info then
                        entry.filled = entry.filled + 1
                        entry.firstItem = entry.firstItem or dump(info)
                    end
                end
            end
            bags.containers[#bags.containers + 1] = entry
        end
    end
    bags.bankViewable = probeCall("C_Bank.CanViewBank", 0)
    db.bags = bags
    out(string.format("Bag dump saved: %d containers. Run again with the bank open.", #bags.containers))
end

---------------------------------------------------------------------------
-- Comms test (V-08, V-09)
---------------------------------------------------------------------------

--- Returns the group chat channel for add-on pings, or nil when solo.
function ns.GroupChannel()
    local instanceCategory = resolve("LE_PARTY_CATEGORY_INSTANCE")
    if instanceCategory and ns.CallIsTrue("IsInGroup", instanceCategory) then
        return "INSTANCE_CHAT"
    elseif ns.CallIsTrue("IsInRaid") then
        return "RAID"
    elseif ns.CallIsTrue("IsInGroup") then
        return "PARTY"
    end
    return nil
end

local function runPing()
    state.pingSeq = state.pingSeq + 1
    local pingSeq = state.pingSeq
    local channel = ns.GroupChannel()
    local ping = { at = time(), t = GetTime(), seq = pingSeq, inEncounter = state.inEncounter,
        ctx = ns.Context(), channel = channel or "none" }
    local payload = "PING:" .. pingSeq
    if channel then
        ping.addonMessage = probeCallSafe("C_ChatInfo.SendAddonMessage", ADDON_MSG_PREFIX, payload, channel)
        local chatPath = resolve("C_ChatInfo.SendChatMessage") and "C_ChatInfo.SendChatMessage" or "SendChatMessage"
        ping.chatMessage = probeCallSafe(chatPath, "[WW:" .. payload .. "]", channel)
        ping.chatPath = chatPath
    else
        -- Solo: whisper the add-on message to ourselves to test the plumbing.
        local playerName = probeCall("UnitName", "player")
        local me = playerName.ok and playerName.returns[1] or nil
        ping.addonMessage = probeCallSafe("C_ChatInfo.SendAddonMessage", ADDON_MSG_PREFIX, payload, "WHISPER", me)
        ping.note = "not in a group: add-on message whispered to self, no chat line sent"
    end
    db.pings[#db.pings + 1] = ping
    out(string.format("Ping %d sent on %s%s.", pingSeq, ping.channel, state.inEncounter and " (in encounter)" or ""))
end

---------------------------------------------------------------------------
-- Event recorder (V-03, V-06..V-09; extended by Combat.lua and Actions.lua)
---------------------------------------------------------------------------

local function recordHandlerError(key, err)
    db.handlerErrors = db.handlerErrors or {}
    ns.PushCapped(db.handlerErrors, { at = time(), key = key, error = tostring(err) }, HANDLER_ERROR_CAP)
end
ns.RecordError = function(key, err)
    if db then
        recordHandlerError(key, err)
    end
end

local function recordEvent(listener, ...)
    if not db.recording then
        return
    end
    local key = listener.key
    local ctx = ns.Context()
    db.eventCounts[key] = (db.eventCounts[key] or 0) + 1
    local byContext = db.eventCountsByContext[ctx]
    if not byContext then
        byContext = {}
        db.eventCountsByContext[ctx] = byContext
    end
    byContext[key] = (byContext[key] or 0) + 1
    if listener.mode ~= "record" then
        return
    end
    local seen = sessionCounts[key] or 0
    sessionCounts[key] = seen + 1
    if listener.cap and seen >= listener.cap then
        return
    end
    local n = select("#", ...)
    local args = {}
    for i = 1, n do
        local ok, info = pcall(classify, (select(i, ...)))
        args[i] = ok and info or { error = "classify failed" }
    end
    ns.PushCapped(db.events, { at = time(), t = GetTime(), event = key, inEncounter = state.inEncounter,
        ctx = ctx, n = n, args = args }, EVENT_CAP)
end

local function initDB()
    WarriorWorkshopProbeDB = WarriorWorkshopProbeDB or {}
    db = WarriorWorkshopProbeDB
    ns.db = db
    db.probeVersion = ns.PROBE_VERSION
    if db.recording == nil then
        db.recording = true
    end
    db.events = db.events or {}
    db.eventCounts = db.eventCounts or {}
    db.eventCountsByContext = db.eventCountsByContext or {}
    db.items = db.items or {}
    db.pings = db.pings or {}
    db.sessions = db.sessions or {}
    db.registrations = registrations
    updateInstance()
    state.inCombat = ns.CallIsTrue("InCombatLockdown") == true
    db.sessions[#db.sessions + 1] = { at = time(), buildInfo = probeCall("GetBuildInfo"), ctx = ns.Context() }
    for _, hook in ipairs(ns.onInit) do
        local ok, err = pcall(hook, db)
        if not ok then
            recordHandlerError("onInit", err)
        end
    end
end

local frames = {} -- [unitsKey] = frame; unit-filtered events need their own frame per unit set

local function onEvent(frame, event, ...)
    -- Initialise on PLAYER_LOGIN (SavedVariables are loaded by then, and on every /reload) so we never need
    -- to compare an ADDON_LOADED argument.
    if not db then
        if event ~= "PLAYER_LOGIN" then
            return
        end
        initDB()
        db.prefixRegistration = ns.prefixRegistration
    end
    local listener = frame.listeners[event]
    if not listener then
        return
    end
    -- Only the event NAME (our own string) is inspected for state; arguments are left untouched.
    if event == "ENCOUNTER_START" then
        state.inEncounter = true
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        updateInstance()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
    end
    recordEvent(listener, ...)
    if listener.handler then
        local ok, err = pcall(listener.handler, event, ...)
        if not ok then
            recordHandlerError(listener.key, err)
        end
    end
    if event == "ENCOUNTER_END" then
        state.inEncounter = false
    end
end

local function getFrame(unitsKey)
    local frame = frames[unitsKey]
    if not frame then
        frame = CreateFrame("Frame")
        frame.listeners = {}
        frame:SetScript("OnEvent", onEvent)
        frames[unitsKey] = frame
    end
    return frame
end

--- Registers a game event with the recorder (D-008: every registration is pcall-wrapped and recorded).
-- @param event string
-- @param opts table|nil { units = { "player" [, "target"] } (unit filter, max two units),
--   mode = "record" (default: classify args into db.events) | "count" (counts only),
--   cap = number (max recorded per session), handler = function(event, ...) run after recording }
-- @return string the registration key (event, or event@units)
function ns.Listen(event, opts)
    opts = opts or {}
    local units = opts.units
    local unitsKey = units and table.concat(units, ",") or ""
    local key = units and (event .. "@" .. unitsKey) or event
    local frame = getFrame(unitsKey)
    local ok, err
    if units then
        ok, err = pcall(frame.RegisterUnitEvent, frame, event, units[1], units[2])
    else
        ok, err = pcall(frame.RegisterEvent, frame, event)
    end
    registrations[key] = ok and true or tostring(err)
    frame.listeners[event] = { key = key, mode = opts.mode or "record", cap = opts.cap, handler = opts.handler }
    return key
end

local EVENTS = {
    -- Lifecycle and context
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    -- Workshop (SPEC v0.1 Section 8)
    "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP",
    -- Encounters and comms
    "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_ADDON",
    -- Candidates (unverified names; a failed registration is itself a finding)
    "TRADE_SKILL_ITEM_CRAFTED_RESULT", "TRADE_SKILL_CRAFT_BEGIN", "NEW_RECIPE_LEARNED",
    "UPDATE_TRADESKILL_CAST_STOPPED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "BANK_TAB_SETTINGS_UPDATED", "EQUIPMENT_SETS_CHANGED",
}

for _, event in ipairs(EVENTS) do
    ns.Listen(event)
end

-- Registered for the player only, to avoid flooding with party/nameplate casts (D-008).
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
    ns.Listen(event, { units = { "player" } })
end

-- Register the prefix at load so CHAT_MSG_ADDON is delivered (D-009).
ns.prefixRegistration = probeCallSafe("C_ChatInfo.RegisterAddonMessagePrefix", ADDON_MSG_PREFIX)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local commands = {}
local commandOrder = {}

--- Adds a /wwprobe sub-command.
-- @param name string first word after /wwprobe (lower case)
-- @param run function(rest) rest is the remaining slash text (our own input)
-- @param help string one help line
function ns.AddCommand(name, run, help)
    if not commands[name] then
        commandOrder[#commandOrder + 1] = name
    end
    commands[name] = { run = run, help = help }
end

local function printHelp()
    out("/wwprobe - static API checks and summary")
    for _, name in ipairs(commandOrder) do
        out(commands[name].help)
    end
end

ns.AddCommand("prof", function(rest)
    runProf(tonumber(rest) or DEFAULT_RECIPE_DUMPS)
end, "/wwprobe prof [n] - dump the open profession (first n recipes in full, default 10)")
ns.AddCommand("item", runItem, "/wwprobe item <link> - dump item stats and info")
ns.AddCommand("gear", runGear, "/wwprobe gear - dump equipped items, durability and equipment sets")
ns.AddCommand("bags", runBags, "/wwprobe bags - dump bag/bank container layout (run once with the bank open)")
ns.AddCommand("ping", runPing, "/wwprobe ping - send an add-on message and a [WW:PING] chat line to your group")
ns.AddCommand("rec", function(rest)
    db.recording = rest:lower() ~= "off"
    out("Recording " .. (db.recording and "on" or "off") .. ".")
end, "/wwprobe rec on|off - toggle the event recorder")
ns.AddCommand("clear", function()
    db.events, db.eventCounts, db.eventCountsByContext, db.items, db.pings = {}, {}, {}, {}, {}
    db.handlerErrors = nil
    for key in pairs(sessionCounts) do
        sessionCounts[key] = nil
    end
    for _, hook in ipairs(ns.onClear) do
        local ok, err = pcall(hook, db)
        if not ok then
            recordHandlerError("onClear", err)
        end
    end
    out("Cleared.")
end, "/wwprobe clear - clear everything recorded (keeps settings such as the combat sampler switch)")
ns.AddCommand("help", printHelp, "/wwprobe help - this list")

SLASH_WWPROBE1 = "/wwprobe"
SlashCmdList.WWPROBE = function(msg)
    if not db then
        out("Not initialised yet.")
        return
    end
    local input = (msg or ""):match("^%s*(.-)%s*$")
    local command, rest = input:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()

    if command == "" then
        runStatic()
        return
    end
    local entry = commands[command]
    if entry then
        local ok, err = pcall(entry.run, rest or "")
        if not ok then
            recordHandlerError("command:" .. command, err)
            out("Command failed (recorded in handlerErrors): " .. tostring(err))
        end
    else
        printHelp()
    end
end
