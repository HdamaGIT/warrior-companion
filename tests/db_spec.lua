local H = dofile("tests/helpers/load_addon.lua")

describe("db", function()
    local ns, DB

    before_each(function()
        ns = H.newNs(H.pureFiles(), { adapter = H.mockAdapter.new() })
        DB = ns.DB
    end)

    describe("defaults", function()
        it("account defaults follow SPEC_V2 6 plus the planner settings (D-014, D-029)", function()
            local account = DB.GetAccountDefaults()
            assert.are.equal(2, account.schemaVersion)
            assert.is_false(account.settings.debug)
            assert.are.equal(5, account.settings.batchSize)
            assert.is_true(account.settings.hideMainInCombat)
            assert.is_nil(account.settings.hideInCombat)
            assert.are.equal("alerts", account.settings.window.tab)
            assert.are.equal(30, account.settings.planner.calibrationMinAttempts)
            assert.are.same({ optimal = 1.00, medium = 0.75, easy = 0.25, trivial = 0.00 },
                account.settings.planner.defaultOdds)
            assert.are.same({}, account.prices)
            for _, difficulty in ipairs({ "optimal", "medium", "easy", "trivial" }) do
                assert.are.same({ attempts = 0, gains = 0 }, account.calibration.byDifficulty[difficulty])
            end
        end)

        it("character defaults follow SPEC_V2 6 and keep the placeholder weights under advisor", function()
            local character = DB.GetCharacterDefaults()
            assert.are.equal(2, character.schemaVersion)
            assert.are.equal("dps", character.advisor.activeProfile)
            local dps, tank = character.advisor.profiles.dps, character.advisor.profiles.tank
            assert.are.equal("DPS", dps.label)
            assert.are.equal("Tank", tank.label)
            assert.are.equal(1.00, dps.weights.str)
            assert.are.equal(3.00, dps.weights.weaponDps)
            assert.are.equal(0.00, dps.weights.defense)
            assert.are.equal(1.00, tank.weights.sta)
            assert.are.equal(1.20, tank.weights.defense)
            assert.are.equal(0.05, tank.weights.armor)
            assert.are.equal(0.60, character.readiness.durabilityAmber)
            assert.are.equal(0.30, character.readiness.durabilityRed)
            assert.are.same({ dps = "DPS", tank = "Tank" }, character.readiness.expectedSet)
            assert.are.same({}, character.craftLog)
            assert.are.same({}, character.professions)
            assert.are.same({ bags = {}, bank = {} }, character.inventory)
        end)

        it("character defaults include the combat, announce and gear sections", function()
            local character = DB.GetCharacterDefaults()
            assert.is_true(character.combat.enabled)
            assert.is_true(character.combat.hud.locked)
            assert.are.equal(6, character.combat.hud.alertStrip.maxIcons)
            assert.are.equal(1.5, character.combat.hud.bigAlert.scale)
            assert.are.same({ parry = true, dodge = true, block = true, crit = false },
                character.combat.hud.combatText.show)
            assert.are.equal("RAID_WARNING", character.combat.alertStyle.dropped.sound)
            assert.is_true(character.combat.alertStyle.dropped.flash)
            assert.are.same({}, character.combat.ruleOverrides)
            assert.are.same({}, character.combat.spellOverrides)
            assert.is_true(character.announce.enabled)
            assert.are.same({ default = 2.0, avoidance = 5.0 }, character.announce.throttle)
            assert.are.same({}, character.announce.events)
            assert.are.same({ sets = {}, weaponSwaps = {}, macros = {} }, character.gear)
        end)

        it("returns independent copies on every call", function()
            local first = DB.GetAccountDefaults()
            first.settings.batchSize = 99
            assert.are.equal(5, DB.GetAccountDefaults().settings.batchSize)
        end)
    end)

    describe("Prepare", function()
        local function prepareAccount(raw, migrations, now)
            return DB.Prepare(raw, DB.GetAccountDefaults(), migrations or {}, now or 100)
        end

        it("builds defaults on first run (nil or empty table)", function()
            local fresh, freshStatus = prepareAccount(nil)
            assert.are.same(DB.GetAccountDefaults(), fresh)
            assert.are.equal("new", freshStatus.state)
            local _, emptyStatus = prepareAccount({})
            assert.are.equal("new", emptyStatus.state)
        end)

        it("keeps user values and fills in only what is missing", function()
            local raw = dofile("tests/fixtures/saved_account.lua")
            raw.schemaVersion = DB.SCHEMA_VERSION
            local db, status = prepareAccount(raw)
            assert.are.equal("ok", status.state)
            assert.are.equal(raw, db)
            assert.is_true(db.settings.debug)
            assert.are.equal(9, db.settings.batchSize)
            assert.are.equal("TOPLEFT", db.settings.window.point)
            assert.are.equal(-20, db.settings.window.y)
            assert.are.equal("alerts", db.settings.window.tab)
            assert.is_true(db.settings.hideMainInCombat)
            assert.are.equal(30, db.settings.planner.calibrationMinAttempts)
            assert.are.equal(1500, db.prices[12345].value)
            assert.are.equal(0, db.calibration.byDifficulty.easy.attempts)
        end)

        describe("with a newer schema in the code", function()
            local savedVersion, nextVersion

            before_each(function()
                savedVersion = DB.SCHEMA_VERSION
                nextVersion = savedVersion + 1
                DB.SCHEMA_VERSION = nextVersion
            end)

            after_each(function()
                DB.SCHEMA_VERSION = savedVersion
            end)

            it("migrates a copy, merges defaults and leaves the original untouched", function()
                local raw = { schemaVersion = savedVersion, settings = { batchSize = 7 } }
                local migrations = {
                    {
                        to = nextVersion,
                        fn = function(db)
                            db.settings.batchSize = db.settings.batchSize * 2
                        end,
                    },
                }
                local db, status = prepareAccount(raw, migrations)
                assert.are.equal("migrated", status.state)
                assert.are.equal(1, status.applied)
                assert.are.equal(nextVersion, db.schemaVersion)
                assert.are.equal(14, db.settings.batchSize)
                assert.is_true(db.settings.hideMainInCombat)
                assert.are.equal(savedVersion, raw.schemaVersion)
                assert.are.equal(7, raw.settings.batchSize)
            end)

            it("backs up and reinitialises when a migration fails", function()
                local raw = { schemaVersion = savedVersion, settings = { batchSize = 7 } }
                local migrations = {
                    {
                        to = nextVersion,
                        fn = function(db)
                            db.settings.batchSize = 0
                            error("bad migration")
                        end,
                    },
                }
                local db, status = prepareAccount(raw, migrations, 555)
                assert.are.equal("backup", status.state)
                assert.are.equal("migration_failed", status.reason)
                assert.are.equal(raw, db._backup.data)
                assert.are.equal(7, raw.settings.batchSize)
                assert.are.equal(savedVersion, db._backup.schemaVersion)
                assert.are.equal(555, db._backup.at)
                assert.are.equal(5, db.settings.batchSize)
            end)
        end)

        it("backs up a database from a future version inside the table (D-012)", function()
            local raw = { schemaVersion = 99, settings = { debug = true }, keep = "me" }
            local db, status = prepareAccount(raw, nil, 777)
            assert.are.equal("backup", status.state)
            assert.are.equal("future", status.reason)
            assert.are.equal(raw, db._backup.data)
            assert.are.equal("me", db._backup.data.keep)
            assert.are.equal(99, db._backup.schemaVersion)
            assert.are.equal(777, db._backup.at)
            assert.are.equal("future", db._backup.reason)
            assert.are.equal(DB.SCHEMA_VERSION, db.schemaVersion)
            assert.is_false(db.settings.debug)
            assert.is_nil(rawget(_G, "WarriorWorkshopDB_backup"))
        end)

        it("backs up corrupt data of any shape", function()
            local samples = {
                "garbage",
                42,
                true,
                { settings = { debug = true } },
                { schemaVersion = "1" },
            }
            for _, raw in ipairs(samples) do
                local db, status = prepareAccount(raw)
                assert.are.equal("backup", status.state)
                assert.are.equal("corrupt", status.reason)
                assert.are.equal(raw, db._backup.data)
                assert.are.equal(DB.SCHEMA_VERSION, db.schemaVersion)
            end
        end)
    end)

    describe("schema v1 -> v2 (D-029 d)", function()
        it("migrates a v1 account: hideInCombat becomes hideMainInCombat, user values kept", function()
            local raw = dofile("tests/fixtures/saved_account.lua")
            raw.settings.hideInCombat = false
            local account, _, report = DB.Init(raw, nil, 10)
            assert.are.equal("migrated", report.account.state)
            assert.are.equal(2, account.schemaVersion)
            assert.is_false(account.settings.hideMainInCombat)
            assert.is_nil(account.settings.hideInCombat)
            assert.are.equal(9, account.settings.batchSize)
            assert.are.equal("TOPLEFT", account.settings.window.point)
            assert.are.equal("alerts", account.settings.window.tab)
            assert.are.equal(1500, account.prices[12345].value)
            assert.is_nil(account._backup)
        end)

        it("migrates a v1 character: gear weights move to advisor, gear is rebuilt for sets", function()
            local _, character, report = DB.Init(nil, dofile("tests/fixtures/saved_character_v1.lua"), 10)
            assert.are.equal("migrated", report.character.state)
            assert.are.equal(2, character.schemaVersion)
            assert.are.equal("tank", character.advisor.activeProfile)
            assert.are.equal(2.0, character.advisor.profiles.tank.weights.sta)
            assert.are.equal(1.5, character.advisor.profiles.dps.weights.str)
            assert.are.equal(1.20, character.advisor.profiles.tank.weights.defense) -- default filled in
            assert.are.same({ sets = {}, weaponSwaps = {}, macros = {} }, character.gear)
            assert.are.equal("Hugh", character.meta.name)
            assert.are.equal(20, character.inventory.bags[2589])
            assert.are.equal("learn at 35", character.targets.example.note)
            assert.are.equal(0.5, character.readiness.durabilityAmber)
            assert.is_true(character.combat.enabled)
            assert.is_true(character.announce.enabled)
        end)

        it("is a no-op on a second load", function()
            local account, character = DB.Init(dofile("tests/fixtures/saved_account.lua"),
                dofile("tests/fixtures/saved_character_v1.lua"), 10)
            local account2, character2, report = DB.Init(account, character, 20)
            assert.are.equal("ok", report.account.state)
            assert.are.equal("ok", report.character.state)
            assert.are.equal("tank", character2.advisor.activeProfile)
            assert.are.equal(9, account2.settings.batchSize)
        end)
    end)

    describe("Init and accessors", function()
        it("has no data before Init", function()
            assert.is_nil(DB.GetAccount())
            assert.is_nil(DB.GetCharacter())
            assert.is_nil(DB.GetSettings())
            assert.has_no.errors(function()
                DB.UpdateMeta({ name = "X" })
                DB.StampLastSeen(5)
            end)
        end)

        it("prepares both tables and reports their state", function()
            local account, character, report = DB.Init(nil, nil, 10)
            assert.are.equal(account, DB.GetAccount())
            assert.are.equal(character, DB.GetCharacter())
            assert.are.equal(account.settings, DB.GetSettings())
            assert.are.equal("new", report.account.state)
            assert.are.equal("new", report.character.state)
        end)

        it("reports each table separately", function()
            local _, character, report = DB.Init(nil, { schemaVersion = 50 }, 10)
            assert.are.equal("new", report.account.state)
            assert.are.equal("backup", report.character.state)
            assert.are.equal(50, character._backup.schemaVersion)
        end)

        it("persists across a simulated reload", function()
            local account, character = DB.Init(nil, nil, 10)
            account.settings.batchSize = 12
            character.targets.example = { name = "Thing" }
            local account2, character2, report = DB.Init(account, character, 20)
            assert.are.equal("ok", report.account.state)
            assert.are.equal(12, account2.settings.batchSize)
            assert.are.equal("Thing", character2.targets.example.name)
        end)

        it("copies player identity into meta and ignores nil", function()
            DB.Init(nil, nil, 10)
            DB.UpdateMeta({ name = "Hugh", realm = "Realm", classFile = "WARRIOR", level = 80 })
            DB.UpdateMeta(nil)
            assert.are.same({ name = "Hugh", realm = "Realm", classFile = "WARRIOR", level = 80 },
                DB.GetCharacter().meta)
        end)

        it("stamps lastSeen", function()
            DB.Init(nil, nil, 10)
            DB.StampLastSeen(1234)
            assert.are.equal(1234, DB.GetCharacter().meta.lastSeen)
        end)
    end)
end)
