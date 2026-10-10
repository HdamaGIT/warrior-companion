-- The replay harness, mock clock and the mock adapter's combat accessors (test infrastructure for M5).
local MockClock = dofile("tests/helpers/mock_clock.lua")
local MockAdapter = dofile("tests/helpers/mock_adapter.lua")
local Replay = dofile("tests/helpers/replay.lua")

local STREAMS = { "run2_fight_parry", "run2_battle_shout", "run2_misses", "run2_target_parry", "assumed_avoidance" }

describe("mock clock", function()
    it("runs timers in due order, including timers scheduled by timers", function()
        local clock = MockClock.new(10)
        local order = {}
        clock.after(0.5, function()
            order[#order + 1] = "b"
            clock.after(0.1, function()
                order[#order + 1] = "c"
            end)
        end)
        clock.after(0.2, function()
            order[#order + 1] = "a"
        end)
        clock.advance(0.55)
        assert.are.same({ "a", "b" }, order)
        assert.are.equal(10.55, clock.now)
        clock.advance(0.1)
        assert.are.same({ "a", "b", "c" }, order)
        assert.are.equal(0, clock.pending())
    end)

    it("never moves backwards", function()
        local clock = MockClock.new(5)
        clock.advanceTo(3)
        assert.are.equal(5, clock.now)
    end)
end)

describe("replay harness", function()
    it("applies data before firing the event and advances the clock to each entry", function()
        local mock = MockAdapter.new()
        mock.CreateEventFrame()
        local seen = {}
        mock.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        mock.frame:SetScript("OnEvent", function(_, event)
            seen[#seen + 1] = { event = event, t = mock.Now(), inCombat = mock.InCombat() }
        end)
        Replay.run(mock, { events = {
            { t = 1.5, event = "PLAYER_REGEN_DISABLED", data = { inCombat = true } },
        } })
        assert.are.same({ { event = "PLAYER_REGEN_DISABLED", t = 1.5, inCombat = true } }, seen)
    end)

    it("runs timers that fall due between entries", function()
        local mock = MockAdapter.new()
        mock.CreateEventFrame()
        local fired
        mock.After(0.2, function()
            fired = mock.Now()
        end)
        Replay.run(mock, { events = { { t = 1.0, data = { x = 1 } } } })
        assert.are.equal(0.2, fired)
        assert.are.equal(1, mock.data.x)
    end)

    it("merges nested data and removes keys set to CLEAR", function()
        local target = { combat = { usable = { [1] = true, [2] = true } } }
        Replay.merge(target, { combat = { usable = { [2] = Replay.CLEAR, [3] = false } } })
        assert.are.same({ combat = { usable = { [1] = true, [3] = false } } }, target)
    end)

    for _, name in ipairs(STREAMS) do
        it("fixture " .. name .. " is well formed and time-ordered", function()
            local stream = Replay.load(name)
            assert.is_string(stream.source)
            local last = -1
            for _, entry in ipairs(stream.events) do
                assert.is_true(entry.t >= last, name .. " out of order at t=" .. tostring(entry.t))
                assert.is_true(entry.event ~= nil or entry.data ~= nil)
                last = entry.t
            end
        end)
    end
end)

describe("mock adapter combat accessors", function()
    local function newMock(extra)
        local data = {
            combat = {
                rage = 40, health = { target = 0.5 }, usable = { [5] = true }, inRange = { [5] = true },
                autoAttacking = true, target = { exists = true, hostile = true },
                stance = { index = 1, name = "Battle Stance" },
                auras = { player = {
                    ["Battle Shout"] = { stacks = 0, expires = 100, duration = 120, fromPlayer = true },
                } },
            },
        }
        for key, value in pairs(extra or {}) do
            data[key] = value
        end
        return MockAdapter.new(data)
    end

    it("returns plain values by default", function()
        local mock = newMock()
        assert.are.equal(40, (mock.GetRage()))
        local stacks, remaining, fromPlayer, duration = mock.GetAura("player", "Battle Shout")
        assert.are.same({ 0, 100, true, 120 }, { stacks, remaining, fromPlayer, duration })
        assert.is_false(mock.GetAura("player", "Demoralizing Shout"))
    end)

    it("hides rage, health, auras in combat and cooldown times in combat in run2 secrecy", function()
        local mock = newMock({ secrecy = "run2", inCombat = true })
        mock.data.combat.cooldowns = { [5] = 3 }
        assert.is_nil(mock.GetRage())
        assert.is_nil(mock.GetHealthPct("target"))
        assert.is_nil(mock.GetAura("player", "Battle Shout"))
        assert.is_nil(mock.GetSpellCooldownRemaining(5))
        assert.is_true((mock.IsSpellUsable(5)))
        assert.is_true(mock.IsSpellInRange(5, "target"))
    end)

    it("returns nil from every combat accessor in secret mode", function()
        local mock = newMock({ secrecy = "all" })
        assert.is_nil(mock.GetRage())
        assert.is_nil(mock.GetHealthPct("target"))
        assert.is_nil(mock.IsSpellUsable(5))
        assert.is_nil(mock.GetSpellCooldownRemaining(5))
        assert.is_nil(mock.IsSpellInRange(5, "target"))
        assert.is_nil(mock.IsAutoAttacking())
        assert.is_nil(mock.GetAura("player", "Battle Shout"))
        assert.is_nil(mock.GetTargetState())
        assert.is_nil(mock.GetStance())
        assert.is_nil(mock.ReadUnitCombat("player", "PARRY", "", 0, 1))
        assert.is_nil(mock.ReadSpellcast("player", "x", 6673))
    end)
end)
