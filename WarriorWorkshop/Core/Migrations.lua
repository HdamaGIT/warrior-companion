local addonName, ns = ...

-- Schema migrations. Schema v1 is the initial schema, created from defaults, so both lists start empty.
-- To change a saved-variables shape: bump DB.SCHEMA_VERSION, append { to = n, fn = function(db) ... end }
-- to the right list, and add a test in tests/migrations_spec.lua (CLAUDE.md).
local Migrations = {
    ACCOUNT = {},   -- WarriorWorkshopDB
    CHARACTER = {}, -- WarriorWorkshopCharDB
}
ns.Migrations = Migrations

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
