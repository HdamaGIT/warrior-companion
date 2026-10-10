local addonName, ns = ...

-- The ONLY file that calls Blizzard data APIs (D-002). SPEC_V2 §5.4 surface (Workshop functions plus the Context
-- and SpellMap reads; combat accessors arrive in M5).
--
-- STATUS: UNVERIFIED SKELETON (D-015). M2 was built before the M1 probe was run, so there are NO probe
-- findings yet: every API choice below is the most likely Mainline (Midnight 12.x) call, not a confirmed one.
-- Each function checks that the API exists, returns nil and warns once if not, and is tagged
-- [VERIFY V-xx] (or with the probe dump that will show the answer). Revise against docs/PROBE_RESULTS.md once
-- it is filled in.
local L = ns.L
local Adapter = {}
ns.Adapter = Adapter

local CHAT_PREFIX = "|cffc79c6eWarrior Workshop|r: " -- warrior class colour

-- Equipment slots 1..19 (head .. tabard; includes ranged/relic slot). [VERIFY: /wwprobe gear]
local FIRST_EQUIPPED_SLOT = 1
local LAST_EQUIPPED_SLOT = 19
-- Backpack, four bags, reagent bag. [VERIFY: /wwprobe bags]
local BAG_IDS = { 0, 1, 2, 3, 4, 5 }
-- Bank container plus bank bag/tab containers. [VERIFY: /wwprobe bags at the bank] Midnight may have changed the
-- bank layout (PROBE_RESULTS "Extras").
local BANK_IDS = { -1, 6, 7, 8, 9, 10, 11, 12 }

--- Maps Blizzard ITEM_MOD_* keys to the internal stat keys (SPEC_V2 §5.6). [VERIFY V-04]
-- Both the *_SHORT and bare spellings are listed because the exact keys returned are unconfirmed.
Adapter.STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str",
    ITEM_MOD_AGILITY_SHORT = "agi",
    ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int",
    ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_CRIT_RATING_SHORT = "crit",
    ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_HASTE_RATING_SHORT = "haste",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "expertise",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense",
    ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "parry",
    ITEM_MOD_BLOCK_RATING_SHORT = "block",
    ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "weaponDps",
    ITEM_MOD_STRENGTH = "str",
    ITEM_MOD_AGILITY = "agi",
    ITEM_MOD_STAMINA = "sta",
    ITEM_MOD_INTELLECT = "int",
    ITEM_MOD_SPIRIT = "spi",
    ITEM_MOD_ATTACK_POWER = "ap",
    ITEM_MOD_CRIT_RATING = "crit",
    ITEM_MOD_HIT_RATING = "hit",
    ITEM_MOD_HASTE_RATING = "haste",
    ITEM_MOD_EXPERTISE_RATING = "expertise",
    ITEM_MOD_DEFENSE_SKILL_RATING = "defense",
    ITEM_MOD_DODGE_RATING = "dodge",
    ITEM_MOD_PARRY_RATING = "parry",
    ITEM_MOD_BLOCK_RATING = "block",
    ITEM_MOD_BLOCK_VALUE = "blockValue",
    ITEM_MOD_DAMAGE_PER_SECOND = "weaponDps",
    RESISTANCE0_NAME = "armor", -- armour is reported under this key by GetItemStats
}

local function warnOnce(key, msg)
    ns.Log.WarnOnce(key, msg or string.format(L.API_UNAVAILABLE, key))
end

local function hasFunction(tbl, name)
    return type(tbl) == "table" and type(tbl[name]) == "function"
end

-- Wraps fn so that a Lua error inside an unverified API call returns nil and warns once instead of throwing.
local function guarded(name, fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if not ok then
            warnOnce(name .. ":error", name .. ": " .. tostring(result))
            return nil
        end
        return result
    end
end

--- Prints a line to the default chat frame with the add-on prefix.
-- @param msg any value; converted with tostring
-- Side effects: chat output only.
function Adapter.Print(msg)
    local line = CHAT_PREFIX .. tostring(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(line)
    else
        print(line)
    end
end

--- Returns client build information.
-- @return { version = string, build = string, interface = number } or nil if unavailable
function Adapter.GetBuildInfo()
    if type(GetBuildInfo) ~= "function" then
        warnOnce("GetBuildInfo")
        return nil
    end
    local version, build, _, interface = GetBuildInfo()
    return { version = version, build = build, interface = interface }
end

--- Returns this add-on's version from the .toc `## Version:` field.
-- @return string or nil if unavailable
function Adapter.GetAddOnVersion()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata
    if type(getMetadata) ~= "function" then
        warnOnce("C_AddOns.GetAddOnMetadata")
        return nil
    end
    return getMetadata(addonName, "Version")
end

--- Returns wall-clock time (seconds since the epoch).
-- @return number, or 0 if the clock is unavailable
function Adapter.Time()
    if type(time) ~= "function" then
        warnOnce("time")
        return 0
    end
    return time()
end

--- Returns the high-resolution session clock (GetTime), in seconds.
-- @return number, or 0 if unavailable
function Adapter.Now()
    if type(GetTime) ~= "function" then
        warnOnce("GetTime")
        return 0
    end
    return GetTime()
end

--- Schedules fn to run once after delaySeconds (C_Timer.After).
-- @param delaySeconds number
-- @param fn function
-- @return true if scheduled, nil if the timer API is missing
function Adapter.After(delaySeconds, fn)
    if not hasFunction(C_Timer, "After") then
        warnOnce("C_Timer.After")
        return nil
    end
    C_Timer.After(delaySeconds, fn)
    return true
end

--- Creates a frame used purely as a game-event receiver.
-- @return frame (supports RegisterEvent, UnregisterEvent, SetScript) or nil if CreateFrame is missing
function Adapter.CreateEventFrame()
    if type(CreateFrame) ~= "function" then
        warnOnce("CreateFrame")
        return nil
    end
    return CreateFrame("Frame")
end

--- Whether the player is in combat lockdown. Uses InCombatLockdown() only; no combat values are read.
-- @return boolean, or nil if the API is missing
function Adapter.InCombat()
    if type(InCombatLockdown) ~= "function" then
        warnOnce("InCombatLockdown")
        return nil
    end
    return InCombatLockdown() and true or false
end

--- Returns identity data for the logged-in character.
-- @return { name, realm, classFile, level } or nil if the unit APIs are missing
Adapter.GetPlayerMeta = guarded("GetPlayerMeta", function()
    if type(UnitName) ~= "function" or type(UnitClass) ~= "function" or type(UnitLevel) ~= "function" then
        warnOnce("UnitName/UnitClass/UnitLevel")
        return nil
    end
    local _, classFile = UnitClass("player")
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    return { name = UnitName("player"), realm = realm, classFile = classFile, level = UnitLevel("player") }
end)

-- Context reads (Core/Context.lua, SPEC_V2 §5.2) ----------------------------------------------------------
-- These read zone, group and life state, not combat values, but each runs inside pcall (guarded) so an
-- unexpected secret return becomes nil plus one warning instead of an error.

--- Returns the player's zone kind.
-- @return "instance" (party or raid instance) | "openWorld", or nil if IsInInstance is missing
Adapter.GetZoneKind = guarded("GetZoneKind", function()
    if type(IsInInstance) ~= "function" then
        warnOnce("IsInInstance")
        return nil
    end
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        return "instance"
    end
    return "openWorld"
end)

--- Returns the player's group kind.
-- @return "raid" | "party" | "solo", or nil if the group APIs are missing
Adapter.GetGroupKind = guarded("GetGroupKind", function()
    if type(IsInGroup) ~= "function" or type(IsInRaid) ~= "function" then
        warnOnce("IsInGroup/IsInRaid")
        return nil
    end
    if IsInRaid() then
        return "raid"
    elseif IsInGroup() then
        return "party"
    end
    return "solo"
end)

--- Whether the player is dead or a ghost.
-- @return boolean, or nil if UnitIsDeadOrGhost is missing
Adapter.IsPlayerDead = guarded("IsPlayerDead", function()
    if type(UnitIsDeadOrGhost) ~= "function" then
        warnOnce("UnitIsDeadOrGhost")
        return nil
    end
    return UnitIsDeadOrGhost("player") and true or false
end)

--- Whether a boss encounter is in progress, used to seed Context after a /reload (D-033). [VERIFY V-06, V-21]
-- @return boolean, or nil if IsEncounterInProgress is missing
Adapter.IsEncounterInProgress = guarded("IsEncounterInProgress", function()
    if type(IsEncounterInProgress) ~= "function" then
        warnOnce("IsEncounterInProgress")
        return nil
    end
    return IsEncounterInProgress() and true or false
end)

--- Whether a Mythic+ (challenge mode) run is active. Forever may not have Mythic+ at all. [VERIFY V-21]
-- @return boolean, or nil if the API is missing (absence is expected; no warning)
Adapter.IsChallengeModeActive = guarded("IsChallengeModeActive", function()
    if not hasFunction(C_ChallengeMode, "IsChallengeModeActive") then
        return nil
    end
    return C_ChallengeMode.IsChallengeModeActive() and true or false
end)

-- Spell map reads (Core/SpellMap.lua, SPEC_V2 §5.3) -------------------------------------------------------

--- Resolves an ability name to a spellID. [VERIFY V-22] Name lookups may only work for spellbook spells.
-- @param name string ability name in the game's spelling
-- @return number spellID, or nil if unknown or the API is missing
Adapter.GetSpellIDByName = guarded("GetSpellIDByName", function(name)
    if not hasFunction(C_Spell, "GetSpellInfo") then
        warnOnce("C_Spell.GetSpellInfo")
        return nil
    end
    local info = C_Spell.GetSpellInfo(name)
    if type(info) == "table" and type(info.spellID) == "number" then
        return info.spellID
    end
    return nil
end)

--- Whether the player knows a spell. [VERIFY V-22]
-- @param spellID number
-- @return boolean, or nil if IsPlayerSpell is missing
Adapter.IsPlayerSpell = guarded("IsPlayerSpell", function(spellID)
    if type(IsPlayerSpell) ~= "function" then
        warnOnce("IsPlayerSpell")
        return nil
    end
    return IsPlayerSpell(spellID) and true or false
end)

-- Bags, bank, equipment -------------------------------------------------------------------------------------

local function scanContainers(bagIDs)
    local counts, totalSlots = {}, 0
    for _, bag in ipairs(bagIDs) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        totalSlots = totalSlots + slots
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts, totalSlots
end

local function hasContainerApi()
    return hasFunction(C_Container, "GetContainerNumSlots") and hasFunction(C_Container, "GetContainerItemInfo")
end

--- Counts items in the backpack and bags. [VERIFY: /wwprobe bags]
-- @return { [itemID] = count } or nil if the container API is missing
Adapter.GetBagContents = guarded("GetBagContents", function()
    if not hasContainerApi() then
        warnOnce("C_Container.GetContainerItemInfo")
        return nil
    end
    return (scanContainers(BAG_IDS))
end)

--- Counts items in the bank. [VERIFY: /wwprobe bags at the bank]
-- @return { [itemID] = count }, or nil if the bank reports no slots (assumed closed) or the API is missing
Adapter.GetBankContents = guarded("GetBankContents", function()
    if not hasContainerApi() then
        warnOnce("C_Container.GetContainerItemInfo")
        return nil
    end
    local counts, totalSlots = scanContainers(BANK_IDS)
    if totalSlots == 0 then
        return nil
    end
    return counts
end)

--- Returns equipped items. [VERIFY: /wwprobe gear]
-- @return { [slotID] = { itemID, link } } for filled slots, or nil if the API is missing
Adapter.GetEquipped = guarded("GetEquipped", function()
    if type(GetInventoryItemID) ~= "function" or type(GetInventoryItemLink) ~= "function" then
        warnOnce("GetInventoryItemID")
        return nil
    end
    local equipped = {}
    for slot = FIRST_EQUIPPED_SLOT, LAST_EQUIPPED_SLOT do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            equipped[slot] = { itemID = itemID, link = GetInventoryItemLink("player", slot) }
        end
    end
    return equipped
end)

--- Returns durability for equipped items that have it. [VERIFY: /wwprobe gear]
-- @return { [slotID] = { cur, max } } or nil if the API is missing
Adapter.GetDurability = guarded("GetDurability", function()
    if type(GetInventoryItemDurability) ~= "function" then
        warnOnce("GetInventoryItemDurability")
        return nil
    end
    local result = {}
    for slot = FIRST_EQUIPPED_SLOT, LAST_EQUIPPED_SLOT do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max then
            result[slot] = { cur = cur, max = max }
        end
    end
    return result
end)

--- Converts a raw Blizzard stat table to internal stat keys. Pure; no WoW calls.
-- Unknown keys are kept under result.other[rawKey]. Values that map to the same key are summed.
-- @param raw table { [ITEM_MOD_* key] = number }
-- @return stats table { [statKey] = number, other = { [rawKey] = value } | nil }
-- @return unknown array of unmapped raw keys, sorted
function Adapter.NormaliseStats(raw)
    local stats, other, unknown = {}, nil, {}
    for rawKey, value in pairs(raw) do
        local key = Adapter.STAT_KEYS[rawKey]
        if key and type(value) == "number" then
            stats[key] = (stats[key] or 0) + value
        else
            other = other or {}
            other[rawKey] = value
            unknown[#unknown + 1] = tostring(rawKey)
        end
    end
    table.sort(unknown)
    stats.other = other
    return stats, unknown
end

--- Returns the item's stats under internal keys (SPEC_V2 §5.6). Unknown raw keys are warned about once. [VERIFY V-04]
-- @param link string item link
-- @return { [statKey] = number, other = table|nil }, or nil if no stats API exists or the item has no data
Adapter.GetItemStats = guarded("GetItemStats", function(link)
    local raw
    if hasFunction(C_Item, "GetItemStats") then
        raw = C_Item.GetItemStats(link)
    elseif type(GetItemStats) == "function" then
        raw = GetItemStats(link)
    else
        warnOnce("GetItemStats")
        return nil
    end
    if type(raw) ~= "table" then
        return nil
    end
    local stats, unknown = Adapter.NormaliseStats(raw)
    for _, rawKey in ipairs(unknown) do
        warnOnce("stat:" .. rawKey, string.format(L.UNKNOWN_STAT, rawKey))
    end
    return stats
end)

local function readItemBasics(itemID)
    local getInfo
    if hasFunction(C_Item, "GetItemInfo") then
        getInfo = C_Item.GetItemInfo
    elseif type(GetItemInfo) == "function" then
        getInfo = GetItemInfo
    else
        return nil, false
    end
    local name, link, quality, ilvl, reqLevel, _, _, _, equipLoc, icon, sellPrice, classID, subClassID =
        getInfo(itemID)
    if not name then
        return nil, true
    end
    return {
        name = name, link = link, quality = quality, ilvl = ilvl, reqLevel = reqLevel, equipLoc = equipLoc,
        classID = classID, subClassID = subClassID, sellPrice = sellPrice, icon = icon,
    }, true
end

--- Fetches item basics, asynchronously if the item is not cached. [VERIFY V-04]
-- @param itemID number
-- @param cb function called exactly once with { name, link, quality, ilvl, reqLevel, equipLoc, classID,
--   subClassID, sellPrice, icon } or nil if the data cannot be obtained
function Adapter.GetItemBasics(itemID, cb)
    local ok, basics, apiExists = pcall(readItemBasics, itemID)
    if not ok then
        warnOnce("GetItemBasics:error", "GetItemBasics: " .. tostring(basics))
        cb(nil)
        return
    end
    if basics then
        cb(basics)
        return
    end
    if not apiExists then
        warnOnce("GetItemInfo")
        cb(nil)
        return
    end
    if type(Item) == "table" and hasFunction(Item, "CreateFromItemID") then
        local item = Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function()
            cb((readItemBasics(itemID)))
        end)
        return
    end
    warnOnce("Item.CreateFromItemID")
    cb(nil)
end

--- Whether the player can use the item. [VERIFY V-04] C_Item.IsUsableItem may mean "has a use effect",
-- not "equippable by class/level"; confirm and replace if needed.
-- @param itemID number
-- @return boolean, or nil if the API is missing
Adapter.IsUsableByPlayer = guarded("IsUsableByPlayer", function(itemID)
    local usable
    if hasFunction(C_Item, "IsUsableItem") then
        usable = C_Item.IsUsableItem(itemID)
    elseif type(IsUsableItem) == "function" then
        usable = IsUsableItem(itemID)
    else
        warnOnce("IsUsableItem")
        return nil
    end
    return usable and true or false
end)

--- Returns the profession window's current profession. [VERIFY V-02]
-- @return { skillLineID, name, rank, maxRank } or nil if none is open or the API is missing
Adapter.GetOpenProfession = guarded("GetOpenProfession", function()
    if not hasFunction(C_TradeSkillUI, "GetBaseProfessionInfo") then
        warnOnce("C_TradeSkillUI.GetBaseProfessionInfo")
        return nil
    end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if type(info) ~= "table" or not info.professionID then
        return nil
    end
    return {
        skillLineID = info.professionID,
        name = info.professionName,
        rank = info.skillLevel,
        maxRank = info.maxSkillLevel,
    }
end)

local function difficultyName(value)
    local enum = Enum and Enum.TradeskillRelativeDifficulty
    if type(enum) == "table" then
        for name, enumValue in pairs(enum) do
            if enumValue == value then
                return string.lower(name)
            end
        end
    end
    return nil
end

local function readReagents(schematic)
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID then
            reagents[#reagents + 1] = { itemID = reagent.itemID, qty = slot.quantityRequired or 0 }
        end
    end
    return reagents
end

--- Returns the recipes of the open profession that the character has learned. [VERIFY V-02]
-- difficulty is "optimal"|"medium"|"easy"|"trivial" or nil when the enum cannot be resolved.
-- @return array of { recipeID, name, difficulty, outputItemID, outputMin, outputMax, reagents = { {itemID, qty} } },
--   or nil if the API is missing
Adapter.GetKnownRecipes = guarded("GetKnownRecipes", function()
    if not (hasFunction(C_TradeSkillUI, "GetAllRecipeIDs") and hasFunction(C_TradeSkillUI, "GetRecipeInfo")
        and hasFunction(C_TradeSkillUI, "GetRecipeSchematic")) then
        warnOnce("C_TradeSkillUI.GetAllRecipeIDs")
        return nil
    end
    local recipes = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if type(info) == "table" and info.learned then
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false) or {}
            recipes[#recipes + 1] = {
                recipeID = recipeID,
                name = info.name,
                difficulty = difficultyName(info.relativeDifficulty),
                outputItemID = schematic.outputItemID,
                outputMin = schematic.quantityMin,
                outputMax = schematic.quantityMax,
                reagents = readReagents(schematic),
            }
        end
    end
    return recipes
end)

--- Returns saved equipment sets (Blizzard's Equipment Manager is the source of truth, D-025). [VERIFY V-05]
-- @return { [setName] = { id = setID, icon = iconFileID|nil, [slotID] = itemID } }, or nil if the API is missing
Adapter.GetEquipmentSets = guarded("GetEquipmentSets", function()
    if not (hasFunction(C_EquipmentSet, "GetEquipmentSetIDs") and hasFunction(C_EquipmentSet, "GetEquipmentSetInfo")
        and hasFunction(C_EquipmentSet, "GetItemIDs")) then
        warnOnce("C_EquipmentSet.GetEquipmentSetIDs")
        return nil
    end
    local sets = {}
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        local items = C_EquipmentSet.GetItemIDs(setID)
        if name and type(items) == "table" then
            local set = { id = setID, icon = icon }
            for slot, itemID in pairs(items) do
                if type(slot) == "number" and type(itemID) == "number" and itemID > 0 then
                    set[slot] = itemID
                end
            end
            sets[name] = set
        end
    end
    return sets
end)

-- Combat accessors (SPEC_V2 §5.4, D-036, D-044, D-045, D-048) ----------------------------------------------------
-- Every combat value may be secret. Rules, in order:
--   1. Before a call whose family Forever marks secret, ask C_Secrets.Should*BeSecret and return nil without calling
--      (aura calls raise an error when secret, D-045).
--   2. Every call runs in pcall; an error returns nil.
--   3. Every returned value (and each table field read) is checked with issecretvalue before it is compared, used in
--      arithmetic or returned. If issecretvalue is missing, values count as readable only outside restricted contexts
--      (D-036): Context sets that fallback through Adapter.SetSecretFallback.
-- A secret or unavailable value returns nil; nil means unknown; unknown is hidden (D-020).
-- Hot-path accessors return multiple values, never new tables (D-036).

-- The one documented hardcoded spell ID (D-048): Auto Attack. Its name does not resolve; beta run 2 confirmed the ID
-- (V-23).
local AUTO_ATTACK_SPELL_ID = 6603
Adapter.AUTO_ATTACK_SPELL_ID = AUTO_ATTACK_SPELL_ID

local assumeSecret = false

--- Sets how values are treated when issecretvalue does not exist (D-036). Called by Context.
-- @param secret boolean true while a restricted context is active
function Adapter.SetSecretFallback(secret)
    assumeSecret = secret and true or false
end

-- True if value is secret (or must be assumed secret). Never errors.
local function isSecret(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok then
            return true
        end
        return secret == true
    end
    return assumeSecret
end

--- Whether a value is secret (or must be assumed secret, D-036). Never errors.
-- @param value any
-- @return boolean
Adapter.IsSecret = isSecret

-- Asks C_Secrets.<name>(arg) whether a family is secret right now. If the function is missing or errors, the answer
-- is `fallback`; the per-value checks still apply either way.
local function familySecret(name, arg, fallback)
    local fn = type(C_Secrets) == "table" and C_Secrets[name]
    if type(fn) ~= "function" then
        return fallback == true
    end
    local ok, result = pcall(fn, arg)
    if not ok then
        return fallback == true
    end
    return result == true
end

-- Fallback for the aura and cooldown families when C_Secrets cannot answer (D-036): run 2 found both secret in
-- combat, and an aura read by name then returns nil, which would look like "absent". So assume secret in combat.
local function secretInCombat()
    return Adapter.InCombat() == true
end

-- Reads tbl[key] and returns it only if readable.
local function field(tbl, key)
    local value = tbl[key]
    if isSecret(value) or value == nil then
        return nil
    end
    return value
end

--- Restriction types that suspend the HUD and announcer (D-045): Encounter, ChallengeMode and PvPMatch Active.
-- Combat (type 0) is the normal state of every fight and is not reported.
-- @return encounter, challengeMode, pvpMatch (booleans), or nil if C_RestrictedActions is missing
function Adapter.GetRestrictionFlags()
    if not hasFunction(C_RestrictedActions, "GetAddOnRestrictionState") then
        return nil
    end
    local types = Enum and Enum.AddOnRestrictionType or {}
    local states = Enum and Enum.AddOnRestrictionState or {}
    local active = states.Active or 2
    local function isActive(restrictionType)
        local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, restrictionType)
        if not ok or isSecret(state) or state == nil then
            return false
        end
        return state == active
    end
    return isActive(types.Encounter or 1), isActive(types.ChallengeMode or 2), isActive(types.PvPMatch or 3)
end

local function readPower()
    return UnitPower("player"), UnitPowerMax("player")
end

--- Player rage. Secret in Forever in and out of combat (V-12), so this normally returns nil (D-044).
-- @return cur, max or nil
function Adapter.GetRage()
    if familySecret("ShouldUnitPowerBeSecret", "player") or type(UnitPower) ~= "function"
        or type(UnitPowerMax) ~= "function" then
        return nil
    end
    local ok, cur, max = pcall(readPower)
    if not ok or isSecret(cur) or isSecret(max) or cur == nil or max == nil then
        return nil
    end
    return cur, max
end

local function readHealth(unit)
    return UnitHealth(unit), UnitHealthMax(unit)
end

--- Unit health as a fraction. Secret in Forever for the target (V-11), so this normally returns nil (D-044).
-- @param unit string
-- @return number 0..1 or nil
function Adapter.GetHealthPct(unit)
    if familySecret("ShouldUnitHealthMaxBeSecret", unit) or type(UnitHealth) ~= "function"
        or type(UnitHealthMax) ~= "function" then
        return nil
    end
    local ok, cur, max = pcall(readHealth, unit)
    if not ok or isSecret(cur) or isSecret(max) or cur == nil or max == nil or max <= 0 then
        return nil
    end
    return cur / max
end

--- Whether a spell is usable now (V-14: readable in combat). Usability includes stance and rage.
-- @param spellID number
-- @return usable, noPower (booleans) or nil
function Adapter.IsSpellUsable(spellID)
    if not hasFunction(C_Spell, "IsSpellUsable") then
        return nil
    end
    local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok or isSecret(usable) or isSecret(noPower) or usable == nil then
        return nil
    end
    return usable and true or false, noPower and true or false
end

--- Seconds until a spell's cooldown ends (0 = ready). In combat the times are secret (V-13); the readable isActive
-- flag then still says "ready" (0) when false, and the remaining time is unknown (nil) when true.
-- @param spellID number
-- @return number or nil
function Adapter.GetSpellCooldownRemaining(spellID)
    if not hasFunction(C_Spell, "GetSpellCooldown") then
        return nil
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" or isSecret(info) then
        return nil
    end
    if not familySecret("ShouldCooldownsBeSecret", nil, secretInCombat()) then
        local start, duration, modRate = field(info, "startTime"), field(info, "duration"), field(info, "modRate")
        if start ~= nil and duration ~= nil then
            if start == 0 or duration == 0 then
                return 0
            end
            local rate = (modRate ~= nil and modRate > 0) and modRate or 1
            local remaining = (start + duration - Adapter.Now()) / rate
            return remaining > 0 and remaining or 0
        end
    end
    if field(info, "isActive") == false then
        return 0
    end
    return nil
end

--- Whether a spell is in range of a unit (V-18: readable in combat).
-- @param spellID number
-- @param unit string
-- @return boolean, or nil when unknown (no target, no range, secret)
function Adapter.IsSpellInRange(spellID, unit)
    if not hasFunction(C_Spell, "IsSpellInRange") then
        return nil
    end
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
    if not ok or isSecret(inRange) or inRange == nil then
        return nil
    end
    return inRange and true or false
end

--- Whether auto-attack is on, via IsCurrentSpell(6603) (V-23, D-048).
-- @return boolean or nil
function Adapter.IsAutoAttacking()
    if not hasFunction(C_Spell, "IsCurrentSpell") then
        return nil
    end
    local ok, current = pcall(C_Spell.IsCurrentSpell, AUTO_ATTACK_SPELL_ID)
    if not ok or isSecret(current) or current == nil then
        return nil
    end
    return current and true or false
end

--- Reads an aura by name (all ranks, D-048). Never scans by index: that raises an error when secret (V-15).
-- In combat the by-name call returns nil, which looks like "absent"; the ShouldAurasBeSecret pre-check is what keeps
-- that from reading as false (D-045).
-- @param unit string
-- @param auraName string
-- @param filter string|nil e.g. "HELPFUL"
-- @return stacks, remaining (seconds; math.huge if permanent), fromPlayer (boolean|nil), duration (number|nil);
--   or false if known absent; or nil if unknown
function Adapter.GetAura(unit, auraName, filter)
    if familySecret("ShouldAurasBeSecret", nil, secretInCombat())
        or not hasFunction(C_UnitAuras, "GetAuraDataBySpellName") then
        return nil
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, auraName, filter)
    if not ok or isSecret(aura) then
        return nil
    end
    if aura == nil then
        return false
    end
    if type(aura) ~= "table" then
        return nil
    end
    local expires = field(aura, "expirationTime")
    if expires == nil then
        return nil
    end
    local remaining = math.huge
    if expires > 0 then
        remaining = expires - Adapter.Now()
        if remaining <= 0 then
            return false
        end
    end
    local fromPlayer = field(aura, "isFromPlayerOrPlayerPet")
    if fromPlayer == nil then
        local source = field(aura, "sourceUnit")
        if source ~= nil then
            fromPlayer = source == "player"
        end
    end
    return field(aura, "applications") or 0, remaining, fromPlayer, field(aura, "duration")
end

--- Target existence and hostility (V-19: readable in combat). Hostile = attackable and not dead.
-- @return exists, hostile (booleans), or nil if unknown
function Adapter.GetTargetState()
    if type(UnitExists) ~= "function" or type(UnitCanAttack) ~= "function" then
        return nil
    end
    local ok, exists = pcall(UnitExists, "target")
    if not ok or isSecret(exists) then
        return nil
    end
    if not exists then
        return false, false
    end
    local okAttack, canAttack = pcall(UnitCanAttack, "player", "target")
    if not okAttack or isSecret(canAttack) or canAttack == nil then
        return nil
    end
    local dead = false
    if type(UnitIsDeadOrGhost) == "function" then
        local okDead, value = pcall(UnitIsDeadOrGhost, "target")
        if not okDead or isSecret(value) then
            return nil
        end
        dead = value and true or false
    end
    return true, (canAttack and not dead) and true or false
end

--- Spell name for an ID (maps own casts to ability names; ranks share a name). [VERIFY: C_Spell.GetSpellName]
-- @param spellID number
-- @return string or nil
function Adapter.GetSpellName(spellID)
    if type(spellID) ~= "number" then
        return nil
    end
    local ok, name
    if hasFunction(C_Spell, "GetSpellName") then
        ok, name = pcall(C_Spell.GetSpellName, spellID)
    elseif hasFunction(C_Spell, "GetSpellInfo") then
        local info
        ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        name = ok and type(info) == "table" and info.name or nil
    end
    if not ok or isSecret(name) or name == nil then
        return nil
    end
    return name
end

--- Current stance (V-22: GetShapeshiftFormInfo returns icon, active, castable, spellID).
-- @return index (0 = none), name (string|nil); or nil if unknown
function Adapter.GetStance()
    if type(GetShapeshiftForm) ~= "function" then
        return nil
    end
    local ok, index = pcall(GetShapeshiftForm)
    if not ok or isSecret(index) or index == nil then
        return nil
    end
    if index == 0 or type(GetShapeshiftFormInfo) ~= "function" then
        return index, nil
    end
    local okInfo, _, _, _, spellID = pcall(GetShapeshiftFormInfo, index)
    if not okInfo or isSecret(spellID) or spellID == nil then
        return index, nil
    end
    return index, Adapter.GetSpellName(spellID)
end

--- Spell icon for display. [VERIFY: C_Spell.GetSpellTexture]
-- @param spellID number
-- @return fileID or nil
function Adapter.GetSpellIcon(spellID)
    if type(spellID) ~= "number" or not hasFunction(C_Spell, "GetSpellTexture") then
        return nil
    end
    local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
    if not ok or isSecret(icon) or icon == nil then
        return nil
    end
    return icon
end

--- Plays a sound kit by SOUNDKIT name (alert style sounds). [VERIFY: PlaySound, SOUNDKIT]
-- @param kitName string e.g. "RAID_WARNING"
-- @return true if played
function Adapter.PlaySound(kitName)
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" or SOUNDKIT[kitName] == nil then
        return false
    end
    return (pcall(PlaySound, SOUNDKIT[kitName], "Master"))
end

-- Normalised combat events (SPEC_V2 §5.5) -------------------------------------------------------------------

--- Normalises UNIT_COMBAT arguments (V-16: unit, action, descriptor, amount, school; readable in combat).
-- @return unit, action, descriptor, amount; descriptor and amount are nil if secret or the wrong type; returns
--   nothing if unit or action is unreadable (ignore the event)
function Adapter.ReadUnitCombat(unit, action, descriptor, amount)
    if type(unit) ~= "string" or isSecret(unit) or type(action) ~= "string" or isSecret(action) then
        return nil
    end
    if type(descriptor) ~= "string" or isSecret(descriptor) then
        descriptor = nil
    end
    if type(amount) ~= "number" or isSecret(amount) then
        amount = nil
    end
    return unit, action, descriptor, amount
end

--- Normalises UNIT_SPELLCAST_* arguments (unit, castGUID, spellID; own casts readable in combat, V-07).
-- @return unit, spellID; nil if either is secret or missing
function Adapter.ReadSpellcast(unit, _, spellID)
    if type(unit) ~= "string" or isSecret(unit) or type(spellID) ~= "number" or isSecret(spellID) then
        return nil
    end
    return unit, spellID
end
