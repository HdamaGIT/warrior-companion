local addonName, ns = ...

-- Avoidance detector (SPEC_V2 §7.4, D-027, D-035): the single consumer of UNIT_COMBAT. One detector, two consumers:
-- local combat text (X-06, off the launch target, D-043) and the announcer (M7).
--   player unit + DODGE/PARRY/BLOCK/MISS...  -> "incoming": the player avoided an attack
--   target unit + the same actions           -> "outgoing": the target avoided the player's attack
--   WOUND with a BLOCK_REDUCED descriptor    -> a partial block (run 2 saw it on the target)
-- Ability resists come from pairing an own cast of a listed ability with the next avoidance on the target within
-- PAIR_WINDOW seconds [VERIFY V-16: no resist observed yet]. UNIT_COMBAT carries no attacker identity.
--
-- Publishes WW_AVOIDANCE(direction, kind, partial, amount) and WW_PLAYER_SPELL_MISSED(abilityName, kind).
-- Suspends while restricted (D-021).
local Adapter = ns.Adapter
local Events = ns.Events
local Log = ns.Log

local Avoidance = ns:NewModule("Avoidance")
ns.Avoidance = Avoidance

-- Actions that mean "the attack did not land". Only PARRY and MISS were seen in run 2; the rest are ASSUMED names.
Avoidance.AVOID_ACTIONS = {
    DODGE = "dodge", PARRY = "parry", BLOCK = "block", MISS = "miss", RESIST = "resist", IMMUNE = "immune",
    EVADE = "evade", DEFLECT = "deflect",
}

-- Seconds between an own cast and the target's avoidance for them to count as one event. Placeholder: run 2 shows an
-- ability's hit arriving at the cast's own timestamp. [VERIFY V-16]
Avoidance.PAIR_WINDOW = 0.5

-- Abilities whose resist or avoidance is worth reporting (SPEC_V2 §7.4). Names in the game's US spelling.
Avoidance.PAIRED_ABILITIES = {
    Taunt = true, ["Mocking Blow"] = true, Disarm = true, ["Intimidating Shout"] = true, Pummel = true,
    ["Shield Bash"] = true,
}

--- Classifies one UNIT_COMBAT event. Pure.
-- @param unit string "player" | "target" (others are ignored)
-- @param action string e.g. "PARRY", "WOUND"
-- @param descriptor string|nil e.g. "", "CRITICAL", "BLOCK_REDUCED"
-- @return direction ("incoming"|"outgoing"), kind ("parry", "dodge", "block", ...), partial (boolean); nil if the
--   event is not an avoidance
function Avoidance.Classify(unit, action, descriptor)
    local direction
    if unit == "player" then
        direction = "incoming"
    elseif unit == "target" then
        direction = "outgoing"
    else
        return nil
    end
    local kind = Avoidance.AVOID_ACTIONS[action]
    if kind then
        return direction, kind, false
    end
    if action == "WOUND" and type(descriptor) == "string" and string.find(descriptor, "BLOCK", 1, true) then
        return direction, "block", true
    end
    return nil
end

local Detector = {}
Detector.__index = Detector

--- Creates a detector. Pure; time is passed in.
-- @param window number|nil pairing window in seconds (default PAIR_WINDOW)
-- @param paired table|nil { [abilityName] = true } (default PAIRED_ABILITIES)
-- @return detector
function Avoidance.NewDetector(window, paired)
    return setmetatable({ window = window or Avoidance.PAIR_WINDOW, paired = paired or Avoidance.PAIRED_ABILITIES,
        castName = nil, castAt = nil }, Detector)
end

--- Records an own successful cast.
-- @param name string|nil ability name
-- @param now number
function Detector:OnCast(name, now)
    if name and self.paired[name] then
        self.castName, self.castAt = name, now
    end
end

--- Processes one normalised UNIT_COMBAT event.
-- @return direction, kind, partial, missedAbility (the paired ability the target avoided, or nil); nil if not an
--   avoidance
function Detector:OnUnitCombat(now, unit, action, descriptor)
    local pending = self.castName
    if pending and now - self.castAt > self.window then
        self.castName, pending = nil, nil
    end
    local direction, kind, partial = Avoidance.Classify(unit, action, descriptor)
    if unit == "target" and pending then
        self.castName = nil -- the next target event settles the cast, hit or not
        if direction and not partial then
            return direction, kind, partial, pending
        end
    end
    if not direction then
        return nil
    end
    return direction, kind, partial, nil
end

Avoidance.Detector = Detector

-- Module wiring -------------------------------------------------------------------------------------------------

function Avoidance:OnInitialize()
    self.detector = Avoidance.NewDetector()
end

local function suspended()
    return ns.Context and ns.Context:IsRestricted()
end

function Avoidance:OnUnitCombat(...)
    if suspended() then
        return
    end
    local unit, action, descriptor, amount = Adapter.ReadUnitCombat(...)
    if unit ~= "player" and unit ~= "target" then
        return
    end
    local direction, kind, partial, missed = self.detector:OnUnitCombat(Adapter.Now(), unit, action, descriptor)
    if direction then
        if Log.IsDebug() then -- the in-game check reads these (no combat text in M5, D-043)
            Log.Debug(string.format("avoidance: %s %s%s", direction, kind, partial and " (partial)" or ""))
        end
        Events:Fire("WW_AVOIDANCE", direction, kind, partial, amount)
    end
    if missed then
        if Log.IsDebug() then
            Log.Debug(string.format("avoidance: %s %s", tostring(missed), kind))
        end
        Events:Fire("WW_PLAYER_SPELL_MISSED", missed, kind)
    end
end

function Avoidance:OnSpellcastSucceeded(...)
    if suspended() then
        return
    end
    local unit, spellID = Adapter.ReadSpellcast(...)
    if unit ~= "player" then
        return
    end
    self.detector:OnCast(Adapter.GetSpellName(spellID), Adapter.Now())
end

--- PLAYER_LOGIN: subscribes to UNIT_COMBAT and own casts.
-- Side effects: event subscriptions.
function Avoidance:OnEnable()
    Events:On("UNIT_COMBAT", self, "OnUnitCombat")
    Events:On("UNIT_SPELLCAST_SUCCEEDED", self, "OnSpellcastSucceeded")
end
