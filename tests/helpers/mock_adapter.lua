-- Fake Adapter for module tests: same surface as WarriorWorkshop/Core/Adapter.lua, returning fixture
-- tables, plus a fake event frame and a manual timer. No WoW globals are involved.
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
        timers = {},
        clock = 0,
        wallTime = data.time or 1700000000,
        timerSeq = 0,
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
        return adapter.clock
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

    -- Fake timer. After() records; advance(dt) runs what has become due; flush() runs everything pending.
    function adapter.After(delay, fn)
        if adapter.failAfter then
            return nil
        end
        adapter.timerSeq = adapter.timerSeq + 1
        adapter.timers[#adapter.timers + 1] = { due = adapter.clock + delay, seq = adapter.timerSeq, fn = fn }
        return true
    end

    -- Removes and returns the earliest timer due at or before limit (any timer if limit is nil).
    local function popEarliest(limit)
        local best
        for index, timer in ipairs(adapter.timers) do
            if limit == nil or timer.due <= limit then
                local current = best and adapter.timers[best]
                if not current or timer.due < current.due or (timer.due == current.due and timer.seq < current.seq) then
                    best = index
                end
            end
        end
        if best then
            return table.remove(adapter.timers, best)
        end
        return nil
    end

    function adapter.advance(seconds)
        local target = adapter.clock + seconds
        local timer = popEarliest(target)
        while timer do
            adapter.clock = math.max(adapter.clock, timer.due)
            timer.fn()
            timer = popEarliest(target)
        end
        adapter.clock = target
    end

    function adapter.flush()
        local timer = popEarliest(nil)
        while timer do
            adapter.clock = math.max(adapter.clock, timer.due)
            timer.fn()
            timer = popEarliest(nil)
        end
    end

    function adapter.pendingTimers()
        return #adapter.timers
    end

    return adapter
end

return M
