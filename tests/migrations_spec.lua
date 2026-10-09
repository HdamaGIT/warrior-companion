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

    it("starts with empty lists because schema v1 is created from defaults", function()
        assert.are.same({}, Migrations.ACCOUNT)
        assert.are.same({}, Migrations.CHARACTER)
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
