-- Combat companion end to end on the mock adapter (SPEC_V2 §7.7): the rule pack, Battle Shout state transitions over
-- a replayed run 2 stream, the reactive rules, suspension, the ticker, and secret mode.
local H = dofile("tests/helpers/load_addon.lua")
local MockAdapter = dofile("tests/helpers/mock_adapter.lua")
local Replay = dofile("tests/helpers/replay.lua")

local IDS = {
    ["Battle Shout"] = 6673, Charge = 100, ["Heroic Strike"] = 284, Overpower = 7384, Execute = 5308,
    Intercept = 20252,
}

-- A hostile target in melee and Charge range, nothing usable, auto-attack on. Battle Shout ids show as
-- "battleShout:<state>" in the assertions below.
local function baseCombat()
    return {
        target = { exists = true, hostile = true },
        usable = { [100] = false, [284] = true, [7384] = false, [5308] = false },
        inRange = { [100] = true, [284] = true },
        autoAttacking = true,
        stance = { index = 1, name = "Battle Stance" },
        auras = { player = { ["Battle Shout"] = false } },
    }
end

--- Boots the whole add-on (Core + Combat) and records WW_* messages.
local function boot(data)
    data = data or {}
    data.spellIDs = data.spellIDs or IDS
    local mock = MockAdapter.new(data)
    local ns = H.bootSandbox({ adapter = mock, extraFiles = H.COMBAT_FILES })
    local log = { alerts = {}, suspended = {}, enabled = {}, last = {} }
    local listener = {}
    function listener:OnAlerts(alerts, count)
        local copy = {}
        for index = 1, count do
            local entry = alerts[index]
            copy[index] = { id = entry.id, state = entry.state, severity = entry.severity, display = entry.display,
                remaining = entry.remaining }
        end
        log.alerts[#log.alerts + 1] = { t = mock.Now(), count = count, list = copy }
        log.last = copy
    end
    function listener:OnSuspended(value)
        log.suspended[#log.suspended + 1] = value
    end
    function listener:OnEnabled(value)
        log.enabled[#log.enabled + 1] = value
    end
    ns.Events:On("WW_ALERTS_UPDATED", listener, "OnAlerts")
    ns.Events:On("WW_COMBAT_SUSPENDED", listener, "OnSuspended")
    ns.Events:On("WW_COMBAT_ENABLED", listener, "OnEnabled")
    mock.frame:Fire("ADDON_LOADED", "WarriorWorkshop")
    mock.frame:Fire("PLAYER_LOGIN")
    return mock, ns, log
end

local function ids(list)
    local out = {}
    for index, entry in ipairs(list or {}) do
        out[index] = entry.id == "battleShout" and (entry.id .. ":" .. tostring(entry.state)) or entry.id
    end
    return out
end

local function errorsPrinted(mock)
    local errors = {}
    for _, line in ipairs(mock.printed) do
        if line:find("Error in", 1, true) or line:find("missing for event", 1, true) then
            errors[#errors + 1] = line
        end
    end
    return errors
end

describe("combat companion", function()
    it("registers the pack's abilities with the SpellMap and disables unknown ones", function()
        local _, ns = boot({ spellIDs = { ["Battle Shout"] = 6673, Charge = 100, ["Heroic Strike"] = 284 } })
        local disabled = {}
        for _, item in ipairs(ns.Companion.compiled.disabled) do
            disabled[#disabled + 1] = item.id
        end
        table.sort(disabled)
        assert.are.same({ "execute", "interceptRange", "overpower" }, disabled)
        assert.are.same({ "Execute", "Intercept", "Overpower" }, ns.SpellMap:GetUnknown())
    end)

    describe("Battle Shout over the run 2 stream (U-01, degraded)", function()
        local mock, log

        before_each(function()
            local stream = Replay.load("run2_battle_shout")
            stream.start.data.spellIDs = IDS
            local _
            mock, _, log = boot(stream.start.data)
            Replay.run(mock, stream, { offset = 0 })
        end)

        it("shows nothing during the fight: the shout learned out of combat still has time left", function()
            for _, update in ipairs(log.alerts) do
                for _, entry in ipairs(update.list) do
                    assert.are_not.equal("battleShout", entry.id)
                end
            end
        end)

        it("wakes up by itself at 10s left out of combat with no target, then counts down", function()
            mock.data.combat.target = { exists = false, hostile = false }
            mock.advance(170.2 - mock.Now())
            assert.are.same({ "battleShout:expiring" }, ids(log.last))
            assert.is_true(log.last[1].remaining <= 10)
            mock.advance(5)
            assert.is_true(log.last[1].remaining <= 5)
        end)

        it("in combat with auras secret, expiring then dropped come from the tracked timer", function()
            mock.data.combat.target = { exists = true, hostile = true }
            mock.advance(172 - mock.Now())
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            mock.frame:Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
            assert.is_nil(mock.GetAura("player", "Battle Shout")) -- secret: the tracker is the only source
            assert.are.same({ "battleShout:expiring" }, ids(log.last))
            mock.data.combat.auras.player["Battle Shout"] = false -- the client would say so, but it is secret
            mock.advance(180.3 - mock.Now())
            assert.are.same({ "battleShout:dropped" }, ids(log.last))
            assert.are.equal("dropped", log.last[1].severity)
        end)

        it("an own recast in combat clears dropped (any rank, matched by name)", function()
            mock.data.combat.target = { exists = true, hostile = true }
            mock.data.spellNames = { [11549] = "Battle Shout" } -- rank 3: a different ID, the same name
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            mock.advance(181 - mock.Now())
            assert.are.same({ "battleShout:dropped" }, ids(log.last))
            mock.frame:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-x", 11549)
            assert.are.same({}, ids(log.last))
        end)
    end)

    it("with no duration learned since login (reload mid-fight), a recast hides dropped but never shows expiring",
        function()
            local data = { secrecy = "run2", inCombat = true, combat = baseCombat() }
            local mock, _, log = boot(data)
            assert.are.same({}, ids(log.last)) -- aura unreadable and nothing tracked yet: unknown, hidden
            mock.frame:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 6673)
            mock.advance(400)
            assert.are.same({}, ids(log.last))
        end)

    describe("reactive rules", function()
        it("Overpower and Execute appear when usable and never otherwise; cooldown time secret in combat", function()
            local mock, _, log = boot({ secrecy = "run2", combat = baseCombat() })
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            assert.are.same({ "battleShout:dropped" }, ids(log.last))
            mock.data.combat.usable[7384] = true
            mock.frame:Fire("SPELL_UPDATE_USABLE")
            assert.are.same({ "battleShout:dropped", "overpower" }, ids(log.last))
            mock.data.combat.cooldowns = { [7384] = 4 } -- cooling down: time secret, isActive true -> unknown
            mock.frame:Fire("SPELL_UPDATE_COOLDOWN")
            mock.advance(0.25) -- past the rule's throttle
            assert.are.same({ "battleShout:dropped" }, ids(log.last))
            mock.data.combat.usable[5308] = true
            mock.frame:Fire("SPELL_UPDATE_USABLE")
            assert.are.same({ "battleShout:dropped", "execute" }, ids(log.last))
        end)

        it("auto-attack badge after 1.5s in melee with auto-attack off, gone when it restarts (S-04)", function()
            local data = { secrecy = "run2", combat = baseCombat() }
            data.combat.auras.player["Battle Shout"] = { stacks = 0, duration = 120, expires = 1000 }
            local mock, _, log = boot(data)
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            mock.data.combat.autoAttacking = false
            mock.frame:Fire("PLAYER_LEAVE_COMBAT")
            mock.advance(1.2)
            assert.are.same({}, ids(log.last))
            mock.advance(0.4)
            assert.are.same({ "autoAttack" }, ids(log.last))
            mock.data.combat.autoAttacking = true
            mock.frame:Fire("PLAYER_ENTER_COMBAT")
            mock.advance(0.45) -- past the rule's 0.2s throttle on the next tick
            assert.are.same({}, ids(log.last))
        end)

        it("Charge badge out of combat in range, gone on entering combat (X-01)", function()
            local data = { combat = baseCombat() }
            data.combat.usable[100] = true
            data.combat.auras.player["Battle Shout"] = { stacks = 0, duration = 120, expires = 1000 }
            local mock, _, log = boot(data)
            assert.are.same({ "chargeRange" }, ids(log.last))
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            mock.advance(0.25) -- past the rule's throttle
            assert.are.same({}, ids(log.last))
        end)
    end)

    describe("suspension", function()
        it("an Encounter restriction suspends and clears everything; the Combat restriction does not", function()
            local mock, _, log = boot({ secrecy = "run2", combat = baseCombat() })
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            mock.frame:Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
            assert.are.same({ "battleShout:dropped" }, ids(log.last))
            assert.are.same({}, log.suspended)
            mock.data.restriction = { encounter = true }
            mock.frame:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
            assert.are.same({ true }, log.suspended)
            assert.are.same({}, ids(log.last))
            mock.advance(5)
            assert.are.same({}, ids(log.last)) -- the ticker does not bring anything back
            mock.data.restriction = {}
            mock.frame:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
            assert.are.same({ true, false }, log.suspended)
            assert.are.same({ "battleShout:dropped" }, ids(log.last))
        end)

        it("announces suspension at login when already in an encounter", function()
            local _, _, log = boot({ restriction = { encounter = true }, combat = baseCombat() })
            assert.are.same({ true }, log.suspended)
        end)

        it("/ww hud off (SetEnabled false) hides everything and is saved", function()
            local mock, ns, log = boot({ secrecy = "run2", inCombat = true, combat = baseCombat() })
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            ns.Companion:SetEnabled(false)
            assert.are.same({ false }, log.enabled)
            assert.are.same({}, ids(log.last))
            assert.is_false(ns.DB.GetCharacter().combat.enabled)
        end)
    end)

    describe("ticker", function()
        it("runs in combat and stops out of combat with no target", function()
            local data = { combat = baseCombat() }
            data.combat.target = { exists = false, hostile = false }
            data.combat.auras.player["Battle Shout"] = { stacks = 0, duration = 120, expires = 1e6 }
            local mock, ns = boot(data)
            local Companion = ns.Companion
            assert.is_falsy(Companion.ticking)
            assert.are.equal(1, mock.pendingTimers()) -- only the wake-up for the shout's 10s mark
            mock.data.inCombat = true
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            assert.is_true(Companion.ticking)
            assert.are.equal(2, mock.pendingTimers())
            mock.advance(1)
            assert.are.equal(2, mock.pendingTimers()) -- one chained tick, never more
            mock.data.inCombat = false
            mock.frame:Fire("PLAYER_REGEN_ENABLED")
            mock.advance(0.5)
            assert.is_false(Companion.ticking)
            assert.are.equal(1, mock.pendingTimers())
        end)

        it("averages under 0.5ms per evaluation (SPEC_V2 §13)", function()
            local mock, ns = boot({ secrecy = "run2", inCombat = true, combat = baseCombat() })
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            local runs = 2000
            local started = os.clock()
            for _ = 1, runs do
                ns.Companion:Evaluate()
            end
            local average = (os.clock() - started) / runs
            assert.is_true(average < 0.0005, string.format("%.3f ms", average * 1000))
        end)
    end)

    describe("secret mode (SPEC_V2 §13): every combat accessor returns nil", function()
        local STREAMS = { "run2_fight_parry", "run2_battle_shout", "run2_misses", "run2_target_parry",
            "assumed_avoidance" }

        for _, name in ipairs(STREAMS) do
            it("replays " .. name .. " with no error and nothing shown", function()
                local stream = Replay.load(name)
                stream.start.data.secrecy = "all"
                stream.start.data.combat = baseCombat()
                local mock, ns, log = boot(stream.start.data)
                local avoided = 0
                local listener = {}
                function listener:OnAvoidance()
                    avoided = avoided + 1
                end
                ns.Events:On("WW_AVOIDANCE", listener, "OnAvoidance")
                Replay.run(mock, stream, { offset = 0, tail = 30 })
                for _, update in ipairs(log.alerts) do
                    assert.are.equal(0, update.count)
                end
                assert.are.equal(0, avoided)
                assert.are.same({}, errorsPrinted(mock))
            end)
        end
    end)
end)
