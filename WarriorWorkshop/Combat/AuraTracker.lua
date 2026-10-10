local addonName, ns = ...

-- Tracks the player's own buffs while auras are unreadable (U-01 Degraded, D-044, D-048). Pure: time is passed in.
--   * A real read (out of combat) is the truth: it sets the expiry and teaches the duration.
--   * When auras turn secret, the last real expiry carries on.
--   * An own cast sets expiry = cast time + learned duration. With no duration learned since login, the aura counts
--     as present with unknown time left (so "expiring" is unknown and "dropped" does not fire).
-- Limits (documented in D-048): dispels and other warriors' shouts are invisible while auras are secret.
-- Durations are kept in memory only; nothing is saved.
local AuraTracker = {}
AuraTracker.__index = AuraTracker
ns.AuraTracker = AuraTracker

--- Creates an empty tracker.
-- @return tracker
function AuraTracker.New()
    return setmetatable({ entries = {} }, AuraTracker)
end

local function entryFor(self, name)
    local entry = self.entries[name]
    if not entry then
        entry = { known = false, expires = nil, duration = nil, openEnded = false, fromPlayer = nil }
        self.entries[name] = entry
    end
    return entry
end

--- Records a real, readable aura read.
-- @param name string aura name
-- @param now number session time
-- @param present boolean
-- @param remaining number|nil seconds left (math.huge if permanent); used when present
-- @param duration number|nil full duration; learned when > 0
-- @param fromPlayer boolean|nil
function AuraTracker:Observe(name, now, present, remaining, duration, fromPlayer)
    local entry = entryFor(self, name)
    entry.known = true
    entry.openEnded = false
    if present then
        entry.expires = remaining and (now + remaining) or nil
        entry.openEnded = remaining == nil
        entry.fromPlayer = fromPlayer
        if type(duration) == "number" and duration > 0 then
            entry.duration = duration
        end
    else
        entry.expires = nil
        entry.fromPlayer = nil
    end
end

--- Records the player's own successful cast of the aura's spell.
-- @param name string aura name (ranks share it)
-- @param now number session time
function AuraTracker:OnCast(name, now)
    local entry = entryFor(self, name)
    entry.known = true
    entry.fromPlayer = true
    if entry.duration then
        entry.expires = now + entry.duration
        entry.openEnded = false
    else
        entry.expires = nil
        entry.openEnded = true
    end
end

--- Current tracked state.
-- @param name string
-- @param now number
-- @return state (true present | false absent | nil unknown), remaining (number|nil), fromPlayer (boolean|nil)
function AuraTracker:Get(name, now)
    local entry = self.entries[name]
    if not entry or not entry.known then
        return nil
    end
    if entry.openEnded then
        return true, nil, entry.fromPlayer
    end
    if entry.expires then
        local remaining = entry.expires - now
        if remaining > 0 then
            return true, remaining, entry.fromPlayer
        end
    end
    return false, nil, nil
end

--- The duration learned for an aura, if any.
-- @return number|nil
function AuraTracker:GetDuration(name)
    local entry = self.entries[name]
    return entry and entry.duration
end
