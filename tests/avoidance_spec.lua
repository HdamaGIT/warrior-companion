-- Avoidance detector (SPEC_V2 §7.4, D-027) over the run 2 stream fixtures and the ASSUMED shapes.
local H = dofile("tests/helpers/load_addon.lua")
local MockAdapter = dofile("tests/helpers/mock_adapter.lua")
local Replay = dofile("tests/helpers/replay.lua")

local FILES = { "Combat/Avoidance.lua" }

--- Boots Core + Avoidance, replays a stream and returns the WW_AVOIDANCE and WW_PLAYER_SPELL_MISSED payloads.
-- data overrides the stream's start data (e.g. secrecy = "all").
local function replay(streamName, data)
    local stream = Replay.load(streamName)
    Replay.merge(stream.start.data, data or {})
    local mock = MockAdapter.new(stream.start.data)
    local ns = H.boot(mock, FILES)
    local avoided, missed = {}, {}
    local listener = {}
    function listener:OnAvoidance(direction, kind, partial, amount)
        avoided[#avoided + 1] =
            { t = mock.Now(), direction = direction, kind = kind, partial = partial, amount = amount }
    end
    function listener:OnMissed(ability, kind)
        missed[#missed + 1] = { t = mock.Now(), ability = ability, kind = kind }
    end
    ns.Events:On("WW_AVOIDANCE", listener, "OnAvoidance")
    ns.Events:On("WW_PLAYER_SPELL_MISSED", listener, "OnMissed")
    Replay.run(mock, stream, { offset = 0 })
    return avoided, missed, mock, ns
end

describe("avoidance", function()
    describe("Classify", function()
        it("reads player events as incoming and target events as outgoing", function()
            local Avoidance = H.bootSandbox({ adapter = MockAdapter.new(), extraFiles = FILES }).Avoidance
            assert.are.same({ "incoming", "parry", false }, { Avoidance.Classify("player", "PARRY", "") })
            assert.are.same({ "outgoing", "miss", false }, { Avoidance.Classify("target", "MISS", "") })
            assert.are.same({ "outgoing", "block", true }, { Avoidance.Classify("target", "WOUND", "BLOCK_REDUCED") })
            assert.is_nil(Avoidance.Classify("player", "WOUND", ""))
            assert.is_nil(Avoidance.Classify("player", "WOUND", "CRITICAL"))
            assert.is_nil(Avoidance.Classify("nameplate1", "PARRY", ""))
        end)
    end)

    describe("run 2 streams", function()
        it("fight 1: one parry on the player and one partial block on the target", function()
            local avoided, missed = replay("run2_fight_parry")
            assert.are.same({
                { t = 5.333, direction = "incoming", kind = "parry", partial = false, amount = 0 },
                { t = 12.140, direction = "outgoing", kind = "block", partial = true, amount = 19 },
            }, avoided)
            assert.are.same({}, missed)
        end)

        it("fight 7: a miss on the player in combat, one on the target after it; Heroic Strike pairs with nothing",
            function()
                local avoided, missed = replay("run2_misses")
                assert.are.equal(2, #avoided)
                assert.are.same({ 7.624, "incoming", "miss" }, { avoided[1].t, avoided[1].direction, avoided[1].kind })
                assert.are.same({ 16.516, "outgoing", "miss" }, { avoided[2].t, avoided[2].direction, avoided[2].kind })
                assert.are.same({}, missed)
            end)

        it("fight 8: parries both ways; a parry 0.98s after a cast is not paired with it", function()
            local avoided, missed = replay("run2_target_parry")
            assert.are.equal(2, #avoided)
            assert.are.equal("incoming", avoided[1].direction)
            assert.are.equal("outgoing", avoided[2].direction)
            assert.are.equal("parry", avoided[2].kind)
            assert.are.same({}, missed)
        end)
    end)

    describe("ASSUMED shapes (not yet seen in the beta)", function()
        it("dodge, block, partial block, a taunt resist and a target dodge; nameplate units are ignored", function()
            local avoided, missed = replay("assumed_avoidance")
            local kinds = {}
            for index, event in ipairs(avoided) do
                kinds[index] = event.direction .. ":" .. event.kind .. (event.partial and "~" or "")
            end
            assert.are.same(
                { "incoming:dodge", "incoming:block", "incoming:block~", "outgoing:resist", "outgoing:dodge" }, kinds)
            assert.are.same({ { t = 4.1, ability = "Taunt", kind = "resist" } }, missed)
        end)
    end)

    describe("pairing window", function()
        local function detector()
            local fresh = H.bootSandbox({ adapter = MockAdapter.new(), extraFiles = FILES })
            return fresh.Avoidance.NewDetector(0.5, { Taunt = true })
        end

        it("does not pair once the window has passed", function()
            local d = detector()
            d:OnCast("Taunt", 10)
            local _, _, _, missed = d:OnUnitCombat(10.6, "target", "RESIST", "")
            assert.is_nil(missed)
        end)

        it("a hit on the target settles the cast, so a later avoidance is not blamed on it", function()
            local d = detector()
            d:OnCast("Taunt", 10)
            d:OnUnitCombat(10.1, "target", "WOUND", "")
            local _, _, _, missed = d:OnUnitCombat(10.2, "target", "PARRY", "")
            assert.is_nil(missed)
        end)

        it("ignores casts of abilities not in the list", function()
            local d = detector()
            d:OnCast("Heroic Strike", 10)
            local _, _, _, missed = d:OnUnitCombat(10.1, "target", "DODGE", "")
            assert.is_nil(missed)
        end)
    end)

    describe("suspension and secrets", function()
        it("publishes nothing while restricted (Encounter active)", function()
            local avoided = replay("assumed_avoidance", { restriction = { encounter = true } })
            assert.are.same({}, avoided)
        end)

        it("publishes nothing and raises nothing in secret mode", function()
            local avoided, missed = replay("run2_fight_parry", { secrecy = "all" })
            assert.are.same({}, avoided)
            assert.are.same({}, missed)
        end)
    end)
end)
