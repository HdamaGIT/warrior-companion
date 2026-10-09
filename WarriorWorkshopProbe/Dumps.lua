local addonName, ns = ...

-- M3 dumps (SPEC_V2 §12.2): spellbook and named warrior abilities (V-22), trainer services (V-24) and tank
-- stat APIs (V-33). Also extends the static checks for the combat, chat, gear and macro APIs.
-- Values that could be secret (stats, possibly in combat) go through probeCallSafe.

local out, resolve, probeCall, probeCallSafe = ns.out, ns.resolve, ns.probeCall, ns.probeCallSafe

local TRAINER_SERVICE_CAP = 200
local TRAINER_VISIT_CAP = 3
local SPELLBOOK_ITEM_CAP = 400

-- Ability names from V-22 plus core cooldowns (R-06) and a few Mainline names, in the game's spelling.
-- Unknown names are findings, not errors.
ns.WARRIOR_ABILITIES = {
    "Overpower", "Revenge", "Execute", "Charge", "Intercept", "Pummel", "Shield Bash", "Battle Shout",
    "Demoralizing Shout", "Thunder Clap", "Rend", "Sunder Armor", "Hamstring", "Taunt", "Mocking Blow",
    "Challenging Shout", "Shield Wall", "Last Stand", "Disarm", "Intimidating Shout", "Bloodrage",
    "Berserker Rage", "Heroic Strike", "Cleave", "Mortal Strike", "Bloodthirst", "Shield Slam", "Whirlwind",
    "Shield Block", "Victory Rush", "Slam", "Retaliation", "Recklessness", "Death Wish", "Sweeping Strikes",
    "Intervene", "Spell Reflection", "Commanding Shout", "Auto Attack",
    "Battle Stance", "Defensive Stance", "Berserker Stance",
}

ns.Extend("FUNCTION_CHECKS", {
    -- combat reads (V-11..V-19, V-23, V-32)
    "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitPower", "UnitPowerMax", "UnitCanAttack",
    "UnitExists", "UnitGUID", "UnitInRange", "UnitIsDeadOrGhost", "UnitThreatSituation",
    "UnitDetailedThreatSituation", "UnitClassification", "UnitReaction", "UnitCastingInfo", "UnitChannelInfo",
    "C_Spell.GetSpellInfo", "C_Spell.GetSpellCooldown", "C_Spell.IsSpellUsable", "C_Spell.IsSpellInRange",
    "C_Spell.IsCurrentSpell", "C_Spell.GetSpellCharges", "IsPlayerSpell", "IsSpellKnown",
    "C_UnitAuras.GetPlayerAuraBySpellID", "C_UnitAuras.GetAuraDataBySpellName", "C_UnitAuras.GetAuraDataByIndex",
    "C_UnitAuras.GetAuraDataByAuraInstanceID", "GetShapeshiftForm", "GetShapeshiftFormID",
    "GetShapeshiftFormInfo", "GetNumShapeshiftForms", "CombatLogGetCurrentEventInfo",
    "C_ChallengeMode.IsChallengeModeActive", "IsInInstance", "IsInGroup", "IsInRaid",
    -- restricted-context candidates (V-21; names are guesses)
    "C_RestrictedActions.IsAddOnRestrictionActive", "C_RestrictedActions.GetAddOnRestrictionState",
    -- spellbook (V-22)
    "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookSkillLineInfo",
    "C_SpellBook.GetSpellBookItemInfo", "GetNumSpellTabs", "GetSpellTabInfo",
    -- trainer (V-24)
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceLevelReq", "GetTrainerServiceCost",
    "GetTrainerServiceSkillReq",
    -- gear sets, secure buttons, bindings, macros (V-27..V-30)
    "C_EquipmentSet.UseEquipmentSet", "SetBindingClick", "SetBinding", "GetBindingAction", "GetBindingKey",
    "SaveBindings", "GetCurrentBindingSet", "CreateMacro", "EditMacro", "DeleteMacro", "GetNumMacros",
    "GetMacroIndexByName", "GetMacroInfo", "C_CVar.GetCVar", "GetCVar",
    -- tank stats (V-33)
    "GetDodgeChance", "GetParryChance", "GetBlockChance", "GetShieldBlock", "UnitArmor", "UnitDefense",
    "GetCombatRating", "GetCombatRatingBonus", "GetCritChance", "GetHitModifier", "GetExpertise", "UnitStat",
    "UnitAttackPower", "UnitAttackSpeed", "UnitDamage", "GetMasteryEffect",
})

ns.Extend("NAMESPACES", {
    "C_Spell", "C_UnitAuras", "C_SpellBook", "C_RestrictedActions", "C_Secrets", "C_CooldownViewer",
    "C_DamageMeter", "C_ChallengeMode", "C_PaperDollInfo", "C_CVar",
})

---------------------------------------------------------------------------
-- /wwprobe spells (V-22)
---------------------------------------------------------------------------

local function firstReturn(report)
    return report.ok and report.returns and report.returns[1] or nil
end

local function dumpSpellbook(spells)
    local numLines = firstReturn(probeCall("C_SpellBook.GetNumSpellBookSkillLines"))
    if type(numLines) ~= "number" then
        spells.spellbookError = "C_SpellBook.GetNumSpellBookSkillLines unavailable"
        spells.legacyTabs = probeCall("GetNumSpellTabs")
        return
    end
    local bank = resolve("Enum.SpellBookSpellBank.Player")
    spells.bankEnum = bank
    spells.skillLines = {}
    spells.items = {}
    for line = 1, numLines do
        local info = probeCall("C_SpellBook.GetSpellBookSkillLineInfo", line)
        spells.skillLines[line] = info
        local lineInfo = firstReturn(info)
        if type(lineInfo) == "table" and type(lineInfo.itemIndexOffset) == "number"
            and type(lineInfo.numSpellBookItems) == "number" then
            for index = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                if #spells.items >= SPELLBOOK_ITEM_CAP then
                    return
                end
                spells.items[#spells.items + 1] = { line = line, index = index,
                    info = firstReturn(probeCall("C_SpellBook.GetSpellBookItemInfo", index, bank)) }
            end
        end
    end
end

local function runSpells()
    local spells = { at = time(), ctx = ns.Context() }
    dumpSpellbook(spells)

    spells.named = {}
    local known, unknown = 0, {}
    for _, name in ipairs(ns.WARRIOR_ABILITIES) do
        local entry = { info = probeCall("C_Spell.GetSpellInfo", name) }
        local info = firstReturn(entry.info)
        if type(info) == "table" then
            known = known + 1
            if type(info.spellID) == "number" then
                entry.isPlayerSpell = probeCall("IsPlayerSpell", info.spellID)
                entry.isSpellKnown = probeCall("IsSpellKnown", info.spellID)
            end
        else
            unknown[#unknown + 1] = name
        end
        spells.named[name] = entry
    end

    spells.stances = { count = probeCall("GetNumShapeshiftForms"), forms = {} }
    local numForms = firstReturn(spells.stances.count)
    if type(numForms) == "number" then
        for index = 1, numForms do
            spells.stances.forms[index] = probeCall("GetShapeshiftFormInfo", index)
        end
    end
    ns.db.spells = spells

    out(string.format("Spells dump saved: %d spellbook items, %d of %d named abilities resolve, %d stance(s).",
        spells.items and #spells.items or 0, known, #ns.WARRIOR_ABILITIES, #spells.stances.forms))
    if #unknown > 0 then
        out("Not resolved by name: " .. table.concat(unknown, ", "))
    end
end

---------------------------------------------------------------------------
-- /wwprobe trainer (V-24); also runs automatically on TRAINER_SHOW
---------------------------------------------------------------------------

local function runTrainer(trigger)
    local visit = { at = time(), trigger = trigger, count = probeCall("GetNumTrainerServices"), services = {} }
    local count = firstReturn(visit.count)
    if type(count) == "number" then
        for index = 1, math.min(count, TRAINER_SERVICE_CAP) do
            visit.services[index] = {
                info = probeCall("GetTrainerServiceInfo", index),
                levelReq = probeCall("GetTrainerServiceLevelReq", index),
                cost = probeCall("GetTrainerServiceCost", index),
                skillReq = probeCall("GetTrainerServiceSkillReq", index),
            }
        end
    end
    ns.PushCapped(ns.db.trainer, visit, TRAINER_VISIT_CAP)
    out(string.format("Trainer dump saved (%s): %s service(s).", trigger, tostring(count)))
end

ns.Listen("TRAINER_SHOW", { handler = function()
    -- Services load just after the window opens.
    ns.After(0.5, function()
        runTrainer("auto")
    end)
end })
ns.Listen("TRAINER_CLOSED")

---------------------------------------------------------------------------
-- /wwprobe tank (V-33)
---------------------------------------------------------------------------

local TANK_CALLS = {
    { "dodge", "GetDodgeChance" }, { "parry", "GetParryChance" }, { "block", "GetBlockChance" },
    { "shieldBlock", "GetShieldBlock" }, { "armor", "UnitArmor", "player" }, { "defense", "UnitDefense", "player" },
    { "crit", "GetCritChance" }, { "hitModifier", "GetHitModifier" }, { "expertise", "GetExpertise" },
    { "mastery", "GetMasteryEffect" }, { "healthMax", "UnitHealthMax", "player" }, { "level", "UnitLevel", "player" },
    { "attackPower", "UnitAttackPower", "player" }, { "attackSpeed", "UnitAttackSpeed", "player" },
    { "damage", "UnitDamage", "player" },
    { "strength", "UnitStat", "player", 1 }, { "agility", "UnitStat", "player", 2 },
    { "stamina", "UnitStat", "player", 3 }, { "intellect", "UnitStat", "player", 4 },
    { "spirit", "UnitStat", "player", 5 },
}

-- Combat rating constants; missing ones are recorded as absent.
local RATING_NAMES = {
    "CR_DEFENSE_SKILL", "CR_DODGE", "CR_PARRY", "CR_BLOCK", "CR_HIT_MELEE", "CR_CRIT_MELEE", "CR_HASTE_MELEE",
    "CR_EXPERTISE", "CR_MASTERY", "CR_AVOIDANCE",
}

local function runTank()
    local tank = { at = time(), ctx = ns.Context(), inCombat = ns.CallIsTrue("InCombatLockdown"), calls = {},
        ratings = {} }
    for _, call in ipairs(TANK_CALLS) do
        tank.calls[call[1]] = probeCallSafe(call[2], call[3], call[4])
    end
    for _, name in ipairs(RATING_NAMES) do
        local index = resolve(name)
        if type(index) == "number" then
            tank.ratings[name] = { index = index, rating = probeCallSafe("GetCombatRating", index),
                bonus = probeCallSafe("GetCombatRatingBonus", index) }
        else
            tank.ratings[name] = { absent = true }
        end
    end
    ns.db.tank = tank
    out("Tank stats saved. Compare with the character pane and note any differences.")
end

---------------------------------------------------------------------------

table.insert(ns.onInit, function(db)
    db.trainer = db.trainer or {}
end)
table.insert(ns.onClear, function(db)
    db.spells, db.tank, db.trainer = nil, nil, {}
end)

ns.AddCommand("spells", runSpells, "/wwprobe spells - dump the spellbook, named warrior abilities and stances")
ns.AddCommand("trainer", function()
    runTrainer("command")
end, "/wwprobe trainer - dump trainer services (window open; also automatic on opening)")
ns.AddCommand("tank", runTank, "/wwprobe tank - dump dodge, parry, block, defense, armour and stats")
