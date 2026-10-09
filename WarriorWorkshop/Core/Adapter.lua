local addonName, ns = ...

-- The ONLY file that calls Blizzard data APIs (D-002). SPEC 5.3 v1 surface.
--
-- STATUS: UNVERIFIED SKELETON (D-014). M2 was built before the M1 probe was run, so there are NO probe
-- findings yet: every API choice below is the most likely Mainline (Midnight 12.x) call, not a confirmed one.
-- Each function checks that the API exists, returns nil and warns once if not, and is tagged
-- [VERIFY V-0x]. Revise against docs/PROBE_RESULTS.md once it is filled in.
local L = ns.L
local Adapter = {}
ns.Adapter = Adapter

local CHAT_PREFIX = "|cffc79c6eWarrior Workshop|r: " -- warrior class colour

-- Equipment slots 1..19 (head .. tabard; includes ranged/relic slot). [VERIFY V-04]
local FIRST_EQUIPPED_SLOT = 1
local LAST_EQUIPPED_SLOT = 19
-- Backpack, four bags, reagent bag. [VERIFY V-04]
local BAG_IDS = { 0, 1, 2, 3, 4, 5 }
-- Bank container plus bank bag/tab containers. [VERIFY V-04] Midnight may have changed the bank layout.
local BANK_IDS = { -1, 6, 7, 8, 9, 10, 11, 12 }

--- Maps Blizzard ITEM_MOD_* keys to the internal stat keys (SPEC 5.4). [VERIFY V-06]
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

--- Schedules fn to run once after delaySeconds (C_Timer.After). [VERIFY V-04]
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

--- Counts items in the backpack and bags. [VERIFY V-04]
-- @return { [itemID] = count } or nil if the container API is missing
Adapter.GetBagContents = guarded("GetBagContents", function()
    if not hasContainerApi() then
        warnOnce("C_Container.GetContainerItemInfo")
        return nil
    end
    return (scanContainers(BAG_IDS))
end)

--- Counts items in the bank. [VERIFY V-04]
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

--- Returns equipped items. [VERIFY V-05]
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

--- Returns durability for equipped items that have it. [VERIFY V-05]
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

--- Returns the item's stats under internal keys (SPEC 5.4). Unknown raw keys are warned about once. [VERIFY V-06]
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

--- Fetches item basics, asynchronously if the item is not cached. [VERIFY V-06]
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

--- Whether the player can use the item. [VERIFY V-06] C_Item.IsUsableItem may mean "has a use effect",
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

--- Returns saved equipment sets. [VERIFY V-05]
-- @return { [setName] = { [slotID] = itemID } }, or nil if the API is missing
Adapter.GetEquipmentSets = guarded("GetEquipmentSets", function()
    if not (hasFunction(C_EquipmentSet, "GetEquipmentSetIDs") and hasFunction(C_EquipmentSet, "GetEquipmentSetInfo")
        and hasFunction(C_EquipmentSet, "GetItemIDs")) then
        warnOnce("C_EquipmentSet.GetEquipmentSetIDs")
        return nil
    end
    local sets = {}
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        local items = C_EquipmentSet.GetItemIDs(setID)
        if name and type(items) == "table" then
            local slots = {}
            for slot, itemID in pairs(items) do
                if type(itemID) == "number" and itemID > 0 then
                    slots[slot] = itemID
                end
            end
            sets[name] = slots
        end
    end
    return sets
end)
