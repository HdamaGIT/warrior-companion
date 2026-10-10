-- AuraTracker (U-01 degraded tracking, D-048) and Snapshot (per-tick read model).
local H = dofile("tests/helpers/load_addon.lua")
local MockAdapter = dofile("tests/helpers/mock_adapter.lua")

local ns = {}
H.loadFile(ns, "Combat/AuraTracker.lua")
H.loadFile(ns, "Combat/Snapshot.lua")
local AuraTracker, Snapshot = ns.AuraTracker, ns.Snapshot

local BS = "Battle Shout"

describe("AuraTracker", function()
    it("knows nothing until something is observed or cast", function()
        assert.is_nil(AuraTracker.New():Get(BS, 0))
    end)

    it("carries the last real expiry on after auras turn secret", function()
        local tracker = AuraTracker.New()
        tracker:Observe(BS, 100, true, 120, 180, true)
        local state, remaining, fromPlayer = tracker:Get(BS, 150)
        assert.are.same({ true, 70, true }, { state, remaining, fromPlayer })
        assert.is_false((tracker:Get(BS, 221)))
    end)

    it("an own cast restarts the timer with the learned duration", function()
        local tracker = AuraTracker.New()
        tracker:Observe(BS, 0, true, 180, 180, true)
        tracker:OnCast(BS, 170)
        local _, remaining = tracker:Get(BS, 200)
        assert.are.equal(150, remaining)
        assert.are.equal(180, tracker:GetDuration(BS))
    end)

    it("an own cast with no learned duration is present with unknown time left", function()
        local tracker = AuraTracker.New()
        tracker:OnCast(BS, 10)
        local state, remaining = tracker:Get(BS, 5000)
        assert.is_true(state)
        assert.is_nil(remaining)
    end)

    it("a real absent read clears the aura but keeps the learned duration", function()
        local tracker = AuraTracker.New()
        tracker:Observe(BS, 0, true, 180, 180)
        tracker:Observe(BS, 10, false)
        assert.is_false((tracker:Get(BS, 11)))
        tracker:OnCast(BS, 20)
        local _, remaining = tracker:Get(BS, 20)
        assert.are.equal(180, remaining)
    end)

    it("a permanent aura is present with no expiry", function()
        local tracker = AuraTracker.New()
        tracker:Observe("Defensive Stance", 0, true, nil, 0)
        assert.is_true((tracker:Get("Defensive Stance", 1e6)))
    end)
end)

describe("Snapshot", function()
    local needs = { spells = { "Charge", "Overpower" }, auras = { { "player", BS } } }
    local ids = { Charge = 100, [BS] = 6673 } -- Overpower not known

    local function newMock(extra)
        local data = {
            combat = {
                usable = { [100] = true }, inRange = { [100] = true }, cooldowns = { [100] = 0 },
                autoAttacking = false, target = { exists = true, hostile = true },
                stance = { index = 1, name = "Battle Stance" },
                auras = { player = { [BS] = { stacks = 0, expires = 120, duration = 180, fromPlayer = true } } },
            },
        }
        for key, value in pairs(extra or {}) do
            data[key] = value
        end
        return MockAdapter.new(data)
    end

    it("fills spells, target, stance and auras from the adapter", function()
        local mock = newMock()
        local snapshot = Snapshot.New(needs)
        Snapshot.Update(snapshot, needs, mock, ids, AuraTracker.New(), false, 0)
        assert.is_true(snapshot.targetHostile)
        assert.are.equal("Battle Stance", snapshot.stance)
        assert.is_false(snapshot.autoAttacking)
        assert.are.same({ usable = true, noPower = false, cooldown = 0, inRange = true }, snapshot.spells.Charge)
        assert.are.same({}, snapshot.spells.Overpower) -- unknown ability: everything unknown
        assert.are.same({ state = true, stacks = 0, remaining = 120, fromPlayer = true }, snapshot.auras.player[BS])
    end)

    it("reuses the same tables on every update", function()
        local mock = newMock()
        local snapshot = Snapshot.New(needs)
        local charge, aura = snapshot.spells.Charge, snapshot.auras.player[BS]
        local tracker = AuraTracker.New()
        Snapshot.Update(snapshot, needs, mock, ids, tracker, false, 0)
        Snapshot.Update(snapshot, needs, mock, ids, tracker, false, 1)
        assert.are.equal(charge, snapshot.spells.Charge)
        assert.are.equal(aura, snapshot.auras.player[BS])
    end)

    it("falls back to the tracker when auras turn secret in combat (run 2)", function()
        local mock = newMock({ secrecy = "run2" })
        local snapshot = Snapshot.New(needs)
        local tracker = AuraTracker.New()
        Snapshot.Update(snapshot, needs, mock, ids, tracker, false, 0)
        mock.data.inCombat = true
        mock.advance(100)
        Snapshot.Update(snapshot, needs, mock, ids, tracker, true, 100)
        assert.is_true(snapshot.auras.player[BS].state)
        assert.are.equal(20, snapshot.auras.player[BS].remaining)
        assert.is_nil(snapshot.rage)
        assert.is_nil(snapshot.targetHealth)
    end)

    it("leaves everything unknown in secret mode", function()
        local mock = newMock({ secrecy = "all" })
        local snapshot = Snapshot.New(needs)
        Snapshot.Update(snapshot, needs, mock, ids, AuraTracker.New(), true, 0)
        assert.is_nil(snapshot.targetHostile)
        assert.is_nil(snapshot.stance)
        assert.is_nil(snapshot.autoAttacking)
        assert.is_nil(snapshot.spells.Charge.usable)
        assert.is_nil(snapshot.auras.player[BS].state)
    end)
end)
