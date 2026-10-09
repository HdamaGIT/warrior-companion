local addonName, ns = ...

-- Ability name -> spellID resolution (SPEC_V2 §5.3). M2 stub: registration, a pure Resolve(), manual overrides
-- from SavedVariables and refresh on login and SPELLS_CHANGED. Rule packs, announce events and macro templates
-- register their ability names from M5 on; until then the map is empty.
--
-- SPELLS_CHANGED alone triggers a refresh. LEARNED_SPELL_IN_TAB (named in SPEC_V2 §5.3) is not subscribed: it
-- may have been renamed in 11.x, and SPELLS_CHANGED also fires when a spell is learned. [VERIFY V-22]
local Adapter = ns.Adapter
local DB = ns.DB
local Events = ns.Events
local Log = ns.Log
local L = ns.L

local REFRESH_DEBOUNCE = 0.5

local SpellMap = ns:NewModule("SpellMap")
ns.SpellMap = SpellMap

SpellMap.names = {}      -- registered ability names, in registration order
SpellMap.registered = {} -- [name] = true
SpellMap.ids = {}        -- [name] = spellID for known abilities
SpellMap.unknown = {}    -- sorted names that did not resolve or are not known by the player

--- Registers an ability name to resolve. Safe to call more than once; a later Refresh picks it up.
-- @param name string ability name in the game's spelling (e.g. "Battle Shout")
function SpellMap:Register(name)
    if type(name) ~= "string" or name == "" or self.registered[name] then
        return
    end
    self.registered[name] = true
    self.names[#self.names + 1] = name
end

--- Resolves names to spellIDs. Pure.
-- @param names array of ability names
-- @param lookup function(name) -> spellID|nil
-- @param isKnown function(spellID) -> boolean|nil (nil = cannot tell, treated as known)
-- @param overrides table|nil { [name] = spellID } manual IDs; a positive number wins over the lookup
-- @return ids { [name] = spellID }, unknown sorted array of names
function SpellMap.Resolve(names, lookup, isKnown, overrides)
    local ids, unknown = {}, {}
    for _, name in ipairs(names) do
        local override = overrides and overrides[name]
        local spellID
        if type(override) == "number" and override > 0 then
            spellID = override
        else
            spellID = lookup(name)
        end
        if type(spellID) == "number" and isKnown(spellID) ~= false then
            ids[name] = spellID
        else
            unknown[#unknown + 1] = name
        end
    end
    table.sort(unknown)
    return ids, unknown
end

local function sameMap(first, second)
    for key, value in pairs(first) do
        if second[key] ~= value then
            return false
        end
    end
    for key in pairs(second) do
        if first[key] == nil then
            return false
        end
    end
    return true
end

--- Re-resolves every registered name and fires WW_SPELLMAP_CHANGED if the result changed.
-- Side effects: updates ids/unknown; may fire WW_SPELLMAP_CHANGED.
function SpellMap:Refresh()
    local character = DB.GetCharacter()
    local overrides = character and character.combat and character.combat.spellOverrides
    local ids, unknown = SpellMap.Resolve(self.names, Adapter.GetSpellIDByName, Adapter.IsPlayerSpell, overrides)
    local changed = not sameMap(ids, self.ids) or #unknown ~= #self.unknown
    self.ids, self.unknown = ids, unknown
    if changed then
        Log.Debug(string.format(L.SPELLMAP_REFRESHED, #self.names - #unknown, #self.names,
            #unknown > 0 and table.concat(unknown, ", ") or L.NONE))
        Events:Fire("WW_SPELLMAP_CHANGED")
    end
end

--- Returns the spellID for a registered, known ability.
-- @param name string
-- @return number|nil
function SpellMap:Get(name)
    return self.ids[name]
end

--- Returns a copy of the names that did not resolve (shown in the config UI from M6; dependants auto-disable).
-- @return array of strings, sorted
function SpellMap:GetUnknown()
    local copy = {}
    for index, name in ipairs(self.unknown) do
        copy[index] = name
    end
    return copy
end

function SpellMap:OnSpellsChanged()
    Events:Debounce("SpellMap:refresh", REFRESH_DEBOUNCE, function()
        self:Refresh()
    end)
end

--- PLAYER_LOGIN: first resolve, then refresh on SPELLS_CHANGED (debounced).
-- Side effects: event subscription; may fire WW_SPELLMAP_CHANGED.
function SpellMap:OnEnable()
    Events:On("SPELLS_CHANGED", self, "OnSpellsChanged")
    self:Refresh()
end
