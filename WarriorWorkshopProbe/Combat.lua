local addonName, ns = ...

-- M3 combat probes (SPEC_V2 §12.2, D-032).
--   /wwprobe combat : 0.25s sampler, aggregated per field and context (V-11..V-15, V-17, V-18, V-23, V-32)
--   recorder        : CLEU (capped, V-16), UNIT_COMBAT fallback, nameplates (V-19), restriction candidates
--                     (V-21), and how often the M5 trigger events fire.
-- Every combat value is classified before use (D-007). Only values confirmed non-secret are stored or compared.

local out, resolve, classify, pack = ns.out, ns.resolve, ns.classify, ns.pack

local SAMPLE_INTERVAL = 0.25
local EXAMPLE_CAP = 5
local ERROR_CAP = 3
local RETURN_CAP = 10
local TRANSITION_CAP = 500
local CLEU_SESSION_CAP = 300
local CLEU_MISS_SESSION_CAP = 150
local CLEU_STORE_CAP = 1500
local CLEU_ARG_CAP = 24
local NAMEPLATE_SESSION_CAP = 60

-- Aura data fields worth keeping (the full table has ~20 fields per aura).
local AURA_FIELDS = {
    applications = true, duration = true, expirationTime = true, sourceUnit = true, spellId = true, name = true,
    isFromPlayerOrPlayerPet = true, auraInstanceID = true, isHarmful = true, timeMod = true,
}

---------------------------------------------------------------------------
-- Sampler field list
---------------------------------------------------------------------------

-- { key, apiPath, args..., transitions = bool, subfields = table|nil }
local FIELDS = {
    { "targetHealth", "UnitHealth", "target" },
    { "targetHealthMax", "UnitHealthMax", "target" },
    { "targetHealthPercent", "UnitHealthPercent", "target" },
    { "playerHealth", "UnitHealth", "player" },
    { "rage", "UnitPower", "player", 1 },
    { "rageMax", "UnitPowerMax", "player", 1 },
    { "targetCanAttack", "UnitCanAttack", "player", "target" },
    { "targetLevel", "UnitLevel", "target" },
    { "targetClassification", "UnitClassification", "target" },
    { "targetReaction", "UnitReaction", "target", "player" },
    { "threatSituation", "UnitThreatSituation", "player", "target" },
    { "targetCasting", "UnitCastingInfo", "target" },
    { "targetChannel", "UnitChannelInfo", "target" },
    { "stance", "GetShapeshiftForm" },
    { "stanceID", "GetShapeshiftFormID" },
    { "encounterInProgress", "IsEncounterInProgress" },
    { "challengeModeActive", "C_ChallengeMode.IsChallengeModeActive" },
    { "gcd", "C_Spell.GetSpellCooldown", 61304 },
    { "current:6603", "C_Spell.IsCurrentSpell", 6603 },
}

local function addFields(prefix, path, names, extra)
    for _, name in ipairs(names) do
        local field = { prefix .. name, path, name }
        for key, value in pairs(extra or {}) do
            if type(key) == "number" then
                field[#field + 1] = value
            else
                field[key] = value
            end
        end
        FIELDS[#FIELDS + 1] = field
    end
end

addFields("usable:", "C_Spell.IsSpellUsable", { "Overpower", "Revenge", "Execute" }, { transitions = true })
addFields("usable:", "C_Spell.IsSpellUsable",
    { "Pummel", "Shield Bash", "Charge", "Intercept", "Victory Rush", "Heroic Strike" })
addFields("cd:", "C_Spell.GetSpellCooldown", { "Charge", "Pummel", "Shield Bash", "Taunt", "Overpower", "Revenge",
    "Mortal Strike", "Bloodthirst", "Shield Slam", "Whirlwind", "Shield Wall", "Last Stand", "Bloodrage" })
addFields("range:", "C_Spell.IsSpellInRange", { "Charge", "Intercept", "Pummel", "Heroic Strike", "Taunt" },
    { "target" })
addFields("current:", "C_Spell.IsCurrentSpell", { "Auto Attack", "Heroic Strike", "Cleave" })

-- C_Spell.GetSpellInfo(name) + aura lookups use the game's spellings; misses are findings.
for _, name in ipairs({ "Battle Shout", "Bloodrage", "Berserker Rage", "Shield Wall", "Last Stand",
    "Shield Block" }) do
    FIELDS[#FIELDS + 1] = { "aura:player:" .. name, "C_UnitAuras.GetAuraDataBySpellName", "player", name,
        "HELPFUL", subfields = AURA_FIELDS }
end
for _, name in ipairs({ "Sunder Armor", "Rend", "Hamstring", "Thunder Clap", "Demoralizing Shout" }) do
    FIELDS[#FIELDS + 1] = { "aura:target:" .. name, "C_UnitAuras.GetAuraDataBySpellName", "target", name,
        "HARMFUL", subfields = AURA_FIELDS }
end
FIELDS[#FIELDS + 1] = { "aura:player:index1", "C_UnitAuras.GetAuraDataByIndex", "player", 1, "HELPFUL",
    subfields = AURA_FIELDS }
FIELDS[#FIELDS + 1] = { "aura:target:index1", "C_UnitAuras.GetAuraDataByIndex", "target", 1, "HARMFUL",
    subfields = AURA_FIELDS }
for index = 1, 4 do
    local unit = "party" .. index
    FIELDS[#FIELDS + 1] = { "exists:" .. unit, "UnitExists", unit }
    FIELDS[#FIELDS + 1] = { "inRange:" .. unit, "UnitInRange", unit }
    FIELDS[#FIELDS + 1] = { "aura:" .. unit .. ":Battle Shout", "C_UnitAuras.GetAuraDataBySpellName", unit,
        "Battle Shout", "HELPFUL", subfields = AURA_FIELDS }
end

-- Restriction state (V-21). Found in the 9 Oct run: ADDON_RESTRICTION_STATE_CHANGED fires (type 0 -> state 1)
-- exactly at PLAYER_REGEN_DISABLED in the open world. Argument shapes below are guesses; errors are findings.
FIELDS[#FIELDS + 1] = { "secretRestrictions", "C_Secrets.HasSecretRestrictions" }
for restrictionType = 0, 5 do
    FIELDS[#FIELDS + 1] = { "restrictionState:" .. restrictionType, "C_RestrictedActions.GetAddOnRestrictionState",
        restrictionType }
    FIELDS[#FIELDS + 1] = { "restrictionActive:" .. restrictionType, "C_RestrictedActions.IsAddOnRestrictionActive",
        restrictionType }
end
-- What the client says will be secret right now (each answers a V-item directly if it works).
for _, spec in ipairs({
    { "secrecy:unitHealthMax:target", "C_Secrets.ShouldUnitHealthMaxBeSecret", "target" },
    { "secrecy:unitPower:player", "C_Secrets.ShouldUnitPowerBeSecret", "player" },
    { "secrecy:unitStats:player", "C_Secrets.ShouldUnitStatsBeSecret", "player" },
    { "secrecy:unitSpellCasting:target", "C_Secrets.ShouldUnitSpellCastingBeSecret", "target" },
    { "secrecy:unitIdentity:target", "C_Secrets.ShouldUnitIdentityBeSecret", "target" },
    { "secrecy:unitThreatState:target", "C_Secrets.ShouldUnitThreatStateBeSecret", "target" },
    { "secrecy:cooldowns", "C_Secrets.ShouldCooldownsBeSecret" },
    { "secrecy:auras", "C_Secrets.ShouldAurasBeSecret" },
    { "secrecy:spellCooldown:Charge", "C_Secrets.ShouldSpellCooldownBeSecret", "Charge" },
    { "secrecy:spellAura:Battle Shout", "C_Secrets.ShouldSpellAuraBeSecret", "Battle Shout" },
}) do
    FIELDS[#FIELDS + 1] = spec
end

-- Arguments of a field spec (array positions 3+), without trailing nils.
local function fieldArgs(field)
    return unpack(field, 3, #field)
end

---------------------------------------------------------------------------
-- Aggregation
---------------------------------------------------------------------------

local function contextBucket(ctx)
    local byContext = ns.db.combat.byContext
    local bucket = byContext[ctx]
    if not bucket then
        bucket = { samples = 0, fields = {} }
        byContext[ctx] = bucket
    end
    return bucket
end

local function fieldStat(bucket, key)
    local stat = bucket.fields[key]
    if not stat then
        stat = { readable = 0, secret = 0, isNil = 0, unchecked = 0, error = 0, missing = 0, types = {},
            examples = {}, errors = {} }
        bucket.fields[key] = stat
    end
    return stat
end

local function noteError(stat, err)
    stat.error = stat.error + 1
    if #stat.errors < ERROR_CAP then
        stat.errors[#stat.errors + 1] = tostring(err)
    end
end

--- Records one possibly-secret value under key. Returns its classification (or nil on failure).
local function recordScalar(bucket, key, value)
    local stat = fieldStat(bucket, key)
    local ok, info = pcall(classify, value)
    if not ok then
        noteError(stat, info)
        return nil
    end
    stat.types[info.type] = (stat.types[info.type] or 0) + 1
    if info.secret == true then
        stat.secret = stat.secret + 1
    elseif info.type == "nil" then
        stat.isNil = stat.isNil + 1
    elseif info.secret == false then
        stat.readable = stat.readable + 1
        -- info.value is confirmed non-secret, so comparing it is safe.
        if info.value ~= nil and #stat.examples < EXAMPLE_CAP then
            local duplicate = false
            for _, example in ipairs(stat.examples) do
                if example == info.value then
                    duplicate = true
                end
            end
            if not duplicate then
                stat.examples[#stat.examples + 1] = info.value
            end
        end
    else
        stat.unchecked = stat.unchecked + 1
    end
    return info
end

--- Records a return value; tables are recorded field by field (only whitelisted subfields if given).
local function recordValue(bucket, key, value, subfields)
    local info = recordScalar(bucket, key, value)
    if not info or info.type ~= "table" or info.secret == true then
        return info
    end
    local ok, err = pcall(function()
        for fieldName, inner in pairs(value) do
            if type(fieldName) == "string" and (not subfields or subfields[fieldName]) then
                recordScalar(bucket, key .. "." .. fieldName, inner)
            end
        end
    end)
    if not ok then
        noteError(fieldStat(bucket, key), err)
    end
    return info
end

local lastUsable = {} -- [key] = last non-secret boolean, for V-14 transitions

local function noteTransition(key, ctx, info)
    if not info or info.secret ~= false or type(info.value) ~= "boolean" then
        return
    end
    local previous = lastUsable[key]
    if previous ~= info.value then
        lastUsable[key] = info.value
        ns.PushCapped(ns.db.combat.transitions, { t = GetTime(), key = key, value = info.value, ctx = ctx },
            TRANSITION_CAP)
    end
end

local function sampleField(bucket, ctx, field)
    local fn = resolve(field[2])
    if type(fn) ~= "function" then
        fieldStat(bucket, field[1]).missing = fieldStat(bucket, field[1]).missing + 1
        return
    end
    local results = pack(pcall(fn, fieldArgs(field)))
    if not results[1] then
        noteError(fieldStat(bucket, field[1]), results[2])
        return
    end
    for index = 2, math.min(results.n, RETURN_CAP + 1) do
        local key = index == 2 and field[1] or (field[1] .. "#" .. (index - 1))
        local info = recordValue(bucket, key, results[index], field.subfields)
        if index == 2 and field.transitions then
            noteTransition(field[1], ctx, info)
        end
    end
    if results.n == 1 then
        recordScalar(bucket, field[1], nil) -- no returns at all counts as nil
    end
end

local function tick()
    local combat = ns.db and ns.db.combat
    if not combat or not combat.enabled then
        return
    end
    -- Gate on our own combat flag (from event names), which cannot be secret, or a hostile target.
    if not ns.state.inCombat then
        local hostile = ns.CallIsTrue("UnitCanAttack", "player", "target")
        if not hostile then
            if hostile == nil then
                combat.gateUnknown = (combat.gateUnknown or 0) + 1
            end
            return
        end
    end
    local ctx = ns.Context()
    local bucket = contextBucket(ctx)
    bucket.samples = bucket.samples + 1
    for _, field in ipairs(FIELDS) do
        sampleField(bucket, ctx, field)
    end
end

local ticker

local function startSampler()
    if ticker then
        return true
    end
    local newTicker = resolve("C_Timer.NewTicker")
    if type(newTicker) ~= "function" then
        return false
    end
    local ok, result = pcall(newTicker, SAMPLE_INTERVAL, function()
        local tickOk, err = pcall(tick)
        if not tickOk then
            ns.db.combat.tickErrors = (ns.db.combat.tickErrors or 0) + 1
            ns.db.combat.lastTickError = tostring(err)
        end
    end)
    if ok then
        ticker = result
    end
    return ok
end

local function stopSampler()
    if ticker and type(ticker.Cancel) == "function" then
        pcall(ticker.Cancel, ticker)
    end
    ticker = nil
end

local function summary()
    local parts = {}
    for _, ctx in ipairs({ "openWorld", "instance", "encounter" }) do
        local bucket = ns.db.combat.byContext[ctx]
        parts[#parts + 1] = ctx .. " " .. (bucket and bucket.samples or 0)
    end
    return table.concat(parts, ", ")
end

local function runCombat(rest)
    local combat = ns.db.combat
    local arg = rest:lower()
    if arg == "on" or (arg == "" and not combat.enabled) then
        combat.enabled = true
        if startSampler() then
            out("Combat sampler on (samples only in combat or with a hostile target). Stays on across /reload.")
        else
            out("Combat sampler could not start: C_Timer.NewTicker is unavailable.")
        end
    elseif arg == "off" or arg == "" then
        combat.enabled = false
        stopSampler()
        out("Combat sampler off.")
    end
    out("Samples so far: " .. summary() .. "; usability transitions: " .. #combat.transitions)
end

---------------------------------------------------------------------------
-- CLEU (V-16): capped per session, with extra room for misses (DODGE/PARRY/BLOCK/RESIST/IMMUNE)
---------------------------------------------------------------------------

local cleuSeen, cleuMissSeen = 0, 0

local function countInto(tbl, ctx, name)
    local byCtx = tbl[ctx]
    if not byCtx then
        byCtx = {}
        tbl[ctx] = byCtx
    end
    byCtx[name] = (byCtx[name] or 0) + 1
end

local function onCombatLog()
    local cleu = ns.db.cleu
    local ctx = ns.Context()
    cleu.seen = cleu.seen + 1
    local getInfo = resolve("CombatLogGetCurrentEventInfo")
    if type(getInfo) ~= "function" then
        cleu.noInfoFunction = true
        return
    end
    local results = pack(pcall(getInfo))
    if not results[1] then
        cleu.errors = cleu.errors + 1
        cleu.lastError = tostring(results[2])
        return
    end
    local args = {}
    for index = 2, math.min(results.n, CLEU_ARG_CAP + 1) do
        local ok, info = pcall(classify, results[index])
        args[index - 1] = ok and info or { error = "classify failed" }
    end
    -- Subevent name (arg 2) is used as a key only when confirmed non-secret.
    local subevent = args[2]
    local name = (subevent and subevent.secret == false and type(subevent.value) == "string") and subevent.value
        or "<unreadable>"
    countInto(cleu.subevents, ctx, name)
    local isMiss = name:find("_MISSED", 1, true) ~= nil
    if isMiss then
        -- SWING_MISSED: missType is arg 12; SPELL_*_MISSED: arg 15.
        local missInfo = name == "SWING_MISSED" and args[12] or args[15]
        if missInfo and missInfo.secret == false and type(missInfo.value) == "string" then
            countInto(cleu.missTypes, ctx, missInfo.value)
        end
    end
    local store = cleuSeen < CLEU_SESSION_CAP or (isMiss and cleuMissSeen < CLEU_MISS_SESSION_CAP)
    cleuSeen = cleuSeen + 1
    if isMiss then
        cleuMissSeen = cleuMissSeen + 1
    end
    if store then
        ns.PushCapped(cleu.events, { t = GetTime(), ctx = ctx, n = results.n - 1, args = args }, CLEU_STORE_CAP)
    end
end

-- Registered only when the info function exists: the 9 Oct beta run found it missing, and registering CLEU
-- anyway is the likely cause of a "blocked from an action only available to the Blizzard UI" popup at load.
if type(resolve("CombatLogGetCurrentEventInfo")) == "function" then
    ns.Listen("COMBAT_LOG_EVENT_UNFILTERED", { mode = "count", handler = onCombatLog })
else
    ns.registrations.COMBAT_LOG_EVENT_UNFILTERED = "skipped: CombatLogGetCurrentEventInfo missing"
end

---------------------------------------------------------------------------
-- UNIT_COMBAT fallback (avoidance and resists without CLEU) and nameplates (V-19)
---------------------------------------------------------------------------

ns.Listen("UNIT_COMBAT", { units = { "player", "target" }, cap = 400, handler = function(_, unit, action)
    local unitInfo, actionInfo = classify(unit), classify(action)
    local unitName = (unitInfo.secret == false and type(unitInfo.value) == "string") and unitInfo.value or "?"
    local actionName = (actionInfo.secret == false and type(actionInfo.value) == "string") and actionInfo.value
        or "<unreadable>"
    countInto(ns.db.unitCombat, ns.Context(), unitName .. ":" .. actionName)
end })

local nameplatesSeen = 0
ns.Listen("NAME_PLATE_UNIT_ADDED", { cap = 100, handler = function(_, unit)
    if nameplatesSeen >= NAMEPLATE_SESSION_CAP then
        return
    end
    local unitInfo = classify(unit)
    if unitInfo.secret ~= false or type(unitInfo.value) ~= "string" then
        return
    end
    nameplatesSeen = nameplatesSeen + 1
    local token = unitInfo.value
    ns.PushCapped(ns.db.nameplates, {
        t = GetTime(), ctx = ns.Context(), unit = token,
        level = ns.probeCallSafe("UnitLevel", token),
        classification = ns.probeCallSafe("UnitClassification", token),
        reaction = ns.probeCallSafe("UnitReaction", token, "player"),
        canAttack = ns.probeCallSafe("UnitCanAttack", "player", token),
        threat = ns.probeCallSafe("UnitThreatSituation", "player", token),
        affectingCombat = ns.probeCallSafe("UnitAffectingCombat", token),
    }, NAMEPLATE_SESSION_CAP * 3)
end })

---------------------------------------------------------------------------
-- Other recorder additions
---------------------------------------------------------------------------

for _, event in ipairs({
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "GROUP_ROSTER_UPDATE",
    "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
    "ADDON_RESTRICTION_STATE_CHANGED", -- V-21 candidate name (unconfirmed)
}) do
    ns.Listen(event)
end
ns.Listen("UPDATE_SHAPESHIFT_FORM", { cap = 100 })
ns.Listen("UI_ERROR_MESSAGE", { cap = 200 })
ns.Listen("UNIT_THREAT_LIST_UPDATE", { units = { "target" }, cap = 100 })
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
    ns.Listen(event, { units = { "target" }, cap = 100 })
end

-- M5 trigger events: counted per context only (they fire too often to record).
for _, event in ipairs({ "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED",
    "ACTIONBAR_UPDATE_USABLE" }) do
    ns.Listen(event, { mode = "count" })
end
ns.Listen("UNIT_POWER_UPDATE", { units = { "player" }, mode = "count" })
ns.Listen("UNIT_AURA", { units = { "player", "target" }, mode = "count" })
ns.Listen("UNIT_HEALTH", { units = { "target" }, mode = "count" })

---------------------------------------------------------------------------

local function newCleu()
    return { seen = 0, errors = 0, subevents = {}, missTypes = {}, events = {} }
end

table.insert(ns.onInit, function(db)
    db.combat = db.combat or { enabled = false }
    db.combat.byContext = db.combat.byContext or {}
    db.combat.transitions = db.combat.transitions or {}
    db.cleu = db.cleu or newCleu()
    db.cleu.playerGUID = ns.probeCallSafe("UnitGUID", "player")
    db.unitCombat = db.unitCombat or {}
    db.nameplates = db.nameplates or {}
    if db.combat.enabled then
        startSampler()
    end
end)

table.insert(ns.onClear, function(db)
    db.combat.byContext, db.combat.transitions = {}, {}
    db.combat.gateUnknown, db.combat.tickErrors, db.combat.lastTickError = nil, nil, nil
    db.cleu = newCleu()
    db.unitCombat, db.nameplates = {}, {}
    cleuSeen, cleuMissSeen, nameplatesSeen = 0, 0, 0
    for key in pairs(lastUsable) do
        lastUsable[key] = nil
    end
end)

ns.CombatSummary = summary

ns.AddCommand("combat", runCombat,
    "/wwprobe combat [on|off] - toggle the 0.25s combat sampler (records readability, not a full log)")
