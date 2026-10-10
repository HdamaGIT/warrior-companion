local addonName, ns = ...

-- Per-evaluation read model of combat state (SPEC_V2 §7.1). One snapshot table is created per compiled rule set and
-- refilled in place on every evaluation: no allocation in the hot path. All reads go through the Adapter passed in
-- (the real one or a mock), so this file touches no WoW globals.
--
-- Shape (read by Combat/Conditions.lua):
--   now, inCombat, targetExists, targetHostile, stance, rage, targetHealth, autoAttacking,
--   hasShield, targetCasting, partyMissing (always nil in M5, D-048)
--   spells[name] = { usable, noPower, cooldown, inRange }   (inRange: target only)
--   auras[unit][name] = { state, stacks, remaining, fromPlayer }
-- Player auras fall back to the AuraTracker whenever the real aura is unreadable (U-01, D-048).
local Snapshot = {}
ns.Snapshot = Snapshot

--- Creates a snapshot sized for what the rules need.
-- @param needs table { spells = { names }, auras = { { unit, name } } } (see Rules.Compile)
-- @return snapshot table
function Snapshot.New(needs)
    local snapshot = { spells = {}, auras = {} }
    for _, name in ipairs(needs.spells) do
        snapshot.spells[name] = {}
    end
    for _, pair in ipairs(needs.auras) do
        local unit, name = pair[1], pair[2]
        snapshot.auras[unit] = snapshot.auras[unit] or {}
        snapshot.auras[unit][name] = {}
    end
    return snapshot
end

local function fillSpell(entry, adapter, spellID)
    if spellID then
        entry.usable, entry.noPower = adapter.IsSpellUsable(spellID)
        entry.cooldown = adapter.GetSpellCooldownRemaining(spellID)
        entry.inRange = adapter.IsSpellInRange(spellID, "target")
    else
        entry.usable, entry.noPower, entry.cooldown, entry.inRange = nil, nil, nil, nil
    end
end

local function fillAura(entry, adapter, tracker, unit, name, now)
    local stacks, remaining, fromPlayer, duration = adapter.GetAura(unit, name, "HELPFUL")
    if unit == "player" and tracker then
        if stacks == false then
            tracker:Observe(name, now, false)
        elseif stacks ~= nil then
            tracker:Observe(name, now, true, remaining ~= math.huge and remaining or nil, duration, fromPlayer)
        end
        if stacks == nil then
            entry.state, entry.remaining, entry.fromPlayer = tracker:Get(name, now)
            entry.stacks = nil
            return
        end
    end
    if stacks == nil then
        entry.state, entry.stacks, entry.remaining, entry.fromPlayer = nil, nil, nil, nil
    elseif stacks == false then
        entry.state, entry.stacks, entry.remaining, entry.fromPlayer = false, 0, nil, nil
    else
        entry.state, entry.stacks, entry.remaining, entry.fromPlayer = true, stacks, remaining, fromPlayer
    end
end

--- Refills the snapshot. Reads only what `needs` lists.
-- @param snapshot table from Snapshot.New
-- @param needs table the same needs
-- @param adapter table Adapter (or mock)
-- @param spellIDs table { [abilityName] = spellID } (SpellMap; unknown abilities are absent)
-- @param tracker AuraTracker|nil for player auras
-- @param inCombat boolean|nil from Context
-- @param now number session time
-- Side effects: tracker observations.
function Snapshot.Update(snapshot, needs, adapter, spellIDs, tracker, inCombat, now)
    snapshot.now = now
    snapshot.inCombat = inCombat
    snapshot.targetExists, snapshot.targetHostile = adapter.GetTargetState()
    local _, stanceName = adapter.GetStance()
    snapshot.stance = stanceName
    snapshot.rage = (adapter.GetRage())
    snapshot.targetHealth = adapter.GetHealthPct("target")
    snapshot.autoAttacking = adapter.IsAutoAttacking()
    local spells = needs.spells
    for index = 1, #spells do
        local name = spells[index]
        fillSpell(snapshot.spells[name], adapter, spellIDs[name])
    end
    local auras = needs.auras
    for index = 1, #auras do
        local pair = auras[index]
        local unit, name = pair[1], pair[2]
        fillAura(snapshot.auras[unit][name], adapter, tracker, unit, name, now)
    end
end
