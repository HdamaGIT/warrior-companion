local addonName, ns = ...

-- M3 action probes (SPEC_V2 §12.2, D-032): chat sending (V-25, V-26), key binding (V-30), equipment sets
-- (V-27), secure weapon-swap button (V-28) and macros (V-29). Plus /wwprobe status.
--
-- A blocked protected call does not raise a Lua error: the client fires ADDON_ACTION_BLOCKED/FORBIDDEN instead.
-- So success is judged by those events and by our own chat echoes, never by pcall alone.

local out, resolve, probeCall, probeCallSafe, classify = ns.out, ns.resolve, ns.probeCall, ns.probeCallSafe,
    ns.classify

local CHAT_TAG = "[WWPROBE test]"
local CHAT_STAGGER = 1.2
local ATTEMPT_CAP = 200
local SWAP_KEY = "CTRL-SHIFT-F9"
local SWAP_BUTTON = "WWProbeSwapButton"
local MACRO_NAME = "WW Probe"
local BINDING_NAME = "WWPROBE_CHATKEY"

-- Key Bindings UI labels for Bindings.xml (the only new globals besides the saved table and slash command).
BINDING_HEADER_WWPROBE = "Warrior Workshop Probe"
BINDING_NAME_WWPROBE_CHATKEY = "Probe: SAY test line (key press)"

local function db()
    return ns.db
end

---------------------------------------------------------------------------
-- Chat (V-25, V-26)
---------------------------------------------------------------------------

local chatSeq = 0
local lastAttempt
local attemptsBySeq = {}

local function sendPath()
    return resolve("C_ChatInfo.SendChatMessage") and "C_ChatInfo.SendChatMessage" or "SendChatMessage"
end

--- Sends one tagged line and records the attempt.
-- @param channel string PARTY|RAID|INSTANCE_CHAT|SAY|YELL
-- @param trigger string "timer" (no hardware event) or "key" (key press)
local function attemptChat(channel, trigger)
    chatSeq = chatSeq + 1
    local text = string.format("%s %d %s %s", CHAT_TAG, chatSeq, channel, trigger)
    local attempt = { seq = chatSeq, channel = channel, trigger = trigger, ctx = ns.Context(),
        inEncounter = ns.state.inEncounter, at = time(), t = GetTime(), text = text, path = sendPath() }
    -- Registered before sending: an echo or a blocked event may arrive during the send call itself.
    ns.PushCapped(db().chat.attempts, attempt, ATTEMPT_CAP)
    attemptsBySeq[chatSeq] = attempt
    lastAttempt = attempt
    attempt.result = probeCallSafe(attempt.path, text, channel)
    return attempt
end

local function chatChannels(filter)
    local channels = {}
    local home = resolve("LE_PARTY_CATEGORY_HOME")
    local instance = resolve("LE_PARTY_CATEGORY_INSTANCE")
    if ns.CallIsTrue("IsInGroup", home) then
        channels[#channels + 1] = "PARTY"
    end
    if ns.CallIsTrue("IsInRaid") then
        channels[#channels + 1] = "RAID"
    end
    if instance and ns.CallIsTrue("IsInGroup", instance) then
        channels[#channels + 1] = "INSTANCE_CHAT"
    end
    channels[#channels + 1] = "SAY"
    channels[#channels + 1] = "YELL"
    if filter == "" then
        return channels
    end
    local wanted, filtered = {}, {}
    for word in filter:upper():gmatch("%S+") do
        wanted[word] = true
    end
    for _, channel in ipairs(channels) do
        if wanted[channel] then
            filtered[#filtered + 1] = channel
        end
    end
    return filtered
end

local function describeAttempt(attempt)
    local sent = attempt.result.exists == false and "no API" or (attempt.result.ok and "call ok" or "call error")
    local echo = attempt.echoed and "echoed" or "no echo"
    local blocked = attempt.blocked and (", " .. attempt.blocked) or ""
    return string.format("#%d %s (%s): %s, %s%s", attempt.seq, attempt.channel, attempt.trigger, sent, echo, blocked)
end

local function runChat(rest)
    local channels = chatChannels(rest)
    if #channels == 0 then
        out("No matching channels. Use: /wwprobe chat [party raid instance_chat say yell]")
        return
    end
    out(string.format("Sending %s lines from a timer (no key press) to: %s", CHAT_TAG, table.concat(channels, ", ")))
    local firstSeq = chatSeq + 1
    for index, channel in ipairs(channels) do
        ns.After(1 + (index - 1) * CHAT_STAGGER, function()
            attemptChat(channel, "timer")
        end)
    end
    -- Report after the echoes have had time to arrive.
    ns.After(1 + #channels * CHAT_STAGGER + 2, function()
        for seq = firstSeq, chatSeq do
            local attempt = attemptsBySeq[seq]
            if attempt and attempt.trigger == "timer" then
                out(describeAttempt(attempt))
            end
        end
    end)
end

-- Matches our own echoes. The text is used only when confirmed non-secret.
local function onChatMessage(event, text)
    local info = classify(text)
    if info.secret ~= false or type(info.value) ~= "string" then
        local chat = db().chat
        chat.unreadableEchoes[ns.Context()] = (chat.unreadableEchoes[ns.Context()] or 0) + 1
        return
    end
    local seq = info.value:match("^%[WWPROBE test%] (%d+) ")
    local attempt = seq and attemptsBySeq[tonumber(seq)]
    if attempt and not attempt.echoed then
        attempt.echoed = event
        attempt.echoDelay = GetTime() - attempt.t
    end
end

for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ns.Listen(event, { handler = onChatMessage })
end

-- Blocked protected calls (chat, macros, bindings, secure frames) are attributed to the latest attempt.
local function onActionBlocked(event, addon, func)
    local addonInfo, funcInfo = classify(addon), classify(func)
    local funcName = (funcInfo.secret == false and type(funcInfo.value) == "string") and funcInfo.value or "?"
    local entry = { t = GetTime(), event = event, ctx = ns.Context(), addon = addonInfo, func = funcInfo,
        lastChatSeq = lastAttempt and lastAttempt.seq or nil }
    ns.PushCapped(db().blocked, entry, ATTEMPT_CAP)
    if lastAttempt and GetTime() - lastAttempt.t < 1 then
        lastAttempt.blocked = event .. ":" .. funcName
    end
end
ns.Listen("ADDON_ACTION_BLOCKED", { handler = onActionBlocked })
ns.Listen("ADDON_ACTION_FORBIDDEN", { handler = onActionBlocked })

--- Bindings.xml handler: a real key press, so SAY should be allowed outdoors (V-25) and the press itself
-- proves the declared binding works (V-30).
function WWProbe_ChatKey()
    if not ns.db then
        return
    end
    ns.db.bindings.pressed = (ns.db.bindings.pressed or 0) + 1
    local attempt = attemptChat("SAY", "key")
    ns.After(2, function()
        out(describeAttempt(attempt))
    end)
end

local function recordBindingCheck(trigger)
    local check = { at = time(), trigger = trigger, keys = probeCall("GetBindingKey", BINDING_NAME) }
    ns.PushCapped(db().bindings.checks, check, 50)
    return check
end

local function runChatKey()
    local check = recordBindingCheck("command")
    local keys = check.keys.ok and check.keys.returns or {}
    if keys[1] then
        out(string.format("'%s' is bound to %s. Press it to send a SAY line from a key press.",
            BINDING_NAME_WWPROBE_CHATKEY, tostring(keys[1])))
    else
        out("Not bound yet. Open Key Bindings, find 'Warrior Workshop Probe' (under AddOns), bind '"
            .. BINDING_NAME_WWPROBE_CHATKEY .. "' to a spare key, then press it.")
    end
end

---------------------------------------------------------------------------
-- Equipment sets (V-27)
---------------------------------------------------------------------------

local function equippedIDs()
    local ids = {}
    for slot = 1, 19 do
        ids[slot] = ns.SafeFirst("GetInventoryItemID", "player", slot) or false
    end
    return ids
end

local function setList()
    local report = probeCall("C_EquipmentSet.GetEquipmentSetIDs")
    local ids = report.ok and report.returns[1] or nil
    return type(ids) == "table" and ids or {}
end

local function runSets(rest)
    local sets = db().sets
    local ids = setList()
    local index = tonumber(rest)
    if not index then
        sets.list = { at = time(), canUse = probeCall("C_EquipmentSet.CanUseEquipmentSets"), sets = {} }
        for position, setID in ipairs(ids) do
            local info = probeCall("C_EquipmentSet.GetEquipmentSetInfo", setID)
            sets.list.sets[position] = { setID = setID, info = info }
            out(string.format("%d: %s (setID %s)", position, tostring(info.ok and info.returns[1]), tostring(setID)))
        end
        out(#ids == 0 and "No equipment sets. Create two in the character pane first."
            or "Apply one with /wwprobe sets <n>, out of combat and then in combat.")
        return
    end
    local setID = ids[index]
    if not setID then
        out("No set " .. index .. ". Run /wwprobe sets to list them.")
        return
    end
    local attempt = { at = time(), t = GetTime(), index = index, setID = setID, ctx = ns.Context(),
        inCombat = ns.CallIsTrue("InCombatLockdown"), before = equippedIDs() }
    attempt.result = probeCallSafe("C_EquipmentSet.UseEquipmentSet", setID)
    ns.PushCapped(sets.attempts, attempt, ATTEMPT_CAP)
    out(string.format("UseEquipmentSet(%s) called %s. Checking slots in 1.5s.", tostring(setID),
        attempt.inCombat and "IN COMBAT" or "out of combat"))
    ns.After(1.5, function()
        attempt.after = equippedIDs()
        local setItems = probeCall("C_EquipmentSet.GetItemIDs", setID)
        attempt.setItems = setItems
        local expected = setItems.ok and setItems.returns[1] or {}
        local matched, total = 0, 0
        for slot = 1, 19 do
            local want = type(expected) == "table" and expected[slot] or nil
            if type(want) == "number" and want > 0 then
                total = total + 1
                if attempt.after[slot] == want then
                    matched = matched + 1
                end
            end
        end
        attempt.matched, attempt.total = matched, total
        out(string.format("Set %d: %d of %d slots now match the set.", index, matched, total))
    end)
end

---------------------------------------------------------------------------
-- Secure weapon-swap button (V-28)
---------------------------------------------------------------------------

local function weaponIDs()
    return { mainHand = ns.SafeFirst("GetInventoryItemID", "player", 16) or false,
        offHand = ns.SafeFirst("GetInventoryItemID", "player", 17) or false }
end

local function onSwapClick(_, mouseButton, down)
    local swap = db().swap
    local click = { t = GetTime(), ctx = ns.Context(), inCombat = ns.CallIsTrue("InCombatLockdown"),
        button = classify(mouseButton), down = classify(down), before = weaponIDs() }
    ns.PushCapped(swap.clicks, click, ATTEMPT_CAP)
    ns.After(1, function()
        click.after = weaponIDs()
    end)
end

local function buildMacrotext(rest)
    local ids = {}
    for id in rest:gmatch("item:(%d+)") do
        ids[#ids + 1] = id
    end
    if #ids == 0 then
        for id in rest:gmatch("%d+") do
            ids[#ids + 1] = id
        end
    end
    if #ids == 1 then
        return "/equip item:" .. ids[1]
    elseif #ids >= 2 then
        return "/equipslot 16 item:" .. ids[1] .. "\n/equipslot 17 item:" .. ids[2]
    end
    return nil
end

local function restoreSwapKey(swap)
    local previous = swap.previousAction
    local hadAction = type(previous) == "string" and previous ~= ""
    if hadAction then
        swap.restore = probeCall("SetBinding", SWAP_KEY, previous)
    else
        swap.restore = probeCall("SetBinding", SWAP_KEY)
    end
    out("Restored " .. SWAP_KEY .. " to " .. (hadAction and previous or "unbound") .. ".")
end

local function runSwapButton(rest)
    local swap = db().swap
    if ns.CallIsTrue("InCombatLockdown") then
        out("Leave combat first: secure buttons and bindings cannot be changed in combat.")
        return
    end
    if rest:lower() == "restore" then
        restoreSwapKey(swap)
        return
    end
    local macrotext = buildMacrotext(rest)
    if not macrotext then
        out("Usage: /wwprobe swapbtn <main-hand link> [<off-hand link>] (shift-click items from your bags), "
            .. "or /wwprobe swapbtn restore")
        return
    end
    local setup = { at = time(), macrotext = macrotext, key = SWAP_KEY,
        keyDownCVar = probeCall("C_CVar.GetCVar", "ActionButtonUseKeyDown") }
    if swap.previousAction == nil then
        local previous = probeCall("GetBindingAction", SWAP_KEY)
        swap.previousAction = previous.ok and previous.returns[1] or ""
    end
    local button = resolve(SWAP_BUTTON)
    if not button then
        local ok, result = pcall(CreateFrame, "Button", SWAP_BUTTON, resolve("UIParent"), "SecureActionButtonTemplate")
        setup.create = { ok = ok, error = not ok and tostring(result) or nil }
        if not ok then
            swap.setup = setup
            out("Could not create the secure button: " .. tostring(result))
            return
        end
        button = result
        setup.registerForClicks = { pcall(button.RegisterForClicks, button, "AnyUp", "AnyDown") }
        setup.hook = { pcall(button.HookScript, button, "OnClick", onSwapClick) }
    end
    setup.typeAttr = { pcall(button.SetAttribute, button, "type", "macro") }
    setup.macroAttr = { pcall(button.SetAttribute, button, "macrotext", macrotext) }
    setup.bind = probeCallSafe("SetBindingClick", SWAP_KEY, SWAP_BUTTON, "LeftButton")
    setup.weapons = weaponIDs()
    swap.setup = setup
    out(string.format("Swap button ready on %s (not saved; /wwprobe swapbtn restore to undo). Equip your other "
        .. "weapon, start a fight, press %s and note whether the weapons change.", SWAP_KEY, SWAP_KEY))
end

---------------------------------------------------------------------------
-- Macros (V-29)
---------------------------------------------------------------------------

local function safeNumber(report)
    local first = report.ok and report.returns[1]
    if type(first) == "table" and first.secret == false and type(first.value) == "number" then
        return first.value
    end
    return nil
end

local function runMacro(rest)
    local macro = { at = time(), ctx = ns.Context(), inCombat = ns.CallIsTrue("InCombatLockdown"),
        counts = probeCall("GetNumMacros"), maxAccount = resolve("MAX_ACCOUNT_MACROS"),
        maxCharacter = resolve("MAX_CHARACTER_MACROS") }
    macro.existing = probeCallSafe("GetMacroIndexByName", MACRO_NAME)
    local index = safeNumber(macro.existing)
    if not index or index == 0 then
        macro.create = probeCallSafe("CreateMacro", MACRO_NAME, "INV_MISC_QUESTIONMARK", "/say " .. CHAT_TAG
            .. " macro", true)
        index = safeNumber(macro.create)
    end
    if index and index > 0 then
        macro.index = index
        macro.edit = probeCallSafe("EditMacro", index, MACRO_NAME, nil, "#showtooltip\n/cast Battle Shout")
        macro.info = probeCall("GetMacroInfo", index)
        macro.countsAfterCreate = probeCall("GetNumMacros")
        if rest:lower() ~= "keep" then
            macro.delete = probeCallSafe("DeleteMacro", index)
            macro.countsAfterDelete = probeCall("GetNumMacros")
        end
    end
    db().macro = macro
    out(string.format("Macro test: create %s, edit %s, %s. Limits: account %s, character %s.",
        index and "ok" or "FAILED", macro.edit and (macro.edit.ok and "ok" or "error") or "skipped",
        macro.delete and "deleted" or "kept", tostring(macro.maxAccount), tostring(macro.maxCharacter)))
end

---------------------------------------------------------------------------
-- /wwprobe status: what has been captured so far
---------------------------------------------------------------------------

local function runStatus()
    local data = db()
    out(string.format("events %d, CLEU seen %d (stored %d), pings %d, items %d", #data.events, data.cleu.seen,
        #data.cleu.events, #data.pings, #data.items))
    out("combat sampler " .. (data.combat.enabled and "on" or "off") .. ": " .. ns.CombatSummary()
        .. "; transitions " .. #data.combat.transitions)
    out(string.format("chat attempts %d, blocked events %d, binding presses %d, set attempts %d, swap clicks %d",
        #data.chat.attempts, #data.blocked, data.bindings.pressed or 0, #data.sets.attempts, #data.swap.clicks))
    out(string.format("dumps: static %s, spells %s, tank %s, trainer visits %d, macro %s, gear %s, prof %s",
        data.static and "yes" or "no", data.spells and "yes" or "no", data.tank and "yes" or "no", #data.trainer,
        data.macro and "yes" or "no", data.gear and "yes" or "no", data.prof and "yes" or "no"))
    out(string.format("handler errors %d", data.handlerErrors and #data.handlerErrors or 0))
end

---------------------------------------------------------------------------

local function newChat()
    return { attempts = {}, unreadableEchoes = {} }
end

table.insert(ns.onInit, function(data)
    data.chat = data.chat or newChat()
    data.blocked = data.blocked or {}
    data.bindings = data.bindings or { checks = {} }
    data.sets = data.sets or { attempts = {} }
    data.swap = data.swap or { clicks = {} }
    -- V-30: is the declared binding still bound after a relog?
    recordBindingCheck("login")
end)

table.insert(ns.onClear, function(data)
    data.chat, data.blocked = newChat(), {}
    data.bindings.checks, data.bindings.pressed = {}, nil
    data.sets = { attempts = {} }
    data.swap.clicks, data.swap.setup = {}, nil
    data.macro = nil
end)

ns.AddCommand("chat", runChat, "/wwprobe chat [channels] - send " .. CHAT_TAG
    .. " lines from a timer to PARTY/RAID/INSTANCE_CHAT/SAY/YELL (warn your group first)")
ns.AddCommand("chatkey", runChatKey, "/wwprobe chatkey - check the probe key binding (SAY from a key press)")
ns.AddCommand("sets", runSets, "/wwprobe sets [n] - list equipment sets, or apply set n (try in and out of combat)")
ns.AddCommand("swapbtn", runSwapButton,
    "/wwprobe swapbtn <link> [<link>] | restore - secure weapon-swap button on " .. SWAP_KEY)
ns.AddCommand("macro", runMacro, "/wwprobe macro [keep] - create, edit and delete a '" .. MACRO_NAME .. "' macro")
ns.AddCommand("status", runStatus, "/wwprobe status - what has been captured so far")
