local H = dofile("tests/helpers/load_addon.lua")

local ADDON = "WarriorWorkshop"

-- Fake spell IDs (9xxxxx): real Forever IDs are unknown until V-22.
local IDS = { ["Battle Shout"] = 900001, Charge = 900002, Overpower = 900003 }

describe("spell map", function()
    describe("Resolve", function()
        local SpellMap

        before_each(function()
            SpellMap = H.bootSandbox({ adapter = H.mockAdapter.new() }).SpellMap
        end)

        local function lookup(name)
            return IDS[name]
        end
        local function knowsAll()
            return true
        end

        it("maps known names and lists the rest as unknown, sorted", function()
            local ids, unknown = SpellMap.Resolve({ "Charge", "Zeal", "Battle Shout", "Apple" }, lookup, knowsAll)
            assert.are.same({ Charge = 900002, ["Battle Shout"] = 900001 }, ids)
            assert.are.same({ "Apple", "Zeal" }, unknown)
        end)

        it("treats a resolved but unlearned spell as unknown", function()
            local ids, unknown = SpellMap.Resolve({ "Charge", "Overpower" }, lookup, function(spellID)
                return spellID ~= 900003
            end)
            assert.are.same({ Charge = 900002 }, ids)
            assert.are.same({ "Overpower" }, unknown)
        end)

        it("treats 'cannot tell' (nil) as known", function()
            local ids = SpellMap.Resolve({ "Charge" }, lookup, function()
                return nil
            end)
            assert.are.equal(900002, ids.Charge)
        end)

        it("lets a positive manual override win and ignores invalid ones", function()
            local ids, unknown = SpellMap.Resolve({ "Charge", "Zeal", "Overpower" }, lookup, knowsAll,
                { Zeal = 900099, Charge = 900050, Overpower = "junk" })
            assert.are.same({ Charge = 900050, Zeal = 900099, Overpower = 900003 }, ids)
            assert.are.same({}, unknown)
        end)
    end)

    describe("module", function()
        local mock, ns, SpellMap, fired

        before_each(function()
            mock = H.mockAdapter.new({ spellIDs = { ["Battle Shout"] = 900001, Charge = 900002 } })
            ns = H.bootSandbox({ adapter = mock })
            SpellMap = ns.SpellMap
            fired = 0
            local listener = {}
            function listener:OnChange()
                fired = fired + 1
            end
            ns.Events:On("WW_SPELLMAP_CHANGED", listener, "OnChange")
            SpellMap:Register("Battle Shout")
            SpellMap:Register("Charge")
            SpellMap:Register("Charge") -- duplicates are ignored
            SpellMap:Register("Revenge")
            mock.frame:Fire("ADDON_LOADED", ADDON)
            mock.frame:Fire("PLAYER_LOGIN")
        end)

        it("resolves registered names at login", function()
            assert.are.same({ "Battle Shout", "Charge", "Revenge" }, SpellMap.names)
            assert.are.equal(900001, SpellMap:Get("Battle Shout"))
            assert.is_nil(SpellMap:Get("Revenge"))
            assert.are.same({ "Revenge" }, SpellMap:GetUnknown())
            assert.are.equal(1, fired)
        end)

        it("uses spellOverrides from the character's saved data", function()
            ns.DB.GetCharacter().combat.spellOverrides.Revenge = 900010
            SpellMap:Refresh()
            assert.are.equal(900010, SpellMap:Get("Revenge"))
            assert.are.same({}, SpellMap:GetUnknown())
        end)

        it("refreshes once, debounced, after a burst of SPELLS_CHANGED", function()
            mock.data.spellIDs.Revenge = 900004
            mock.frame:Fire("SPELLS_CHANGED")
            mock.frame:Fire("SPELLS_CHANGED")
            assert.is_nil(SpellMap:Get("Revenge"))
            mock.advance(1)
            assert.are.equal(900004, SpellMap:Get("Revenge"))
            assert.are.equal(2, fired)
        end)

        it("does not fire when nothing changed", function()
            SpellMap:Refresh()
            assert.are.equal(1, fired)
        end)

        it("returns a copy of the unknown list", function()
            local unknown = SpellMap:GetUnknown()
            unknown[1] = "changed"
            assert.are.same({ "Revenge" }, SpellMap:GetUnknown())
        end)
    end)
end)
