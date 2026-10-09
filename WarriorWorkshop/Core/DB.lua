local addonName, ns = ...

-- Saved-variables defaults, validation, migration and accessors. The raw tables arrive as arguments and
-- results are returned, so this file touches no globals; Core/Init.lua assigns the SavedVariables.
local Util = ns.Util
local Migrations = ns.Migrations

local DB = {}
ns.DB = DB

DB.SCHEMA_VERSION = 1

-- Placeholder weights (SPEC 7.6). Not shipped as truth: the user edits them.
local function dpsWeights()
    return {
        str = 1.00, agi = 0.70, sta = 0.10, ap = 0.50, crit = 0.80, hit = 1.00, haste = 0.60, expertise = 0.80,
        armor = 0.00, defense = 0.00, dodge = 0.00, parry = 0.00, block = 0.00, blockValue = 0.00,
        weaponDps = 3.00,
    }
end

local function tankWeights()
    return {
        str = 0.50, agi = 0.60, sta = 1.00, ap = 0.20, crit = 0.20, hit = 0.40, haste = 0.20, expertise = 0.50,
        armor = 0.05, defense = 1.20, dodge = 1.00, parry = 0.90, block = 0.60, blockValue = 0.30,
        weaponDps = 1.00,
    }
end

--- Returns a fresh copy of the account-wide defaults (SPEC 6, plus settings.planner per D-013).
-- @return table
function DB.GetAccountDefaults()
    return {
        schemaVersion = DB.SCHEMA_VERSION,
        settings = {
            debug = false,
            batchSize = 5,
            hideInCombat = true,
            window = { point = "CENTER", x = 0, y = 0, w = 640, h = 480, tab = "planner" },
            planner = {
                calibrationMinAttempts = 30,
                defaultOdds = { optimal = 1.00, medium = 0.75, easy = 0.25, trivial = 0.00 },
            },
        },
        prices = {},
        calibration = {
            byDifficulty = {
                optimal = { attempts = 0, gains = 0 },
                medium = { attempts = 0, gains = 0 },
                easy = { attempts = 0, gains = 0 },
                trivial = { attempts = 0, gains = 0 },
            },
        },
    }
end

--- Returns a fresh copy of the per-character defaults (SPEC 6).
-- @return table
function DB.GetCharacterDefaults()
    return {
        schemaVersion = DB.SCHEMA_VERSION,
        meta = {},
        inventory = { bags = {}, bank = {} },
        professions = {},
        targets = {},
        craftLog = {},
        colourObservations = {},
        gear = {
            activeProfile = "dps",
            profiles = {
                dps = { label = "DPS", weights = dpsWeights() },
                tank = { label = "Tank", weights = tankWeights() },
            },
        },
        readiness = {
            consumables = {},
            durabilityAmber = 0.60,
            durabilityRed = 0.30,
            expectedSet = { dps = "DPS", tank = "Tank" },
        },
    }
end

local function reinitialise(raw, defaults, reason, now, previousVersion)
    local db = Util.DeepCopy(defaults)
    -- D-011: the backup lives inside the saved-variables table, so it persists and adds no global.
    db._backup = { at = now, reason = reason, schemaVersion = previousVersion, data = raw }
    return db, { state = "backup", reason = reason }
end

--- Validates, migrates and completes one raw saved-variables table. Pure apart from mutating raw when no
-- migration is needed (migrations run on a copy so a failure cannot half-migrate the original).
-- User values are never overwritten by defaults. Unusable data is kept in db._backup and replaced by defaults.
-- @param raw any the value read from SavedVariables (nil on first run)
-- @param defaults table fresh defaults for this scope (not modified)
-- @param migrations array migration list for this scope
-- @param now number timestamp stored in a backup
-- @return db table ready for use
-- @return status { state = "new"|"ok"|"migrated"|"backup", reason = "corrupt"|"future"|"migration_failed"|nil,
--   applied = number|nil }
function DB.Prepare(raw, defaults, migrations, now)
    if raw == nil or (type(raw) == "table" and next(raw) == nil) then
        return Util.DeepCopy(defaults), { state = "new" }
    end
    if type(raw) ~= "table" or type(raw.schemaVersion) ~= "number" then
        return reinitialise(raw, defaults, "corrupt", now, nil)
    end
    if raw.schemaVersion > DB.SCHEMA_VERSION then
        return reinitialise(raw, defaults, "future", now, raw.schemaVersion)
    end
    local db = raw
    local status = { state = "ok", applied = 0 }
    if raw.schemaVersion < DB.SCHEMA_VERSION then
        db = Util.DeepCopy(raw)
        local ok, applied = Migrations.Apply(db, migrations, DB.SCHEMA_VERSION)
        if not ok then
            return reinitialise(raw, defaults, "migration_failed", now, raw.schemaVersion)
        end
        status = { state = "migrated", applied = applied }
    end
    Util.MergeDefaults(db, defaults)
    return db, status
end

--- Prepares both saved-variables tables and keeps them for the accessors below.
-- @param accountRaw any raw WarriorWorkshopDB
-- @param characterRaw any raw WarriorWorkshopCharDB
-- @param now number timestamp for backups
-- @return account table
-- @return character table
-- @return report { account = status, character = status } (see DB.Prepare)
function DB.Init(accountRaw, characterRaw, now)
    local account, accountStatus = DB.Prepare(accountRaw, DB.GetAccountDefaults(), Migrations.ACCOUNT, now)
    local character, characterStatus =
        DB.Prepare(characterRaw, DB.GetCharacterDefaults(), Migrations.CHARACTER, now)
    DB.account = account
    DB.character = character
    return account, character, { account = accountStatus, character = characterStatus }
end

--- Returns the account-wide table, or nil before DB.Init.
-- @return table|nil
function DB.GetAccount()
    return DB.account
end

--- Returns the current character's table, or nil before DB.Init.
-- @return table|nil
function DB.GetCharacter()
    return DB.character
end

--- Returns account settings, or nil before DB.Init.
-- @return table|nil
function DB.GetSettings()
    return DB.account and DB.account.settings
end

--- Copies identity fields into character.meta.
-- @param info table|nil { name, realm, classFile, level } from Adapter.GetPlayerMeta; nil is ignored
-- Side effects: writes character.meta.
function DB.UpdateMeta(info)
    local character = DB.character
    if not character or type(info) ~= "table" then
        return
    end
    local meta = character.meta
    meta.name = info.name
    meta.realm = info.realm
    meta.classFile = info.classFile
    meta.level = info.level
end

--- Stamps character.meta.lastSeen.
-- @param now number timestamp
-- Side effects: writes character.meta.lastSeen.
function DB.StampLastSeen(now)
    if DB.character then
        DB.character.meta.lastSeen = now
    end
end
