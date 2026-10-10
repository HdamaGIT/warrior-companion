-- Rule engine (SPEC_V2 §7.1, D-048): compile, unknown -> hidden, states, contexts, delay, throttle.
local H = dofile("tests/helpers/load_addon.lua")

local ns = {}
H.loadFile(ns, "Combat/Conditions.lua")
H.loadFile(ns, "Combat/Rules.lua")
local Rules = ns.Rules

local OPEN = { zone = "openWorld", restricted = false, dead = false }
local IDS = { Overpower = 7384, ["Battle Shout"] = 6673, Charge = 100 }

local function overpower(extra)
    local def = { id = "overpower", label = "Overpower", ability = "Overpower", severity = "reactive",
        display = "strip", when = { { "spellUsable", "@ability" } } }
    for key, value in pairs(extra or {}) do
        def[key] = value
    end
    return def
end

local function battleShout()
    return {
        id = "battleShout", label = "Battle Shout", ability = "Battle Shout", severity = "dropped", display = "big",
        countdown = "player", args = { expiring = 10 },
        states = {
            { name = "dropped", when = { { "auraMissing", "player", "@ability", false } } },
            { name = "expiring", when = { { "auraExpiringWithin", "player", "@ability", "$expiring" } } },
        },
    }
end

local function snapshotWith(usable, aura)
    return {
        spells = { Overpower = { usable = usable } },
        auras = { player = { ["Battle Shout"] = aura or { state = true, remaining = 100 } } },
    }
end

describe("rules", function()
    describe("Compile", function()
        it("compiles known rules and records what they need", function()
            local compiled = Rules.Compile({ overpower(), battleShout() }, nil, IDS)
            assert.are.equal(2, #compiled.rules)
            assert.are.same({ "Overpower" }, compiled.needs.spells)
            assert.are.same({ { "player", "Battle Shout" } }, compiled.needs.auras)
            assert.are.same({}, compiled.disabled)
        end)

        it("disables a rule whose ability is unknown (auto-disable, SPEC_V2 §5.3)", function()
            local compiled = Rules.Compile({ overpower() }, nil, { Charge = 100 })
            assert.are.equal(0, #compiled.rules)
            assert.are.same({ { id = "overpower", reason = "unknownAbility", detail = "Overpower" } },
                compiled.disabled)
        end)

        it("disables a rule that uses a condition outside the vocabulary", function()
            local compiled = Rules.Compile({ overpower({ when = { { "pressThisNext" } } }) }, nil, IDS)
            assert.are.equal("unknownCondition", compiled.disabled[1].reason)
        end)

        it("disables a rule whose condition names an unknown ability", function()
            local compiled = Rules.Compile({ overpower({ when = { { "inRange", "Intercept", "target" } } }) }, nil, IDS)
            assert.are.same({ id = "overpower", reason = "unknownAbility", detail = "Intercept" }, compiled.disabled[1])
        end)

        it("honours sparse overrides: enabled = false, and args of the right type only", function()
            local off = Rules.Compile({ overpower() }, { overpower = { enabled = false } }, IDS)
            assert.are.equal("disabled", off.disabled[1].reason)
            local compiled = Rules.Compile({ battleShout() },
                { battleShout = { args = { expiring = 20, bogus = 1 } } }, IDS)
            assert.are.same({ expiring = 20 }, compiled.rules[1].args)
            local wrongType = Rules.Compile({ battleShout() }, { battleShout = { args = { expiring = "x" } } }, IDS)
            assert.are.equal(10, wrongType.rules[1].args.expiring)
        end)

        it("a rule disabled by default can be switched on by an override", function()
            local compiled = Rules.Compile({ overpower({ enabled = false }) }, { overpower = { enabled = true } }, IDS)
            assert.are.equal(1, #compiled.rules)
        end)
    end)

    describe("Evaluate", function()
        local out

        before_each(function()
            out = {}
        end)

        it("shows a rule when its conditions are true and hides it when false or unknown", function()
            local compiled = Rules.Compile({ overpower() }, nil, IDS)
            assert.are.same({ 1, true }, { Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out) })
            assert.are.equal("overpower", out[1].id)
            assert.are.equal("reactive", out[1].severity)
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(nil), OPEN, 1, out)))
            assert.is_nil(out[1])
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 2, out)
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(false), OPEN, 3, out)))
        end)

        it("reports no change when nothing visible changed", function()
            local compiled = Rules.Compile({ overpower() }, nil, IDS)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out)
            local _, changed = Rules.Evaluate(compiled, snapshotWith(true), OPEN, 1, out)
            assert.is_false(changed)
        end)

        it("picks the first matching state and counts down in whole seconds", function()
            local compiled = Rules.Compile({ battleShout() }, nil, IDS)
            Rules.Evaluate(compiled, snapshotWith(false, { state = true, remaining = 8.4 }), OPEN, 0, out)
            assert.are.equal("expiring", out[1].state)
            assert.are.equal(8.4, out[1].remaining)
            local later = snapshotWith(false, { state = true, remaining = 8.1 })
            local _, changed = Rules.Evaluate(compiled, later, OPEN, 0.3, out)
            assert.is_false(changed)
            later = snapshotWith(false, { state = true, remaining = 7.9 })
            _, changed = Rules.Evaluate(compiled, later, OPEN, 0.5, out)
            assert.is_true(changed)
            Rules.Evaluate(compiled, snapshotWith(false, { state = false }), OPEN, 9, out)
            assert.are.equal("dropped", out[1].state)
            assert.are.equal("dropped", out[1].severity)
        end)

        it("hides everything while restricted or dead, and outside the rule's contexts", function()
            local compiled = Rules.Compile({ overpower({ contexts = { "instance" } }) }, nil, IDS)
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out)))
            local instance = { zone = "instance", restricted = false, dead = false }
            assert.are.equal(1, (Rules.Evaluate(compiled, snapshotWith(true), instance, 1, out)))
            local restricted = { zone = "instance", restricted = true, dead = false }
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(true), restricted, 2, out)))
            local dead = { zone = "instance", restricted = false, dead = true }
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(true), dead, 3, out)))
        end)

        it("waits `delay` seconds before showing and reports when to retry (S-04)", function()
            local compiled = Rules.Compile({ overpower({ delay = 1.5 }) }, nil, IDS)
            local count, _, retryIn = Rules.Evaluate(compiled, snapshotWith(true), OPEN, 10, out)
            assert.are.equal(0, count)
            assert.are.equal(1.5, retryIn)
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(true), OPEN, 11, out)))
            assert.are.equal(1, (Rules.Evaluate(compiled, snapshotWith(true), OPEN, 11.5, out)))
        end)

        it("restarts the delay when the conditions break", function()
            local compiled = Rules.Compile({ overpower({ delay = 1.5 }) }, nil, IDS)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out)
            Rules.Evaluate(compiled, snapshotWith(false), OPEN, 1, out)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 1.2, out)
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(true), OPEN, 2, out)))
            assert.are.equal(1, (Rules.Evaluate(compiled, snapshotWith(true), OPEN, 2.7, out)))
        end)

        it("limits visible changes to one per `throttle` seconds", function()
            local compiled = Rules.Compile({ overpower({ throttle = 0.5 }) }, nil, IDS)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out)
            local count, changed, retryIn = Rules.Evaluate(compiled, snapshotWith(false), OPEN, 0.2, out)
            assert.are.equal(1, count)
            assert.is_false(changed)
            assert.is_true(math.abs(retryIn - 0.3) < 1e-9)
            assert.are.equal(0, (Rules.Evaluate(compiled, snapshotWith(false), OPEN, 0.5, out)))
        end)

        it("reuses the same entry tables (no allocation per evaluation)", function()
            local compiled = Rules.Compile({ overpower() }, nil, IDS)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out)
            local first = out[1]
            Rules.Evaluate(compiled, snapshotWith(false), OPEN, 1, out)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 2, out)
            assert.are.equal(first, out[1])
        end)

        it("reports when an aura timer will cross a threshold, so the caller can wake up without a game event",
            function()
                local compiled = Rules.Compile({ battleShout() }, nil, IDS)
                local _, _, retryIn = Rules.Evaluate(compiled, snapshotWith(false, { state = true, remaining = 25 }),
                    OPEN, 0, out)
                assert.are.equal(15, retryIn) -- 25s left, "expiring" at 10s
            end)

        it("AbilityNames lists rule abilities and ability arguments once each", function()
            local names = Rules.AbilityNames({ battleShout(), overpower({ when = { { "inRange", "Charge", "target" },
                { "spellUsable", "@ability" } } }) })
            assert.are.same({ "Battle Shout", "Overpower", "Charge" }, names)
        end)

        it("Reset hides everything and says whether anything was visible", function()
            local compiled = Rules.Compile({ overpower() }, nil, IDS)
            Rules.Evaluate(compiled, snapshotWith(true), OPEN, 0, out)
            assert.is_true(Rules.Reset(compiled))
            assert.is_false(Rules.Reset(compiled))
        end)
    end)
end)
