local addonName, ns = ...

-- Warrior Workshop Probe (Phase 0, SPEC Section 9). Deliberately crude and
-- throwaway: it answers V-01..V-10 by recording what the Forever client exposes.
--
-- SECRET-VALUE SAFETY (D-007): event arguments are never used in arithmetic,
-- comparisons, concatenation or as table keys. For each argument we record
-- type() and the result of issecretvalue(); the raw value is stored by plain
-- assignment ONLY when issecretvalue exists and returns false. Classification
-- runs inside pcall, so an unexpected secret cannot break the recorder.
--
-- Output lives in WarriorWorkshopProbeDB, written to disk on /reload or logout.

ns.PROBE_VERSION = 1

local EVENT_CAP = 3000
local DUMP_MAX_DEPTH = 6
local DEFAULT_RECIPE_DUMPS = 10
local ADDON_MSG_PREFIX = "WWPROBE"
local CHAT_PREFIX = "|cffc79c6eWWProbe|r: "

local db -- WarriorWorkshopProbeDB once ADDON_LOADED fires
local inEncounter = false -- our own flag, toggled by ENCOUNTER_START/END (args never read)
local registrations = {} -- [event] = true | error string
local pingSeq = 0

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

local function pack(...)
    return { n = select("#", ...), ... }
end

--- Recursively copies a value into SavedVariables-safe form (API data, not event args).
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

--- Calls an API by path inside pcall. Returns { exists, ok, error | returns (dumped) }.
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

--- Describes one event argument (or one possibly-secret return) without operating on it (D-007).
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

--- Like probeCall, but returns are classified instead of copied, because calls made
-- during an encounter (e.g. sends) might return secret values.
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

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
end

---------------------------------------------------------------------------
-- Static checks (V-01..V-05, V-10)
---------------------------------------------------------------------------

-- Functions the Adapter surface (SPEC 5.3) and V-02..V-05 may rely on.
local FUNCTION_CHECKS = {
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
local SECRET_CHECKS = {
    "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
    "canaccessallvalues", "hasanysecretvalues", "scrubsecretvalues",
}

-- Classic-only globals we expect to be ABSENT on the Mainline API.
local CLASSIC_CHECKS = {
    "GetTradeSkillInfo", "GetNumTradeSkills", "GetTradeSkillReagentInfo", "GetCraftInfo",
    "GetContainerItemInfo", "GetContainerNumSlots",
}

-- Namespaces whose full key lists are recorded, so real function names are visible.
local NAMESPACES = {
    "C_TradeSkillUI", "C_Item", "C_Container", "C_Bank", "C_EquipmentSet", "C_ChatInfo", "C_PlayerInfo",
}

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
    static.functions = checkPaths(FUNCTION_CHECKS)
    static.secretApis = checkPaths(SECRET_CHECKS)
    static.classicGlobals = checkPaths(CLASSIC_CHECKS)
    static.namespaces = {}
    for _, name in ipairs(NAMESPACES) do
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
    local prof = { at = time(), inEncounter = inEncounter }
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
-- Item, gear, sets and bag dumps (V-04, V-05, bank layout for M3)
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

local function groupChannel()
    local isInGroup = resolve("IsInGroup")
    local isInRaid = resolve("IsInRaid")
    local instanceCategory = resolve("LE_PARTY_CATEGORY_INSTANCE")
    if type(isInGroup) ~= "function" then
        return nil
    end
    if instanceCategory and isInGroup(instanceCategory) then
        return "INSTANCE_CHAT"
    elseif type(isInRaid) == "function" and isInRaid() then
        return "RAID"
    elseif isInGroup() then
        return "PARTY"
    end
    return nil
end

local function runPing()
    pingSeq = pingSeq + 1
    local channel = groupChannel()
    local ping = { at = time(), t = GetTime(), seq = pingSeq, inEncounter = inEncounter, channel = channel or "none" }
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
    out(string.format("Ping %d sent on %s%s.", pingSeq, ping.channel, inEncounter and " (in encounter)" or ""))
end

---------------------------------------------------------------------------
-- Event recorder (V-03, V-06..V-09)
---------------------------------------------------------------------------

local EVENTS = {
    -- SPEC Section 8
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "BAG_UPDATE_DELAYED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP",
    -- Encounters and comms
    "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_ADDON",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    -- Candidates (unverified names; a failed registration is itself a finding)
    "TRADE_SKILL_ITEM_CRAFTED_RESULT", "TRADE_SKILL_CRAFT_BEGIN", "NEW_RECIPE_LEARNED",
    "UPDATE_TRADESKILL_CAST_STOPPED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "BANK_TAB_SETTINGS_UPDATED", "EQUIPMENT_SETS_CHANGED",
}

-- Registered for the player only, to avoid flooding with party/nameplate casts (D-008).
local PLAYER_UNIT_EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
}

local function recordEvent(event, ...)
    if not db or not db.recording then
        return
    end
    local n = select("#", ...)
    local args = {}
    for i = 1, n do
        local ok, info = pcall(classify, (select(i, ...)))
        args[i] = ok and info or { error = "classify failed" }
    end
    local events = db.events
    events[#events + 1] = { at = time(), t = GetTime(), event = event, inEncounter = inEncounter, n = n, args = args }
    if #events > EVENT_CAP then
        table.remove(events, 1)
    end
    db.eventCounts[event] = (db.eventCounts[event] or 0) + 1
end

local frame = CreateFrame("Frame")

local function tryRegister(event, unit)
    local ok, err
    if unit then
        ok, err = pcall(frame.RegisterUnitEvent, frame, event, unit)
    else
        ok, err = pcall(frame.RegisterEvent, frame, event)
    end
    registrations[event] = ok and true or tostring(err)
end

local function initDB()
    WarriorWorkshopProbeDB = WarriorWorkshopProbeDB or {}
    db = WarriorWorkshopProbeDB
    db.probeVersion = ns.PROBE_VERSION
    if db.recording == nil then
        db.recording = true
    end
    db.events = db.events or {}
    db.eventCounts = db.eventCounts or {}
    db.items = db.items or {}
    db.pings = db.pings or {}
    db.sessions = db.sessions or {}
    db.registrations = registrations
    db.sessions[#db.sessions + 1] = { at = time(), buildInfo = probeCall("GetBuildInfo") }
end

for _, event in ipairs(EVENTS) do
    tryRegister(event)
end
for _, event in ipairs(PLAYER_UNIT_EVENTS) do
    tryRegister(event, "player")
end

-- Register the prefix at load so CHAT_MSG_ADDON is delivered (D-009).
local prefixRegistration = probeCallSafe("C_ChatInfo.RegisterAddonMessagePrefix", ADDON_MSG_PREFIX)

frame:SetScript("OnEvent", function(_, event, ...)
    -- Initialise on PLAYER_LOGIN (SavedVariables are loaded by then, and on every
    -- /reload) so we never need to compare an ADDON_LOADED argument.
    if not db then
        if event ~= "PLAYER_LOGIN" then
            return
        end
        initDB()
        db.prefixRegistration = prefixRegistration
    end
    -- Only the event NAME (our own string) is inspected; arguments are left untouched.
    if event == "ENCOUNTER_START" then
        inEncounter = true
    end
    recordEvent(event, ...)
    if event == "ENCOUNTER_END" then
        inEncounter = false
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local HELP = {
    "/wwprobe - static API checks and summary",
    "/wwprobe prof [n] - dump the open profession (first n recipes in full, default 10)",
    "/wwprobe item <link> - dump item stats and info",
    "/wwprobe gear - dump equipped items, durability and equipment sets",
    "/wwprobe bags - dump bag/bank container layout (run once with the bank open)",
    "/wwprobe ping - send an add-on message and a [WW:PING] chat line to your group",
    "/wwprobe rec on|off - toggle the event recorder",
    "/wwprobe clear - clear recorded events, items and pings",
}

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
    elseif command == "prof" then
        runProf(tonumber(rest) or DEFAULT_RECIPE_DUMPS)
    elseif command == "item" then
        runItem(rest)
    elseif command == "gear" then
        runGear()
    elseif command == "bags" then
        runBags()
    elseif command == "ping" then
        runPing()
    elseif command == "rec" then
        db.recording = rest:lower() ~= "off"
        out("Recording " .. (db.recording and "on" or "off") .. ".")
    elseif command == "clear" then
        db.events, db.eventCounts, db.items, db.pings = {}, {}, {}, {}
        out("Cleared.")
    else
        for _, line in ipairs(HELP) do
            out(line)
        end
    end
end
