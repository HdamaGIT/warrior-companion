-- Fake WoW client for loading WarriorWorkshopProbe in busted. The probe is the one add-on that touches WoW
-- globals directly, so it is tested as a whole inside a sandbox environment (setfenv) rather than with the
-- mock Adapter. Nothing here claims to match Forever: the stubs only exercise the probe's code paths.
--
-- Modes:
--   "full"     APIs exist and return plausible plain values.
--   "missing"  only the frame, timer, chat-frame and slash plumbing exist; every data API is absent.
--   "secret"   APIs exist but every data value is a secret proxy that errors on any use except type().
--   "nochecker" like "full", but issecretvalue does not exist.

local C = {}

local PROBE_FILES = { "Probe.lua", "Dumps.lua", "Combat.lua", "Actions.lua" }
C.PROBE_FILES = PROBE_FILES

-- Secret proxy: errors on indexing, arithmetic, concatenation, ordering, length, call and tostring.
local function secretError()
    error("attempt to use a secret value", 2)
end
local secretPrototype = newproxy(true)
do
    local meta = getmetatable(secretPrototype)
    for _, event in ipairs({ "__index", "__newindex", "__add", "__sub", "__mul", "__div", "__mod", "__pow",
        "__unm", "__concat", "__len", "__lt", "__le", "__call", "__tostring" }) do
        meta[event] = secretError
    end
end
local secretSet = setmetatable({}, { __mode = "k" })

--- Returns a new secret proxy.
function C.Secret()
    local value = newproxy(secretPrototype)
    secretSet[value] = true
    return value
end

--- True if value is a secret proxy created by this helper.
function C.IsSecret(value)
    return type(value) == "userdata" and secretSet[value] == true
end

--- Walks a table and returns the path of the first secret proxy found, or nil.
function C.FindSecret(tbl, path, seen)
    path = path or "db"
    seen = seen or {}
    if C.IsSecret(tbl) then
        return path
    end
    if type(tbl) ~= "table" or seen[tbl] then
        return nil
    end
    seen[tbl] = true
    for key, value in pairs(tbl) do
        if C.IsSecret(key) then
            return path .. "[<secret key>]"
        end
        local found = C.FindSecret(value, path .. "." .. tostring(key), seen)
        if found then
            return found
        end
    end
    return nil
end

local function makeFrame(client, frameType, name)
    local frame = { frameType = frameType, name = name, scripts = {}, hooks = {}, attributes = {},
        events = {}, units = {} }
    function frame:RegisterEvent(event)
        if client.forbiddenEvents[event] then
            error("Attempt to register unknown event \"" .. event .. "\"")
        end
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event, unit1, unit2)
        self:RegisterEvent(event)
        self.units[event] = { [unit1] = true }
        if unit2 then
            self.units[event][unit2] = true
        end
    end
    function frame:SetScript(script, fn)
        self.scripts[script] = fn
    end
    function frame:HookScript(script, fn)
        self.hooks[script] = fn
    end
    function frame:SetAttribute(key, value)
        self.attributes[key] = value
    end
    function frame:RegisterForClicks(...)
        self.clicks = { ... }
    end
    function frame:Click(mouseButton, down)
        if self.hooks.OnClick then
            self.hooks.OnClick(self, mouseButton or "LeftButton", down)
        end
    end
    client.frames[#client.frames + 1] = frame
    return frame
end

--- Builds a client sandbox.
-- @param mode string "full" | "missing" | "secret" | "nochecker"
-- @return client { env, frames, chat (printed lines), sent (chat sends), Fire, RunTimers, Tick, Slash, Load }
function C.New(mode)
    mode = mode or "full"
    local client = { mode = mode, frames = {}, timers = {}, tickers = {}, printed = {}, sent = {},
        forbiddenEvents = {}, now = 1000, hardware = false, inCombatLockdown = false, equipped = { [16] = 11 } }
    local env = {}
    client.env = env
    for _, name in ipairs({ "string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
        "select", "pcall", "error", "unpack", "next", "setmetatable", "getmetatable", "rawget", "rawset",
        "print", "assert", "newproxy" }) do
        env[name] = _G[name]
    end
    env._G = env
    env.time = function()
        return 1700000000
    end
    env.GetTime = function()
        return client.now
    end
    env.CreateFrame = function(frameType, name)
        local frame = makeFrame(client, frameType, name)
        if name then
            env[name] = frame
        end
        return frame
    end
    env.UIParent = {}
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
        client.printed[#client.printed + 1] = msg
    end }
    env.SlashCmdList = {}
    env.C_Timer = {
        After = function(delay, fn)
            client.timers[#client.timers + 1] = { at = client.now + delay, fn = fn }
        end,
        NewTicker = function(_, fn)
            local ticker = { fn = fn }
            function ticker.Cancel(self)
                self.cancelled = true
            end
            client.tickers[#client.tickers + 1] = ticker
            return ticker
        end,
    }
    if mode ~= "missing" then
        C.InstallApis(client)
    end
    return client
end

--- Installs the data APIs (full, secret and nochecker modes).
function C.InstallApis(client)
    local env, mode = client.env, client.mode
    local secret = mode == "secret"
    -- v(x) returns x, or a secret proxy in secret mode.
    local function v(x)
        if secret and x ~= nil then
            return C.Secret()
        end
        return x
    end
    if mode ~= "nochecker" then
        env.issecretvalue = function(value)
            return C.IsSecret(value)
        end
    end
    env.GetBuildInfo = function()
        return "12.1.5", "60000", "Oct 1 2026", 120105
    end
    env.InCombatLockdown = function()
        return v(client.inCombatLockdown)
    end
    env.UnitName = function()
        return v("Hugh")
    end
    env.UnitGUID = function()
        return v("Player-1-0001")
    end
    env.IsInGroup = function()
        return v(true)
    end
    env.IsInRaid = function()
        return v(false)
    end
    env.IsInInstance = function()
        return v(false), v("none")
    end
    env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
    env.UnitAffectingCombat = function()
        return v(true)
    end
    env.UnitCanAttack = function()
        return v(true)
    end
    env.UnitExists = function()
        return v(true)
    end
    env.UnitInRange = function()
        return v(true), v(true)
    end
    env.UnitHealth = function()
        return v(500)
    end
    env.UnitHealthMax = function()
        return v(1000)
    end
    env.UnitPower = function()
        return v(30)
    end
    env.UnitPowerMax = function()
        return v(100)
    end
    env.UnitLevel = function()
        return v(12)
    end
    env.UnitCastingInfo = function()
        return v("Heal"), v(""), v(1), v(1000), v(2000), v(false), v(7), v(false), v(2061)
    end
    env.GetShapeshiftForm = function()
        return v(1)
    end
    env.IsEncounterInProgress = function()
        return v(false)
    end
    env.CombatLogGetCurrentEventInfo = function()
        return v(1), v("SWING_MISSED"), v(false), v("Creature-1"), v("Mob"), v(0), v(0), v("Player-1-0001"),
            v("Hugh"), v(0), v(0), v("PARRY"), v(false), v(0)
    end
    local usableToggle = false
    env.C_Spell = {
        GetSpellCooldown = function()
            if secret then
                return C.Secret()
            end
            return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
        end,
        IsSpellUsable = function(name)
            if name == "Overpower" then
                usableToggle = not usableToggle
                return v(usableToggle), v(false)
            end
            return v(true), v(false)
        end,
        IsSpellInRange = function()
            return v(true)
        end,
        IsCurrentSpell = function()
            return v(false)
        end,
        GetSpellInfo = function(name)
            if name == "Charge" then
                return { name = "Charge", spellID = 100 }
            end
            return nil
        end,
    }
    env.IsPlayerSpell = function()
        return true
    end
    env.IsSpellKnown = function()
        return true
    end
    env.C_UnitAuras = {
        GetAuraDataBySpellName = function()
            -- A plain table whose fields may be secret.
            return { applications = v(0), duration = v(120), expirationTime = v(500), name = v("Battle Shout"),
                spellId = v(6673), sourceUnit = v("player"), icon = 1 }
        end,
        GetAuraDataByIndex = function()
            return nil
        end,
    }
    env.C_SpellBook = {
        GetNumSpellBookSkillLines = function()
            return 2
        end,
        GetSpellBookSkillLineInfo = function(line)
            return { name = "Line" .. line, itemIndexOffset = (line - 1) * 3, numSpellBookItems = 3 }
        end,
        GetSpellBookItemInfo = function(index)
            return { name = "Spell" .. index, spellID = index, itemType = 1 }
        end,
    }
    env.Enum = { SpellBookSpellBank = { Player = 0 }, BagIndex = { Backpack = 0 } }
    env.GetNumShapeshiftForms = function()
        return 3
    end
    env.GetShapeshiftFormInfo = function(index)
        return 1, index == 1, true, 2457
    end
    env.GetNumTrainerServices = function()
        return 2
    end
    env.GetTrainerServiceInfo = function()
        return "Rend", "Rank 2", "available"
    end
    env.GetTrainerServiceLevelReq = function()
        return 10
    end
    env.GetDodgeChance = function()
        return v(5.2)
    end
    env.UnitStat = function()
        return v(20), v(20), v(0), v(0)
    end
    env.CR_DODGE = 3
    env.GetCombatRating = function()
        return v(12)
    end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function()
            return true
        end,
        SendAddonMessage = function()
            return v(true)
        end,
        SendChatMessage = function(text, channel)
            client.sent[#client.sent + 1] = { text = text, channel = channel, hardware = client.hardware }
            if (channel == "SAY" or channel == "YELL") and not client.hardware then
                C.Fire(client, "ADDON_ACTION_BLOCKED", "WarriorWorkshopProbe", "SendChatMessage")
            else
                C.Fire(client, "CHAT_MSG_" .. channel, secret and C.Secret() or text, "Hugh")
            end
        end,
    }
    env.C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            return { 1, 2 }
        end,
        GetEquipmentSetInfo = function(setID)
            return "Set" .. setID, 132, setID
        end,
        CanUseEquipmentSets = function()
            return true
        end,
        UseEquipmentSet = function(setID)
            client.equipped[16] = 100 + setID
            return true
        end,
        GetItemIDs = function(setID)
            return { [16] = 100 + setID }
        end,
    }
    env.GetInventoryItemID = function(_, slot)
        return v(client.equipped[slot])
    end
    env.GetBindingAction = function()
        return ""
    end
    env.GetBindingKey = function()
        return "F12"
    end
    env.SetBindingClick = function()
        return true
    end
    env.SetBinding = function()
        return true
    end
    env.C_CVar = { GetCVar = function()
        return "1"
    end }
    env.MAX_ACCOUNT_MACROS, env.MAX_CHARACTER_MACROS = 120, 30
    env.GetNumMacros = function()
        return 5, 2
    end
    env.GetMacroIndexByName = function()
        return 0
    end
    env.CreateMacro = function()
        return 121
    end
    env.EditMacro = function(index)
        return index
    end
    env.GetMacroInfo = function()
        return "WW Probe", 134400, "/cast Battle Shout"
    end
    env.DeleteMacro = function() end
end

--- Fires a game event at every frame registered for it (respecting unit filters).
function C.Fire(client, event, ...)
    local unit = ...
    for _, frame in ipairs(client.frames) do
        local filter = frame.units[event]
        local unitOk = not filter or (type(unit) == "string" and filter[unit])
        if frame.events[event] and unitOk and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

--- Advances time and runs due C_Timer.After callbacks (including ones they schedule).
function C.RunTimers(client, seconds)
    client.now = client.now + (seconds or 60)
    for _ = 1, 100 do
        local due
        for index, timer in ipairs(client.timers) do
            if timer.at <= client.now then
                due = table.remove(client.timers, index)
                break
            end
        end
        if not due then
            return
        end
        due.fn()
    end
end

--- Runs every active ticker n times.
function C.Tick(client, n)
    for _ = 1, n or 1 do
        for _, ticker in ipairs(client.tickers) do
            if not ticker.cancelled then
                ticker.fn()
            end
        end
    end
end

--- Loads the probe files in .toc order into the sandbox, then fires PLAYER_LOGIN.
function C.Load(client)
    local ns = {}
    client.ns = ns
    for _, file in ipairs(PROBE_FILES) do
        local chunk = assert(loadfile("WarriorWorkshopProbe/" .. file))
        setfenv(chunk, client.env)
        chunk("WarriorWorkshopProbe", ns)
    end
    C.Fire(client, "PLAYER_LOGIN")
    return ns
end

--- Runs a /wwprobe command.
function C.Slash(client, text)
    client.env.SlashCmdList.WWPROBE(text)
end

return C
