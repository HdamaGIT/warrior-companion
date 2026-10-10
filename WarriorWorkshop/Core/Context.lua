local addonName, ns = ...

-- Play context (SPEC_V2 §5.2): zone, restricted, inCombat, dead and group, published as WW_CONTEXT_CHANGED.
-- Restricted = encounter, Mythic+ or the direct signal from C_RestrictedActions: restriction types Encounter,
-- ChallengeMode or PvPMatch Active (D-045). Type 0 (Combat) is active in every open-world fight and suspends nothing.
-- A secret value seen by an accessor does NOT suspend anything, it is only counted for diagnostics (D-033, D-049).
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
    directRestriction = false, -- C_RestrictedActions: Encounter, ChallengeMode or PvPMatch Active (D-045)
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

--- Returns the current context table itself, without copying (hot paths: no allocation). Callers must not modify it.
-- @return table { zone, restricted, inCombat, dead, group }
function Context:Current()
    if not self.state then
        self.state = Context.Compute(self.flags)
    end
    return self.state
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
    Adapter.SetSecretFallback(newState.restricted) -- values count as secret while restricted if no checker (D-036)
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

-- Reads the direct restriction signal (D-045). Missing API leaves the flag false.
function Context:ReadRestrictions()
    local encounter, challengeMode, pvpMatch = Adapter.GetRestrictionFlags()
    self.flags.directRestriction = (encounter or challengeMode or pvpMatch) and true or false
end

-- ADDON_RESTRICTION_STATE_CHANGED: its arguments are not read (run 2 saw (0, 1) and (0, 0) for Combat); ask instead.
function Context:OnRestrictionChanged()
    self:ReadRestrictions()
    self:Publish()
end

-- After a zone change, re-ask the encounter and Mythic+ state too: an END event may have been missed.
function Context:OnZoneChanged()
    self.flags.encounter = Adapter.IsEncounterInProgress() == true
    self.flags.challengeMode = Adapter.IsChallengeModeActive() == true
    self:ReadRestrictions()
    self:Refresh()
end

--- PLAYER_LOGIN: seeds every flag (including an encounter in progress after /reload, D-033), subscribes to
-- events and publishes the first state.
-- Side effects: event subscriptions; fires WW_CONTEXT_CHANGED.
function Context:OnEnable()
    self.flags.inCombat = Adapter.InCombat() == true
    self.flags.encounter = Adapter.IsEncounterInProgress() == true
    self.flags.challengeMode = Adapter.IsChallengeModeActive() == true
    self:ReadRestrictions()
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
    Events:On("ADDON_RESTRICTION_STATE_CHANGED", self, "OnRestrictionChanged")
    self:Refresh()
end
