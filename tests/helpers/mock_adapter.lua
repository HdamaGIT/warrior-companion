-- Fake Adapter for module tests: same surface as WarriorWorkshop/Core/Adapter.lua, returning fixture
-- tables, plus a fake event frame and a manual timer. No WoW globals are involved.
local MockClock = dofile("tests/helpers/mock_clock.lua")

local M = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = deepCopy(item)
    end
    return copy
end

--- A fake event frame. Records registrations; tests deliver events with frame:Fire(event, ...).
-- Set frame.rejectEvents = { [event] = true } to make RegisterEvent raise, like an unknown event does.
function M.newFrame()
    local frame = { registered = {}, scripts = {}, registerCalls = {} }
    function frame:RegisterEvent(event)
        self.registerCalls[#self.registerCalls + 1] = event
        if self.rejectEvents and self.rejectEvents[event] then
            error("unknown event " .. event)
        end
        self.registered[event] = true
    end
    function frame:UnregisterEvent(event)
        self.registered[event] = nil
    end
    function frame:SetScript(name, fn)
        self.scripts[name] = fn
    end
    function frame:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then
            handler(self, event, ...)
        end
    end
    return frame
end

--- Builds a mock adapter. data (all optional): buildInfo, addonVersion, inCombat, bags, bank, equipped,
-- durability, itemStats = { [link] = stats }, itemBasics = { [itemID] = basics }, usable = { [itemID] = bool },
-- openProfession, recipes, equipmentSets, playerMeta, time,
-- zoneKind, groupKind, dead, encounter, challengeMode, spellIDs = { [name] = id }, knownSpells = { [id] = bool }.
-- Fields can be changed on adapter.data after creation.
function M.new(data)
    data = data or {}
    local adapter = {
        printed = {},
        frames = {},
        sounds = {},
        clockObj = MockClock.new(data.now or 0),
        wallTime = data.time or 1700000000,
        failAfter = false,
        data = data,
    }

    function adapter.Print(msg)
        adapter.printed[#adapter.printed + 1] = tostring(msg)
    end
    function adapter.GetBuildInfo()
        return deepCopy(data.buildInfo) or { version = "12.0.5", build = "66666", interface = 120105 }
    end
    function adapter.GetAddOnVersion()
        return data.addonVersion or "0.0.1"
    end
    function adapter.Time()
        return adapter.wallTime
    end
    function adapter.Now()
        return adapter.clockObj.now
    end
    function adapter.InCombat()
        return data.inCombat == true
    end
    function adapter.GetPlayerMeta()
        return deepCopy(data.playerMeta)
    end
    function adapter.GetBagContents()
        return deepCopy(data.bags)
    end
    function adapter.GetBankContents()
        return deepCopy(data.bank)
    end
    function adapter.GetEquipped()
        return deepCopy(data.equipped)
    end
    function adapter.GetDurability()
        return deepCopy(data.durability)
    end
    function adapter.GetItemStats(link)
        return deepCopy(data.itemStats and data.itemStats[link])
    end
    function adapter.GetItemBasics(itemID, cb)
        cb(deepCopy(data.itemBasics and data.itemBasics[itemID]))
    end
    function adapter.IsUsableByPlayer(itemID)
        return data.usable ~= nil and data.usable[itemID] == true
    end
    function adapter.GetOpenProfession()
        return deepCopy(data.openProfession)
    end
    function adapter.GetKnownRecipes()
        return deepCopy(data.recipes)
    end
    function adapter.GetEquipmentSets()
        return deepCopy(data.equipmentSets)
    end
    function adapter.GetZoneKind()
        return data.zoneKind or "openWorld"
    end
    function adapter.GetGroupKind()
        return data.groupKind or "solo"
    end
    function adapter.IsPlayerDead()
        return data.dead == true
    end
    function adapter.IsEncounterInProgress()
        return data.encounter
    end
    function adapter.IsChallengeModeActive()
        return data.challengeMode
    end
    function adapter.GetSpellIDByName(name)
        return data.spellIDs and data.spellIDs[name]
    end
    function adapter.IsPlayerSpell(spellID)
        if data.knownSpells == nil then
            return true
        end
        return data.knownSpells[spellID] == true
    end

    -- Event frame: every call returns a new fake frame; the latest is adapter.frame.
    function adapter.CreateEventFrame()
        local frame = M.newFrame()
        adapter.frames[#adapter.frames + 1] = frame
        adapter.frame = frame
        return frame
    end

    -- Fake timer on a manual clock (tests/helpers/mock_clock.lua). After() records; advance(dt) runs what has become
    -- due; flush() runs everything pending.
    function adapter.After(delay, fn)
        if adapter.failAfter then
            return nil
        end
        adapter.clockObj.after(delay, fn)
        return true
    end
    function adapter.advance(seconds)
        adapter.clockObj.advance(seconds)
    end
    function adapter.flush()
        adapter.clockObj.flush()
    end
    function adapter.pendingTimers()
        return adapter.clockObj.pending()
    end

    M.installCombat(adapter)

    return adapter
end

--- Installs the combat accessors (SPEC_V2 §5.4, D-048) on a mock adapter. They read adapter.data:
--   combat = {
--     rage, rageMax, health = { [unit] = 0..1 },
--     usable = { [spellID] = bool }, noPower = { [spellID] = bool },
--     cooldowns = { [spellID] = seconds remaining } (a spell in `usable` without an entry is ready: 0),
--     inRange = { [spellID] = bool }, autoAttacking = bool,
--     auras = { [unit] = { [auraName] = false | { stacks, expires, duration, fromPlayer } } }
--       (expires is clock time; nil means permanent),
--     target = { exists, hostile }, stance = { index, name },
--   }
--   secrecy = "none" (default) | "run2" | "all"
--     "run2": what beta run 2 saw (D-044): rage and health always secret; in combat (data.inCombat) auras and
--             cooldown times are secret (cooldown falls back to isActive: ready stays 0, cooling down is unknown).
--     "all":  secret mode (SPEC_V2 §13): every combat accessor and normalised event returns nil.
--   restriction = { encounter, challengeMode, pvpMatch }, spellNames = { [spellID] = name }.
-- Unknown is nil throughout, as in the real Adapter.
function M.installCombat(adapter)
    local data = adapter.data

    local function all()
        return data.secrecy == "all"
    end
    local function run2()
        return data.secrecy == "run2"
    end
    local function combat()
        return data.combat or {}
    end

    function adapter.SetSecretFallback(assumeSecret)
        adapter.secretFallback = assumeSecret
    end

    function adapter.GetRestrictionFlags()
        local r = data.restriction or {}
        return r.encounter == true, r.challengeMode == true, r.pvpMatch == true
    end

    function adapter.GetRage()
        local c = combat()
        if all() or run2() or c.rage == nil then
            return nil
        end
        return c.rage, c.rageMax or 100
    end

    function adapter.GetHealthPct(unit)
        local c = combat()
        if all() or run2() or c.health == nil then
            return nil
        end
        return c.health[unit]
    end

    function adapter.IsSpellUsable(spellID)
        local c = combat()
        local usable = c.usable and c.usable[spellID]
        if all() or usable == nil then
            return nil
        end
        return usable, (c.noPower and c.noPower[spellID]) == true
    end

    function adapter.GetSpellCooldownRemaining(spellID)
        local c = combat()
        if all() then
            return nil
        end
        local remaining = c.cooldowns and c.cooldowns[spellID]
        if remaining == nil then
            if c.usable and c.usable[spellID] ~= nil then
                remaining = 0
            else
                return nil
            end
        end
        if run2() and data.inCombat and remaining > 0 then
            return nil
        end
        return remaining
    end

    function adapter.IsSpellInRange(spellID, unit)
        local c = combat()
        if all() or unit ~= "target" or c.inRange == nil then
            return nil
        end
        return c.inRange[spellID]
    end

    function adapter.IsAutoAttacking()
        if all() then
            return nil
        end
        return combat().autoAttacking
    end

    function adapter.GetAura(unit, auraName)
        local c = combat()
        if all() or (run2() and data.inCombat) then
            return nil
        end
        local byUnit = c.auras and c.auras[unit]
        if byUnit == nil then
            return nil
        end
        local aura = byUnit[auraName]
        if not aura then
            return false
        end
        local remaining = math.huge
        if aura.expires then
            remaining = aura.expires - adapter.Now()
            if remaining <= 0 then
                return false
            end
        end
        return aura.stacks or 0, remaining, aura.fromPlayer, aura.duration
    end

    function adapter.GetTargetState()
        local target = combat().target
        if all() or target == nil then
            return nil
        end
        return target.exists == true, target.exists == true and target.hostile == true
    end

    function adapter.GetStance()
        local stance = combat().stance
        if all() or stance == nil then
            return nil
        end
        return stance.index, stance.name
    end

    function adapter.GetSpellName(spellID)
        if data.spellNames and data.spellNames[spellID] then
            return data.spellNames[spellID]
        end
        for name, id in pairs(data.spellIDs or {}) do
            if id == spellID then
                return name
            end
        end
        return nil
    end

    function adapter.GetSpellIcon(spellID)
        if type(spellID) ~= "number" then
            return nil
        end
        return 130000 + spellID
    end

    function adapter.PlaySound(kitName)
        adapter.sounds[#adapter.sounds + 1] = kitName
        return true
    end

    -- Normalised events (SPEC_V2 §5.5). Plain pass-through unless in secret mode.
    function adapter.ReadUnitCombat(unit, action, descriptor, amount)
        if all() then
            return nil
        end
        return unit, action, descriptor, amount
    end

    function adapter.ReadSpellcast(unit, _, spellID)
        if all() then
            return nil
        end
        return unit, spellID
    end
end

return M
