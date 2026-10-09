local addonName, ns = ...

-- Schema migrations. Schema v1 is the initial schema, created from defaults.
-- To change a saved-variables shape: bump DB.SCHEMA_VERSION, append { to = n, fn = function(db) ... end }
-- to the right list, and add a test in tests/migrations_spec.lua (CLAUDE.md). A migration only moves or renames
-- user data; DB.Prepare fills in new defaults afterwards. Never drop user data.
local Migrations = {
    ACCOUNT = {},   -- WarriorWorkshopDB
    CHARACTER = {}, -- WarriorWorkshopCharDB
}
ns.Migrations = Migrations

--- Account v1 -> v2 (SPEC_V2 §6, D-029 d): settings.hideInCombat becomes settings.hideMainInCombat.
-- The saved window tab is left alone; the UI falls back to its default when a tab does not exist.
-- @param db table account database at v1; modified in place
function Migrations.AccountV2(db)
    local settings = db.settings
    if type(settings) ~= "table" then
        return
    end
    if settings.hideInCombat ~= nil then
        if settings.hideMainInCombat == nil then
            settings.hideMainInCombat = settings.hideInCombat
        end
        settings.hideInCombat = nil
    end
end

--- Character v1 -> v2 (SPEC_V2 §6, D-029 d): the v1 `gear` table (stat-weight profiles) moves to `advisor`;
-- `gear` is then rebuilt from defaults for sets, weapon swaps and macros.
-- @param db table character database at v1; modified in place
function Migrations.CharacterV2(db)
    local gear = db.gear
    if type(gear) ~= "table" or (gear.profiles == nil and gear.activeProfile == nil) then
        return
    end
    if db.advisor == nil then
        db.advisor = gear
    else
        -- Both exist (should not happen): keep the old table rather than drop it.
        db.advisor.legacyGear = gear
    end
    db.gear = nil
end

table.insert(Migrations.ACCOUNT, { to = 2, fn = Migrations.AccountV2 })
table.insert(Migrations.CHARACTER, { to = 2, fn = Migrations.CharacterV2 })

--- Applies, in ascending order, every migration with `to` greater than db.schemaVersion (and not above
-- targetVersion), then sets db.schemaVersion to targetVersion. Pure apart from mutating db.
-- @param db table with a numeric schemaVersion; modified in place
-- @param migrations array of { to = number, fn = function(db) }
-- @param targetVersion number
-- @return true, appliedCount on success
-- @return false, errorMessage, appliedCount if db is invalid or a migration errors (db may be part-migrated)
function Migrations.Apply(db, migrations, targetVersion)
    if type(db) ~= "table" or type(db.schemaVersion) ~= "number" then
        return false, "invalid database", 0
    end
    local ordered = {}
    for index, migration in ipairs(migrations) do
        ordered[index] = migration
    end
    table.sort(ordered, function(first, second)
        return first.to < second.to
    end)
    local applied = 0
    for _, migration in ipairs(ordered) do
        if migration.to > db.schemaVersion and migration.to <= targetVersion then
            local ok, err = pcall(migration.fn, db)
            if not ok then
                return false, tostring(err), applied
            end
            db.schemaVersion = migration.to
            applied = applied + 1
        end
    end
    if db.schemaVersion < targetVersion then
        db.schemaVersion = targetVersion
    end
    return true, applied
end
