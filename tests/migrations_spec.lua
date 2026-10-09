local H = dofile("tests/helpers/load_addon.lua")

describe("migrations", function()
    local Migrations
    local order

    local function step(version)
        return {
            to = version,
            fn = function(db)
                order[#order + 1] = version
                db["v" .. version] = true
            end,
        }
    end

    before_each(function()
        Migrations = H.newNs({ "Locale/enUS.lua", "Core/Util.lua", "Core/Migrations.lua" }).Migrations
        order = {}
    end)

    it("has exactly the v2 migration in each list", function()
        assert.are.equal(1, #Migrations.ACCOUNT)
        assert.are.equal(2, Migrations.ACCOUNT[1].to)
        assert.are.equal(1, #Migrations.CHARACTER)
        assert.are.equal(2, Migrations.CHARACTER[1].to)
    end)

    describe("AccountV2", function()
        it("renames hideInCombat to hideMainInCombat, keeping the value", function()
            local db = { schemaVersion = 1, settings = { hideInCombat = false, batchSize = 9 } }
            Migrations.AccountV2(db)
            assert.is_false(db.settings.hideMainInCombat)
            assert.is_nil(db.settings.hideInCombat)
            assert.are.equal(9, db.settings.batchSize)
        end)

        it("does not overwrite an existing hideMainInCombat", function()
            local db = { settings = { hideInCombat = false, hideMainInCombat = true } }
            Migrations.AccountV2(db)
            assert.is_true(db.settings.hideMainInCombat)
            assert.is_nil(db.settings.hideInCombat)
        end)

        it("tolerates missing settings", function()
            assert.has_no.errors(function()
                Migrations.AccountV2({})
                Migrations.AccountV2({ settings = "junk" })
            end)
        end)
    end)

    describe("CharacterV2", function()
        it("moves the v1 gear profiles to advisor", function()
            local profiles = { dps = { weights = { str = 2 } } }
            local db = { gear = { activeProfile = "tank", profiles = profiles } }
            Migrations.CharacterV2(db)
            assert.are.equal("tank", db.advisor.activeProfile)
            assert.are.equal(profiles, db.advisor.profiles)
            assert.is_nil(db.gear)
        end)

        it("keeps old gear under advisor.legacyGear if advisor already exists", function()
            local old = { activeProfile = "dps", profiles = {} }
            local db = { gear = old, advisor = { activeProfile = "tank" } }
            Migrations.CharacterV2(db)
            assert.are.equal(old, db.advisor.legacyGear)
            assert.are.equal("tank", db.advisor.activeProfile)
        end)

        it("leaves a v2-shaped gear table and missing gear alone", function()
            local sets = { sets = { [1] = { setID = 3 } } }
            local db = { gear = sets }
            Migrations.CharacterV2(db)
            assert.are.equal(sets, db.gear)
            assert.is_nil(db.advisor)
            assert.has_no.errors(function()
                Migrations.CharacterV2({})
            end)
        end)
    end)

    it("applies every migration above the current version, in order", function()
        local db = { schemaVersion = 1 }
        local ok, applied = Migrations.Apply(db, { step(2), step(3), step(4) }, 4)
        assert.is_true(ok)
        assert.are.equal(3, applied)
        assert.are.same({ 2, 3, 4 }, order)
        assert.are.equal(4, db.schemaVersion)
        assert.is_true(db.v2 and db.v3 and db.v4)
    end)

    it("sorts migrations that were listed out of order", function()
        local db = { schemaVersion = 1 }
        Migrations.Apply(db, { step(3), step(2) }, 3)
        assert.are.same({ 2, 3 }, order)
    end)

    it("skips migrations that were already applied", function()
        local db = { schemaVersion = 2 }
        local ok, applied = Migrations.Apply(db, { step(2), step(3) }, 3)
        assert.is_true(ok)
        assert.are.equal(1, applied)
        assert.are.same({ 3 }, order)
        assert.is_nil(db.v2)
    end)

    it("does nothing when already at the target version", function()
        local db = { schemaVersion = 3 }
        local ok, applied = Migrations.Apply(db, { step(2), step(3) }, 3)
        assert.is_true(ok)
        assert.are.equal(0, applied)
        assert.are.same({}, order)
    end)

    it("does not apply migrations beyond the target", function()
        local db = { schemaVersion = 1 }
        Migrations.Apply(db, { step(2), step(3) }, 2)
        assert.are.same({ 2 }, order)
        assert.are.equal(2, db.schemaVersion)
    end)

    it("sets the target version even when no migration is listed", function()
        local db = { schemaVersion = 1 }
        assert.is_true(Migrations.Apply(db, {}, 2))
        assert.are.equal(2, db.schemaVersion)
    end)

    it("reports a failing migration and keeps the version of the last good step", function()
        local db = { schemaVersion = 1 }
        local failing = {
            to = 3,
            fn = function()
                error("boom")
            end,
        }
        local ok, message, applied = Migrations.Apply(db, { step(2), failing, step(4) }, 4)
        assert.is_false(ok)
        assert.is_truthy(string.find(message, "boom", 1, true))
        assert.are.equal(1, applied)
        assert.are.equal(2, db.schemaVersion)
        assert.are.same({ 2 }, order)
    end)

    it("rejects a database without a numeric schemaVersion", function()
        assert.is_false((Migrations.Apply({}, {}, 1)))
        assert.is_false((Migrations.Apply({ schemaVersion = "1" }, {}, 1)))
        assert.is_false((Migrations.Apply("junk", {}, 1)))
    end)
end)
