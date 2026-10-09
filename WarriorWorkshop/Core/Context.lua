local addonName, ns = ...

-- Play context (SPEC_V2 §5.2): zone, restricted, inCombat, dead and group, published as WW_CONTEXT_CHANGED.
-- M2 stub per SPEC_V2 §15: event wiring plus a pure Compute(). M5 adds a direct restriction signal if V-21 finds
-- one. Restricted = encounter, Mythic+ or a direct signal only; a secret value seen by an accessor does NOT
-- suspend everything, it is only counted for diagnostics (D-033).
--
-- Event arguments are never read: state changes come from event names and Adapter queries only.
local Adapter = ns.Adapter
local Events = ns.Events
local Log = ns.Log
local Util = ns.Util

local Context = ns:NewModule("Context")
ns.Context = Context

-- Raw inputs. Compute() turns these into the published state.
Context.flags = {
    zone = "openWorld",   -- "openWorld" | "instance"
    group = "solo",       -- "solo" | "party" | "raid"
    inCombat = false,
    dead = false,
    encounter = false,    -- ENCOUNTER_START seen without ENCOUNTER_END
    challengeMode = false, -- Mythic+ active
    directRestriction = false, -- reserved for a V-21 signal (M5)
}
Context.secretHits = 0

--- Builds the published context from raw flags. Pure.
-- @param flags table see Context.flags
-- @return { zone, restricted, inCombat, dead, group }
function Context.Compute(flags)
    return {
        zone = flags.zone == "instance" and "instance" or "openWorld",
        restricted = (flags.encounter or flags.challengeMode or flags.directRestriction) and true or false,
        inCombat = flags.inCombat and true or false,
        dead = flags.dead and true or false,
        group = (flags.group == "raid" or flags.group == "party") and flags.group or "solo",
    }
end

local function sameState(first, second)
    for key, value in pairs(first) do
        if second[key] ~= value then
            return false
        end
    end
    return true
end

--- Returns a copy of the current context.
-- @return table { zone, restricted, inCombat, dead, group }
function Context:Get()
    return Util.DeepCopy(self.state or Context.Compute(self.flags))
end

--- Whether combat and announce features must suspend (D-021).
-- @return boolean
function Context:IsRestricted()
    return (self.state or Context.Compute(self.flags)).restricted
end

--- Recomputes the state and fires WW_CONTEXT_CHANGED(newState, oldState) if anything changed.
-- Side effects: may fire WW_CONTEXT_CHANGED.
function Context:Publish()
    local newState = Context.Compute(self.flags)
    local oldState = self.state
    if oldState and sameState(newState, oldState) then
        return
    end
    self.state = newState
    Log.Debug(string.format("context: %s, %s, restricted=%s, combat=%s, dead=%s", newState.zone, newState.group,
        tostring(newState.restricted), tostring(newState.inCombat), tostring(newState.dead)))
    Events:Fire("WW_CONTEXT_CHANGED", Util.DeepCopy(newState), oldState and Util.DeepCopy(oldState) or nil)
end

--- Re-reads zone, group and life state from the Adapter; nil answers leave the previous value.
-- Side effects: updates flags, may fire WW_CONTEXT_CHANGED.
function Context:Refresh()
    local flags = self.flags
    flags.zone = Adapter.GetZoneKind() or flags.zone
    flags.group = Adapter.GetGroupKind() or flags.group
    local dead = Adapter.IsPlayerDead()
    if dead ~= nil then
        flags.dead = dead
    end
    self:Publish()
end

--- Counts a secret value returned by a combat accessor (diagnostics only, D-033). Does not change state.
function Context:NoteSecret()
    self.secretHits = self.secretHits + 1
end

-- Event handlers ----------------------------------------------------------------------------------------------

function Context:OnRegenDisabled()
    self.flags.inCombat = true
    self:Publish()
end

function Context:OnRegenEnabled()
    self.flags.inCombat = false
    self:Publish()
end

function Context:OnPlayerDead()
    self.flags.dead = true
    self:Publish()
end

-- PLAYER_ALIVE also fires on release (as a ghost), so ask rather than assume.
function Context:OnPlayerAliveOrUnghost()
    self:Refresh()
end

function Context:OnEncounterStart()
    self.flags.encounter = true
    self:Publish()
end

function Context:OnEncounterEnd()
    self.flags.encounter = false
    self:Publish()
end

function Context:OnChallengeModeStart()
    self.flags.challengeMode = true
    self:Publish()
end

function Context:OnChallengeModeCompleted()
    self.flags.challengeMode = false
    self:Publish()
end

-- After a zone change, re-ask the encounter and Mythic+ state too: an END event may have been missed.
function Context:OnZoneChanged()
    self.flags.encounter = Adapter.IsEncounterInProgress() == true
    self.flags.challengeMode = Adapter.IsChallengeModeActive() == true
    self:Refresh()
end

--- PLAYER_LOGIN: seeds every flag (including an encounter in progress after /reload, D-033), subscribes to
-- events and publishes the first state.
-- Side effects: event subscriptions; fires WW_CONTEXT_CHANGED.
function Context:OnEnable()
    self.flags.inCombat = Adapter.InCombat() == true
    self.flags.encounter = Adapter.IsEncounterInProgress() == true
    self.flags.challengeMode = Adapter.IsChallengeModeActive() == true
    Events:On("PLAYER_REGEN_DISABLED", self, "OnRegenDisabled")
    Events:On("PLAYER_REGEN_ENABLED", self, "OnRegenEnabled")
    Events:On("PLAYER_DEAD", self, "OnPlayerDead")
    Events:On("PLAYER_ALIVE", self, "OnPlayerAliveOrUnghost")
    Events:On("PLAYER_UNGHOST", self, "OnPlayerAliveOrUnghost")
    Events:On("ENCOUNTER_START", self, "OnEncounterStart")
    Events:On("ENCOUNTER_END", self, "OnEncounterEnd")
    Events:On("CHALLENGE_MODE_START", self, "OnChallengeModeStart")
    Events:On("CHALLENGE_MODE_COMPLETED", self, "OnChallengeModeCompleted")
    Events:On("PLAYER_ENTERING_WORLD", self, "OnZoneChanged")
    Events:On("ZONE_CHANGED_NEW_AREA", self, "OnZoneChanged")
    Events:On("GROUP_ROSTER_UPDATE", self, "Refresh")
    self:Refresh()
end
