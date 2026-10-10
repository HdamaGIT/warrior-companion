local addonName, ns = ...

-- Combat companion wiring (SPEC_V2 §7, D-048): game events and one shared 0.2s ticker drive
-- Snapshot -> Rules -> WW_ALERTS_UPDATED. Pure logic lives in Conditions, Snapshot, Rules and AuraTracker; this module
-- only connects them to the event bus, the Adapter, the SpellMap, Context and the character's sparse overrides.
--
-- Messages:
--   WW_ALERTS_UPDATED(alerts, count)  alerts is a reused array of reused entries { id, label, ability, spellID,
--                                     display, state, severity, remaining }; read it, do not keep it
--   WW_COMBAT_SUSPENDED(suspended)    restricted context entered or left (D-021); the HUD shows its badge
--   WW_COMBAT_ENABLED(enabled)        /ww hud on|off
-- The ticker is a chain of Adapter.After calls (no OnUpdate) and runs only while in combat, with a hostile target,
-- or while an alert is showing or waiting on a delay.
local Adapter = ns.Adapter
local AuraTracker = ns.AuraTracker
local DB = ns.DB
local Events = ns.Events
local L = ns.L
local Log = ns.Log
local Rules = ns.Rules
local Snapshot = ns.Snapshot

local Companion = ns:NewModule("Companion")
ns.Companion = Companion

Companion.TICK = 0.2
-- Small margin so a wake-up for an aura threshold lands just after it, not just before.
local WAKE_MARGIN = 0.05

local function characterCombat()
    local character = DB.GetCharacter()
    return character and character.combat
end

--- Whether the companion is switched on (combat.enabled; /ww hud on|off).
-- @return boolean
function Companion:IsEnabled()
    local combat = characterCombat()
    return not (combat and combat.enabled == false)
end

--- Whether alerts are suspended: switched off, or a restricted context (D-021, D-045).
-- @return boolean
function Companion:IsSuspended()
    return not self:IsEnabled() or ns.Context:Current().restricted
end

--- Rebuilds the compiled rules from the pack, the SpellMap and the character's overrides, then evaluates.
-- Side effects: replaces compiled rules and snapshot; logs disabled rules (debug); may fire WW_ALERTS_UPDATED.
function Companion:Recompile()
    local combat = characterCombat()
    local compiled = Rules.Compile(self.pack, combat and combat.ruleOverrides, ns.SpellMap.ids)
    self.compiled = compiled
    self.snapshot = Snapshot.New(compiled.needs)
    self.trackedAuras = {}
    for _, pair in ipairs(compiled.needs.auras) do
        if pair[1] == "player" then
            self.trackedAuras[pair[2]] = true
        end
    end
    for _, item in ipairs(compiled.disabled) do
        Log.Debug(string.format(L.RULE_DISABLED, tostring(item.id), L.RULE_REASONS[item.reason] or item.reason,
            item.detail or ""))
    end
    self.lastCount = nil
    self:Evaluate()
end

local function publish(self, count)
    if count == 0 and self.lastCount == 0 then
        return
    end
    self.lastCount = count
    Events:Fire("WW_ALERTS_UPDATED", self.out, count)
end

--- Reads the snapshot, runs the rules and publishes when anything visible changed. Keeps the ticker running while
-- it is needed and schedules a wake-up for aura thresholds when it is not.
-- Side effects: may fire WW_ALERTS_UPDATED; schedules timers.
function Companion:Evaluate()
    local compiled = self.compiled
    if not compiled then
        return
    end
    if self:IsSuspended() then
        Rules.Reset(compiled)
        for index = #self.out, 1, -1 do
            self.out[index] = nil
        end
        publish(self, 0)
        return
    end
    local now = Adapter.Now()
    local context = ns.Context:Current()
    Snapshot.Update(self.snapshot, compiled.needs, Adapter, ns.SpellMap.ids, self.tracker, context.inCombat, now)
    local count, changed, retryIn = Rules.Evaluate(compiled, self.snapshot, context, now, self.out)
    if changed or self.lastCount == nil then
        publish(self, count)
    end
    local snapshot = self.snapshot
    if context.inCombat or snapshot.targetHostile or count > 0 then
        self:StartTicker()
    elseif retryIn then
        self:WakeIn(retryIn + WAKE_MARGIN)
    end
end

--- Starts the shared ticker if it is not running. It stops itself when no longer needed.
-- Side effects: schedules timers.
function Companion:StartTicker()
    if self.ticking then
        return
    end
    self.ticking = true
    Adapter.After(Companion.TICK, self.tickFn)
end

function Companion:Tick()
    self.ticking = false
    self:Evaluate() -- restarts the ticker if it is still needed
end

--- Schedules one evaluation after `seconds`, unless one is already due sooner or the ticker is running.
-- Side effects: schedules a timer.
function Companion:WakeIn(seconds)
    if self.ticking then
        return
    end
    local due = Adapter.Now() + seconds
    if self.wakeAt and self.wakeAt <= due then
        return
    end
    self.wakeAt = due
    Adapter.After(seconds, self.wakeFn)
end

function Companion:OnWake()
    self.wakeAt = nil
    self:Evaluate()
end

--- Switches the companion on or off (combat.enabled).
-- @param enabled boolean
-- Side effects: writes combat.enabled; fires WW_COMBAT_ENABLED; may fire WW_ALERTS_UPDATED.
function Companion:SetEnabled(enabled)
    local combat = characterCombat()
    if combat then
        combat.enabled = enabled and true or false
    end
    Events:Fire("WW_COMBAT_ENABLED", self:IsEnabled())
    self:Evaluate()
end

-- Event handlers ----------------------------------------------------------------------------------------------

function Companion:OnStateEvent()
    self:Evaluate()
end

function Companion:OnUnitAura(unit)
    if unit == "player" or unit == "target" then
        self:Evaluate()
    end
end

function Companion:OnSpellcastSucceeded(...)
    local unit, spellID = Adapter.ReadSpellcast(...)
    if unit ~= "player" then
        return
    end
    local name = Adapter.GetSpellName(spellID)
    if name and self.trackedAuras and self.trackedAuras[name] then
        self.tracker:OnCast(name, Adapter.Now())
        self:Evaluate()
    end
end

function Companion:OnContextChanged(newState, oldState)
    local wasRestricted = oldState and oldState.restricted or false
    if newState.restricted ~= wasRestricted then
        Events:Fire("WW_COMBAT_SUSPENDED", newState.restricted)
    end
    self:Evaluate()
end

function Companion:OnSpellMapChanged()
    self:Recompile()
end

local STATE_EVENTS = {
    "PLAYER_TARGET_CHANGED", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "PLAYER_ENTER_COMBAT",
    "PLAYER_LEAVE_COMBAT", "UPDATE_SHAPESHIFT_FORM",
}

--- ADDON_LOADED: registers every ability the rule pack names with the SpellMap (before it first resolves).
-- Side effects: SpellMap registrations.
function Companion:OnInitialize()
    self.pack = ns.RulePacks.WarriorDefault
    self.tracker = AuraTracker.New()
    self.out = {}
    self.tickFn = function()
        self:Tick()
    end
    self.wakeFn = function()
        self:OnWake()
    end
    for _, name in ipairs(Rules.AbilityNames(self.pack)) do
        ns.SpellMap:Register(name)
    end
end

--- PLAYER_LOGIN: compiles the rules against the resolved SpellMap and subscribes to events.
-- Side effects: event subscriptions; may fire WW_ALERTS_UPDATED.
function Companion:OnEnable()
    for _, event in ipairs(STATE_EVENTS) do
        Events:On(event, self, "OnStateEvent")
    end
    Events:On("UNIT_AURA", self, "OnUnitAura")
    Events:On("UNIT_SPELLCAST_SUCCEEDED", self, "OnSpellcastSucceeded")
    Events:On("WW_CONTEXT_CHANGED", self, "OnContextChanged")
    Events:On("WW_SPELLMAP_CHANGED", self, "OnSpellMapChanged")
    self:Recompile()
    if ns.Context:Current().restricted then
        Events:Fire("WW_COMBAT_SUSPENDED", true)
    end
end
