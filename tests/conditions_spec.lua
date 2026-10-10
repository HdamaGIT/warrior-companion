-- Condition vocabulary (SPEC_V2 §7.1): every condition true, false and unknown.
local H = dofile("tests/helpers/load_addon.lua")

local ns = {}
H.loadFile(ns, "Combat/Conditions.lua")
local Conditions = ns.Conditions

local function snap(fields)
    return fields
end

-- { condition, args, snapshot giving true, snapshot giving false, snapshot giving unknown }
local CASES = {
    { "inCombat", {}, snap({ inCombat = true }), snap({ inCombat = false }), snap({}) },
    { "outOfCombat", {}, snap({ inCombat = false }), snap({ inCombat = true }), snap({}) },
    { "stance", { "Battle Stance" }, snap({ stance = "Battle Stance" }), snap({ stance = "Defensive Stance" }),
        snap({}) },
    { "spellUsable", { "Overpower" }, snap({ spells = { Overpower = { usable = true } } }),
        snap({ spells = { Overpower = { usable = false } } }), snap({ spells = { Overpower = {} } }) },
    { "cooldownReady", { "Charge" }, snap({ spells = { Charge = { cooldown = 1.2 } } }),
        snap({ spells = { Charge = { cooldown = 9 } } }), snap({ spells = {} }) },
    { "rageAtLeast", { 10 }, snap({ rage = 10 }), snap({ rage = 9 }), snap({}) },
    { "targetHealthBelow", { 0.2 }, snap({ targetHealth = 0.1 }), snap({ targetHealth = 0.5 }), snap({}) },
    { "targetHostile", {}, snap({ targetHostile = true }), snap({ targetHostile = false }), snap({}) },
    { "targetCasting", { true }, snap({ targetCasting = true, targetCastInterruptible = true }),
        snap({ targetCasting = false }), snap({}) },
    { "auraMissing", { "player", "Battle Shout", false },
        snap({ auras = { player = { ["Battle Shout"] = { state = false } } } }),
        snap({ auras = { player = { ["Battle Shout"] = { state = true } } } }),
        snap({ auras = { player = { ["Battle Shout"] = { state = nil } } } }) },
    { "auraExpiringWithin", { "player", "Battle Shout", 10 },
        snap({ auras = { player = { ["Battle Shout"] = { state = true, remaining = 8 } } } }),
        snap({ auras = { player = { ["Battle Shout"] = { state = true, remaining = 30 } } } }),
        snap({ auras = { player = { ["Battle Shout"] = { state = true } } } }) },
    { "auraStacksBelow", { "target", "Sunder Armor", 5 },
        snap({ auras = { target = { ["Sunder Armor"] = { state = true, stacks = 3 } } } }),
        snap({ auras = { target = { ["Sunder Armor"] = { state = true, stacks = 5 } } } }),
        snap({ auras = {} }) },
    { "inRange", { "Charge", "target" }, snap({ spells = { Charge = { inRange = true } } }),
        snap({ spells = { Charge = { inRange = false } } }), snap({ spells = { Charge = {} } }) },
    { "notInRange", { "Charge", "target" }, snap({ spells = { Charge = { inRange = false } } }),
        snap({ spells = { Charge = { inRange = true } } }), snap({}) },
    { "autoAttacking", { false }, snap({ autoAttacking = false }), snap({ autoAttacking = true }), snap({}) },
    { "hasShield", { true }, snap({ hasShield = true }), snap({ hasShield = false }), snap({}) },
    { "partyMissingAura", { "Battle Shout", 2 }, snap({ partyMissing = { ["Battle Shout"] = 3 } }),
        snap({ partyMissing = { ["Battle Shout"] = 1 } }), snap({}) },
}

describe("conditions", function()
    for _, case in ipairs(CASES) do
        local name, args = case[1], case[2]
        it(name .. " is true, false and unknown", function()
            assert.is_true(Conditions.Exists(name))
            assert.is_true(Conditions.Evaluate(name, case[3], unpack(args)))
            assert.is_false(Conditions.Evaluate(name, case[4], unpack(args)))
            assert.is_nil(Conditions.Evaluate(name, case[5], unpack(args)))
        end)
    end

    it("covers the whole vocabulary", function()
        local tested = {}
        for _, case in ipairs(CASES) do
            tested[case[1]] = true
        end
        for name in pairs(Conditions.evaluators) do
            assert.is_true(tested[name] == true, name .. " has no test")
        end
    end)

    it("treats an unknown condition name as unknown", function()
        assert.is_false(Conditions.Exists("rotationNext"))
        assert.is_nil(Conditions.Evaluate("rotationNext", {}))
    end)

    it("auraMissing with fromPlayer counts someone else's aura as missing; unknown source counts as present", function()
        local other = { auras = { player = { ["Battle Shout"] = { state = true, fromPlayer = false } } } }
        local unknownSource = { auras = { player = { ["Battle Shout"] = { state = true } } } }
        assert.is_true(Conditions.Evaluate("auraMissing", other, "player", "Battle Shout", true))
        assert.is_false(Conditions.Evaluate("auraMissing", other, "player", "Battle Shout", false))
        assert.is_false(Conditions.Evaluate("auraMissing", unknownSource, "player", "Battle Shout", true))
    end)

    it("an absent aura is not expiring and has 0 stacks", function()
        local absent = { auras = { target = { ["Sunder Armor"] = { state = false } } } }
        assert.is_false(Conditions.Evaluate("auraExpiringWithin", absent, "target", "Sunder Armor", 5))
        assert.is_true(Conditions.Evaluate("auraStacksBelow", absent, "target", "Sunder Armor", 5))
    end)

    it("inRange is unknown for units other than the target in M5", function()
        local s = { spells = { Charge = { inRange = true } } }
        assert.is_nil(Conditions.Evaluate("inRange", s, "Charge", "focus"))
    end)

    describe("All (three-valued AND)", function()
        local function c(value)
            return { function()
                return value
            end }
        end

        it("false wins over unknown, unknown wins over true, empty is true", function()
            assert.is_false(Conditions.All({ c(nil), c(false), c(true) }, {}))
            assert.is_nil(Conditions.All({ c(true), c(nil) }, {}))
            assert.is_true(Conditions.All({ c(true), c(true) }, {}))
            assert.is_true(Conditions.All({}, {}))
        end)
    end)
end)
