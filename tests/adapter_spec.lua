-- Adapter-level tests. The real Core/Adapter.lua is loaded; where an API has to exist, a stub is placed in a
-- sandbox environment (never in _G) for the Adapter chunk only. Module tests use the mock adapter instead.
local H = dofile("tests/helpers/load_addon.lua")

local INTERNAL_KEYS = {
    str = true, agi = true, sta = true, int = true, spi = true, armor = true, ap = true, crit = true,
    hit = true, haste = true, expertise = true, defense = true, dodge = true, parry = true, block = true,
    blockValue = true, weaponDps = true, weaponSpeed = true,
}

--- Loads the real Adapter in a sandbox with the given WoW stubs. Returns the adapter and the lines it printed.
local function loadAdapter(stubs)
    local env = setmetatable({}, { __index = _G })
    for key, value in pairs(stubs or {}) do
        env[key] = value
    end
    local ns = H.newNs({ "Locale/enUS.lua", "Core/Util.lua", "Core/Log.lua", "Core/Adapter.lua" }, { env = env })
    local printed = {}
    ns.Adapter.Print = function(msg)
        printed[#printed + 1] = msg
    end
    return ns.Adapter, printed
end

describe("adapter", function()
    describe("NormaliseStats", function()
        local Adapter

        before_each(function()
            Adapter = loadAdapter()
        end)

        it("maps ITEM_MOD_* keys to the SPEC 5.4 internal keys", function()
            local stats, unknown = Adapter.NormaliseStats(dofile("tests/fixtures/item_stats.lua"))
            assert.are.equal(25, stats.str)
            assert.are.equal(40, stats.sta)
            assert.are.equal(18, stats.crit)
            assert.are.equal(310, stats.armor)
            assert.are.equal(61.5, stats.weaponDps)
            assert.are.same({ "ITEM_MOD_MASTERY_RATING_SHORT" }, unknown)
        end)

        it("keeps unknown keys under other[rawKey] instead of dropping them", function()
            local stats = Adapter.NormaliseStats(dofile("tests/fixtures/item_stats.lua"))
            assert.are.same({ ITEM_MOD_MASTERY_RATING_SHORT = 12 }, stats.other)
        end)

        it("leaves other nil when every key is known", function()
            local stats, unknown = Adapter.NormaliseStats({ ITEM_MOD_AGILITY_SHORT = 7 })
            assert.are.equal(7, stats.agi)
            assert.is_nil(stats.other)
            assert.are.same({}, unknown)
        end)

        it("sums keys that map to the same internal key", function()
            local stats = Adapter.NormaliseStats({ ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STRENGTH = 3 })
            assert.are.equal(8, stats.str)
        end)

        it("treats a non-numeric value as unknown", function()
            local stats, unknown = Adapter.NormaliseStats({ ITEM_MOD_STRENGTH_SHORT = "lots" })
            assert.is_nil(stats.str)
            assert.are.equal("lots", stats.other.ITEM_MOD_STRENGTH_SHORT)
            assert.are.same({ "ITEM_MOD_STRENGTH_SHORT" }, unknown)
        end)

        it("returns an empty table for empty input", function()
            local stats, unknown = Adapter.NormaliseStats({})
            assert.are.same({}, stats)
            assert.are.same({}, unknown)
        end)

        it("only ever maps to keys in the SPEC 5.4 list", function()
            for rawKey, internalKey in pairs(Adapter.STAT_KEYS) do
                assert.is_true(INTERNAL_KEYS[internalKey], rawKey .. " maps to unlisted key " .. internalKey)
            end
        end)
    end)

    describe("when the underlying API is missing", function()
        local Adapter, printed

        before_each(function()
            Adapter, printed = loadAdapter()
        end)

        it("returns nil from every data function", function()
            assert.is_nil(Adapter.GetBagContents())
            assert.is_nil(Adapter.GetBankContents())
            assert.is_nil(Adapter.GetEquipped())
            assert.is_nil(Adapter.GetDurability())
            assert.is_nil(Adapter.GetItemStats("|cff|Hitem:1|h[x]|h|r"))
            assert.is_nil(Adapter.IsUsableByPlayer(1))
            assert.is_nil(Adapter.GetOpenProfession())
            assert.is_nil(Adapter.GetKnownRecipes())
            assert.is_nil(Adapter.GetEquipmentSets())
            assert.is_nil(Adapter.GetPlayerMeta())
            assert.is_nil(Adapter.InCombat())
            assert.is_nil(Adapter.After(1, function() end))
            assert.is_nil(Adapter.CreateEventFrame())
            assert.is_nil(Adapter.GetBuildInfo())
            assert.is_nil(Adapter.GetAddOnVersion())
            assert.is_nil(Adapter.GetZoneKind())
            assert.is_nil(Adapter.GetGroupKind())
            assert.is_nil(Adapter.IsPlayerDead())
            assert.is_nil(Adapter.IsEncounterInProgress())
            assert.is_nil(Adapter.IsChallengeModeActive())
            assert.is_nil(Adapter.GetSpellIDByName("Charge"))
            assert.is_nil(Adapter.IsPlayerSpell(1))
        end)

        it("calls back with nil from GetItemBasics, exactly once", function()
            local calls, last = 0, "unset"
            Adapter.GetItemBasics(1, function(basics)
                calls = calls + 1
                last = basics
            end)
            assert.are.equal(1, calls)
            assert.is_nil(last)
        end)

        it("warns only once per missing API", function()
            Adapter.GetBagContents()
            local afterFirst = #printed
            assert.is_true(afterFirst > 0)
            Adapter.GetBagContents()
            Adapter.GetBagContents()
            assert.are.equal(afterFirst, #printed)
        end)

        it("still provides a clock", function()
            assert.is_number(Adapter.Time())
            assert.are.equal(0, Adapter.Now())
        end)
    end)

    describe("with stubbed APIs", function()
        it("sums stacks across bags and returns nil for a bank that reports no slots", function()
            local contents = {
                [0] = { { itemID = 100, stackCount = 5 }, { itemID = 200, stackCount = 1 } },
                [1] = { { itemID = 100, stackCount = 3 } },
            }
            local Adapter = loadAdapter({
                C_Container = {
                    GetContainerNumSlots = function(bag)
                        return contents[bag] and #contents[bag] or 0
                    end,
                    GetContainerItemInfo = function(bag, slot)
                        return contents[bag] and contents[bag][slot]
                    end,
                },
            })
            assert.are.same({ [100] = 8, [200] = 1 }, Adapter.GetBagContents())
            assert.is_nil(Adapter.GetBankContents())
        end)

        it("reads the bank when it reports slots", function()
            local Adapter = loadAdapter({
                C_Container = {
                    GetContainerNumSlots = function(bag)
                        return bag == -1 and 1 or 0
                    end,
                    GetContainerItemInfo = function()
                        return { itemID = 300, stackCount = 2 }
                    end,
                },
            })
            assert.are.same({ [300] = 2 }, Adapter.GetBankContents())
        end)

        it("normalises GetItemStats output from the global fallback", function()
            local Adapter = loadAdapter({
                GetItemStats = function()
                    return { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_NEW_THING_SHORT = 4 }
                end,
            })
            local stats = Adapter.GetItemStats("link")
            assert.are.equal(10, stats.str)
            assert.are.equal(4, stats.other.ITEM_MOD_NEW_THING_SHORT)
        end)

        it("warns once about an unknown stat key", function()
            local Adapter, printed = loadAdapter({
                GetItemStats = function()
                    return { ITEM_MOD_NEW_THING_SHORT = 4 }
                end,
            })
            Adapter.GetItemStats("link")
            Adapter.GetItemStats("link")
            assert.are.equal(1, #printed)
            assert.is_truthy(string.find(printed[1], "ITEM_MOD_NEW_THING_SHORT", 1, true))
        end)

        it("turns an error inside an API into nil plus one warning", function()
            local Adapter, printed = loadAdapter({
                GetInventoryItemID = function()
                    error("api exploded")
                end,
                GetInventoryItemLink = function() end,
            })
            assert.is_nil(Adapter.GetEquipped())
            assert.is_nil(Adapter.GetEquipped())
            assert.are.equal(1, #printed)
        end)

        it("returns equipped items by slot", function()
            local Adapter = loadAdapter({
                GetInventoryItemID = function(_, slot)
                    return slot == 16 and 777 or nil
                end,
                GetInventoryItemLink = function(_, slot)
                    return "link" .. slot
                end,
            })
            assert.are.same({ [16] = { itemID = 777, link = "link16" } }, Adapter.GetEquipped())
        end)

        it("lists only learned recipes and resolves difficulty names from the enum", function()
            local Adapter = loadAdapter({
                Enum = { TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 } },
                C_TradeSkillUI = {
                    GetAllRecipeIDs = function()
                        return { 11, 12 }
                    end,
                    GetRecipeInfo = function(recipeID)
                        return { name = "Recipe " .. recipeID, learned = recipeID == 11, relativeDifficulty = 1 }
                    end,
                    GetRecipeSchematic = function()
                        return {
                            outputItemID = 900,
                            quantityMin = 1,
                            quantityMax = 2,
                            reagentSlotSchematics = {
                                { quantityRequired = 4, reagents = { { itemID = 50 } } },
                                { quantityRequired = 1, reagents = {} },
                            },
                        }
                    end,
                },
            })
            assert.are.same({
                {
                    recipeID = 11, name = "Recipe 11", difficulty = "medium", outputItemID = 900,
                    outputMin = 1, outputMax = 2, reagents = { { itemID = 50, qty = 4 } },
                },
            }, Adapter.GetKnownRecipes())
        end)

        it("returns cached item basics synchronously", function()
            local Adapter = loadAdapter({
                C_Item = {
                    GetItemInfo = function()
                        return "Sword", "link", 3, 20, 10, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 111, 500, 2, 7
                    end,
                },
            })
            local got
            Adapter.GetItemBasics(5, function(basics)
                got = basics
            end)
            assert.are.same({
                name = "Sword", link = "link", quality = 3, ilvl = 20, reqLevel = 10, equipLoc = "INVTYPE_WEAPON",
                classID = 2, subClassID = 7, sellPrice = 500, icon = 111,
            }, got)
        end)

        it("loads uncached item basics asynchronously", function()
            local cached = false
            local pendingLoad
            local Adapter = loadAdapter({
                C_Item = {
                    GetItemInfo = function()
                        if cached then
                            return "Axe", "link", 2, 5, 1, "Weapon", "Axe", 1, "INVTYPE_WEAPON", 1, 10, 2, 0
                        end
                        return nil
                    end,
                },
                Item = {
                    CreateFromItemID = function()
                        return {
                            ContinueOnItemLoad = function(_, callback)
                                pendingLoad = callback
                            end,
                        }
                    end,
                },
            })
            local results = {}
            Adapter.GetItemBasics(5, function(basics)
                results[#results + 1] = basics
            end)
            assert.are.equal(0, #results)
            cached = true
            pendingLoad()
            assert.are.equal(1, #results)
            assert.are.equal("Axe", results[1].name)
        end)

        it("schedules timers through C_Timer.After", function()
            local scheduled
            local Adapter = loadAdapter({
                C_Timer = {
                    After = function(delay, fn)
                        scheduled = { delay = delay, fn = fn }
                    end,
                },
            })
            local function task() end
            assert.is_true(Adapter.After(0.5, task))
            assert.are.equal(0.5, scheduled.delay)
            assert.are.equal(task, scheduled.fn)
        end)

        it("returns equipment sets by name with id, icon and item per slot (SPEC_V2 5.4)", function()
            local Adapter = loadAdapter({
                C_EquipmentSet = {
                    GetEquipmentSetIDs = function()
                        return { 3, 4 }
                    end,
                    GetEquipmentSetInfo = function(setID)
                        return setID == 3 and "Tank" or "DPS", 130000 + setID, setID
                    end,
                    GetItemIDs = function(setID)
                        if setID == 3 then
                            return { [16] = 900011, [17] = 900012, [1] = 0 }
                        end
                        return { [16] = 900021 }
                    end,
                },
            })
            assert.are.same({
                Tank = { id = 3, icon = 130003, [16] = 900011, [17] = 900012 },
                DPS = { id = 4, icon = 130004, [16] = 900021 },
            }, Adapter.GetEquipmentSets())
        end)

        it("reads zone and group kinds", function()
            local Adapter = loadAdapter({
                IsInInstance = function()
                    return true, "party"
                end,
                IsInGroup = function()
                    return true
                end,
                IsInRaid = function()
                    return false
                end,
            })
            assert.are.equal("instance", Adapter.GetZoneKind())
            assert.are.equal("party", Adapter.GetGroupKind())
            local scenario = loadAdapter({
                IsInInstance = function()
                    return true, "scenario"
                end,
            })
            assert.are.equal("openWorld", scenario.GetZoneKind())
        end)

        it("reads death, encounter and challenge-mode state as booleans", function()
            local Adapter = loadAdapter({
                UnitIsDeadOrGhost = function()
                    return 1
                end,
                IsEncounterInProgress = function()
                    return nil
                end,
                C_ChallengeMode = {
                    IsChallengeModeActive = function()
                        return true
                    end,
                },
            })
            assert.is_true(Adapter.IsPlayerDead())
            assert.is_false(Adapter.IsEncounterInProgress())
            assert.is_true(Adapter.IsChallengeModeActive())
        end)

        it("resolves spell names through C_Spell.GetSpellInfo", function()
            local Adapter = loadAdapter({
                C_Spell = {
                    GetSpellInfo = function(name)
                        if name == "Charge" then
                            return { name = "Charge", spellID = 900100 }
                        end
                        return nil
                    end,
                },
                IsPlayerSpell = function(spellID)
                    return spellID == 900100
                end,
            })
            assert.are.equal(900100, Adapter.GetSpellIDByName("Charge"))
            assert.is_nil(Adapter.GetSpellIDByName("Unknown Ability"))
            assert.is_true(Adapter.IsPlayerSpell(900100))
            assert.is_false(Adapter.IsPlayerSpell(900101))
        end)

        it("reports player identity", function()
            local Adapter = loadAdapter({
                UnitName = function()
                    return "Hugh"
                end,
                UnitClass = function()
                    return "Warrior", "WARRIOR"
                end,
                UnitLevel = function()
                    return 80
                end,
                GetRealmName = function()
                    return "Realm"
                end,
            })
            assert.are.same({ name = "Hugh", realm = "Realm", classFile = "WARRIOR", level = 80 },
                Adapter.GetPlayerMeta())
        end)
    end)
end)
