local addonName, ns = ...

-- Condition vocabulary (SPEC_V2 §7.1, D-019). Each evaluator is pure: (snapshot, a1, a2, a3) -> true | false | nil,
-- where nil means unknown and an unknown condition hides its rule (D-020). New conditions need a spec change.
--
-- The snapshot (Combat/Snapshot.lua) is the only input:
--   inCombat, targetExists, targetHostile, stance (name), rage, targetHealth, autoAttacking, hasShield,
--   spells[name] = { usable, noPower, cooldown, inRange },
--   auras[unit][name] = { state = true|false|nil, stacks, remaining, fromPlayer }
-- In combat rage, health and target casting are secret in Forever (D-044), so those conditions are unknown there.
local Conditions = {}
ns.Conditions = Conditions

-- Global cooldown allowance for cooldownReady: a spell whose cooldown ends within the GCD counts as ready.
Conditions.GCD = 1.5

local evaluators = {}

local function spell(snapshot, ability)
    return snapshot.spells and snapshot.spells[ability]
end

local function aura(snapshot, unit, ability)
    local byUnit = snapshot.auras and snapshot.auras[unit]
    return byUnit and byUnit[ability]
end

function evaluators.inCombat(snapshot)
    return snapshot.inCombat
end

function evaluators.outOfCombat(snapshot)
    if snapshot.inCombat == nil then
        return nil
    end
    return not snapshot.inCombat
end

-- stance(name): the current stance's name equals name.
function evaluators.stance(snapshot, name)
    if snapshot.stance == nil then
        return nil
    end
    return snapshot.stance == name
end

function evaluators.spellUsable(snapshot, ability)
    local entry = spell(snapshot, ability)
    if not entry or entry.usable == nil then
        return nil
    end
    return entry.usable
end

-- cooldownReady(ability): the cooldown ends within the GCD.
function evaluators.cooldownReady(snapshot, ability)
    local entry = spell(snapshot, ability)
    if not entry or entry.cooldown == nil then
        return nil
    end
    return entry.cooldown <= Conditions.GCD
end

function evaluators.rageAtLeast(snapshot, n)
    if snapshot.rage == nil or type(n) ~= "number" then
        return nil
    end
    return snapshot.rage >= n
end

function evaluators.targetHealthBelow(snapshot, fraction)
    if snapshot.targetHealth == nil or type(fraction) ~= "number" then
        return nil
    end
    return snapshot.targetHealth < fraction
end

-- targetHostile: false with no target; unknown if the target state cannot be read.
function evaluators.targetHostile(snapshot)
    return snapshot.targetHostile
end

-- targetCasting(interruptible): target casting is secret in combat (V-17, D-044) and not read in M5 (D-048).
function evaluators.targetCasting(snapshot, interruptible)
    local casting = snapshot.targetCasting
    if casting == nil then
        return nil
    end
    if casting == false then
        return false
    end
    if interruptible then
        return snapshot.targetCastInterruptible
    end
    return true
end

-- auraMissing(unit, ability, fromPlayer): no such aura on the unit (fromPlayer: only the player's own counts).
function evaluators.auraMissing(snapshot, unit, ability, fromPlayer)
    local entry = aura(snapshot, unit, ability)
    if not entry or entry.state == nil then
        return nil
    end
    if entry.state == false then
        return true
    end
    if fromPlayer and entry.fromPlayer == false then
        return true
    end
    return false
end

-- auraExpiringWithin(unit, ability, seconds): present with at most `seconds` left.
function evaluators.auraExpiringWithin(snapshot, unit, ability, seconds)
    local entry = aura(snapshot, unit, ability)
    if not entry or entry.state == nil or type(seconds) ~= "number" then
        return nil
    end
    if entry.state == false then
        return false
    end
    if entry.remaining == nil then
        return nil
    end
    return entry.remaining <= seconds
end

-- auraStacksBelow(unit, ability, n): absent counts as 0 stacks.
function evaluators.auraStacksBelow(snapshot, unit, ability, n)
    local entry = aura(snapshot, unit, ability)
    if not entry or entry.state == nil or type(n) ~= "number" then
        return nil
    end
    if entry.state == false then
        return n > 0
    end
    if entry.stacks == nil then
        return nil
    end
    return entry.stacks < n
end

-- inRange(ability, unit) / notInRange(ability, unit). Only the target's range is read in M5.
function evaluators.inRange(snapshot, ability, unit)
    if unit ~= nil and unit ~= "target" then
        return nil
    end
    local entry = spell(snapshot, ability)
    if not entry or entry.inRange == nil then
        return nil
    end
    return entry.inRange
end

function evaluators.notInRange(snapshot, ability, unit)
    local inRange = evaluators.inRange(snapshot, ability, unit)
    if inRange == nil then
        return nil
    end
    return not inRange
end

function evaluators.autoAttacking(snapshot, wanted)
    if snapshot.autoAttacking == nil then
        return nil
    end
    return snapshot.autoAttacking == (wanted ~= false)
end

-- hasShield(bool): equipped-weapon reads arrive in M8 (D-048), so this stays unknown until then.
function evaluators.hasShield(snapshot, wanted)
    if snapshot.hasShield == nil then
        return nil
    end
    return snapshot.hasShield == (wanted ~= false)
end

-- partyMissingAura(ability, minCount): party reads are M6 and out of combat only (U-02); unknown until then.
function evaluators.partyMissingAura(snapshot, ability, minCount)
    local missing = snapshot.partyMissing and snapshot.partyMissing[ability]
    if missing == nil or type(minCount) ~= "number" then
        return nil
    end
    return missing >= minCount
end

Conditions.evaluators = evaluators

--- Whether a condition name is part of the vocabulary.
-- @param name string
-- @return boolean
function Conditions.Exists(name)
    return evaluators[name] ~= nil
end

--- Evaluates one condition. Pure.
-- @param name string condition name
-- @param snapshot table
-- @param a1, a2, a3 condition arguments
-- @return true | false | nil (unknown; also nil for a name outside the vocabulary)
function Conditions.Evaluate(name, snapshot, a1, a2, a3)
    local evaluator = evaluators[name]
    if not evaluator then
        return nil
    end
    return evaluator(snapshot, a1, a2, a3)
end

--- Evaluates a compiled condition list with three-valued AND: any false -> false; else any unknown -> nil;
-- else true. An empty list is true. Pure; no allocation.
-- @param list array of { fn, a1, a2, a3 } (see Rules.Compile)
-- @param snapshot table
-- @return true | false | nil
function Conditions.All(list, snapshot)
    local unknown = false
    for index = 1, #list do
        local condition = list[index]
        local result = condition[1](snapshot, condition[2], condition[3], condition[4])
        if result == false then
            return false
        elseif result == nil then
            unknown = true
        end
    end
    if unknown then
        return nil
    end
    return true
end
