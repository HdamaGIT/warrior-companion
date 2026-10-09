local H = dofile("tests/helpers/load_addon.lua")

local ADDON = "WarriorWorkshop"

describe("context", function()
    local mock, ns, Context, changes

    --- Boots the Core against the mock adapter, runs ADDON_LOADED and PLAYER_LOGIN, and records
    -- WW_CONTEXT_CHANGED payloads.
    local function boot(data)
        mock = H.mockAdapter.new(data)
        ns = H.bootSandbox({ adapter = mock })
        Context = ns.Context
        changes = {}
        local listener = {}
        function listener:OnChange(newState, oldState)
            changes[#changes + 1] = { new = newState, old = oldState }
        end
        ns.Events:On("WW_CONTEXT_CHANGED", listener, "OnChange")
        mock.frame:Fire("ADDON_LOADED", ADDON)
        mock.frame:Fire("PLAYER_LOGIN")
    end

    describe("Compute", function()
        before_each(function()
            boot()
        end)

        it("is restricted only by an encounter, Mythic+ or a direct signal (D-033)", function()
            local base = { zone = "instance", group = "party", inCombat = true, dead = false }
            assert.is_false(Context.Compute(base).restricted)
            for _, flag in ipairs({ "encounter", "challengeMode", "directRestriction" }) do
                local flags = { zone = "instance", group = "party", inCombat = true, dead = false }
                flags[flag] = true
                assert.is_true(Context.Compute(flags).restricted, flag)
            end
        end)

        it("normalises unexpected values", function()
            local state = Context.Compute({ zone = "scenario", group = "weird" })
            assert.are.same({ zone = "openWorld", restricted = false, inCombat = false, dead = false, group = "solo" },
                state)
        end)
    end)

    describe("events", function()
        it("publishes the initial state at login", function()
            boot({ zoneKind = "instance", groupKind = "party" })
            assert.are.equal(1, #changes)
            assert.are.same({ zone = "instance", restricted = false, inCombat = false, dead = false, group = "party" },
                changes[1].new)
            assert.is_nil(changes[1].old)
            assert.are.same(changes[1].new, Context:Get())
        end)

        it("seeds combat and an encounter already in progress after /reload", function()
            boot({ inCombat = true, encounter = true })
            local state = Context:Get()
            assert.is_true(state.inCombat)
            assert.is_true(state.restricted)
            assert.is_true(Context:IsRestricted())
        end)

        it("tracks combat from PLAYER_REGEN_DISABLED/ENABLED", function()
            boot()
            mock.frame:Fire("PLAYER_REGEN_DISABLED")
            assert.is_true(Context:Get().inCombat)
            mock.frame:Fire("PLAYER_REGEN_ENABLED")
            assert.is_false(Context:Get().inCombat)
            assert.are.equal(3, #changes)
            assert.is_true(changes[3].old.inCombat)
        end)

        it("is restricted between ENCOUNTER_START and ENCOUNTER_END, without reading the arguments", function()
            boot()
            mock.frame:Fire("ENCOUNTER_START", {}, {}, {}, {}) -- arguments are opaque to Context
            assert.is_true(Context:IsRestricted())
            mock.frame:Fire("ENCOUNTER_END")
            assert.is_false(Context:IsRestricted())
        end)

        it("is restricted during a Mythic+ run", function()
            boot()
            mock.frame:Fire("CHALLENGE_MODE_START")
            assert.is_true(Context:IsRestricted())
            mock.frame:Fire("CHALLENGE_MODE_COMPLETED")
            assert.is_false(Context:IsRestricted())
        end)

        it("clears a stale encounter flag on zone change by asking the Adapter", function()
            boot()
            mock.frame:Fire("ENCOUNTER_START")
            mock.data.zoneKind = "openWorld"
            mock.frame:Fire("ZONE_CHANGED_NEW_AREA")
            assert.is_false(Context:IsRestricted())
        end)

        it("tracks death, and asks on PLAYER_ALIVE because releasing makes you a ghost", function()
            boot()
            mock.frame:Fire("PLAYER_DEAD")
            assert.is_true(Context:Get().dead)
            mock.data.dead = true -- released: still a ghost
            mock.frame:Fire("PLAYER_ALIVE")
            assert.is_true(Context:Get().dead)
            mock.data.dead = false
            mock.frame:Fire("PLAYER_UNGHOST")
            assert.is_false(Context:Get().dead)
        end)

        it("updates the group on GROUP_ROSTER_UPDATE", function()
            boot()
            mock.data.groupKind = "raid"
            mock.frame:Fire("GROUP_ROSTER_UPDATE")
            assert.are.equal("raid", Context:Get().group)
        end)

        it("fires only when something changed", function()
            boot()
            mock.frame:Fire("GROUP_ROSTER_UPDATE")
            mock.frame:Fire("PLAYER_REGEN_ENABLED")
            assert.are.equal(1, #changes)
        end)

        it("keeps the previous value when the Adapter cannot answer", function()
            boot({ groupKind = "party" })
            mock.GetGroupKind = function()
                return nil
            end
            mock.frame:Fire("GROUP_ROSTER_UPDATE")
            assert.are.equal("party", Context:Get().group)
        end)

        it("counts secrets without suspending anything (D-033)", function()
            boot()
            Context:NoteSecret()
            Context:NoteSecret()
            assert.are.equal(2, Context.secretHits)
            assert.is_false(Context:IsRestricted())
        end)

        it("returns copies, so callers cannot change the published state", function()
            boot()
            local state = Context:Get()
            state.restricted = true
            assert.is_false(Context:IsRestricted())
        end)
    end)
end)
