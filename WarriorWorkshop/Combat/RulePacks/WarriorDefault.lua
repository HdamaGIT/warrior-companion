local addonName, ns = ...

-- Default warrior rule pack: the M5 must-have alerts (SPEC_V2 §7.2) within the D-044 gate.
--   U-01 Battle Shout  Degraded: real aura when readable, else own casts + learned duration (D-048)
--   R-03 Execute       Degraded: IsSpellUsable only (target health is secret)
--   R-01 Overpower     Go (usability + cooldown); the stance hint is deferred (D-048)
--   S-04 Auto-attack   Go
--   X-01 Charge range  Go (Intercept likewise, when known)
-- Not here: R-11 Interrupt and R-06 cooldown tracker (No-go), X-06 combat text (off the launch target, D-043).
-- Thresholds are labelled placeholders, editable through combat.ruleOverrides[id].args (D-039).
-- Defaults live in code; SavedVariables keep sparse overrides only (D-039).
local L = ns.L

ns.RulePacks = ns.RulePacks or {}

ns.RulePacks.WarriorDefault = {
    {
        id = "battleShout",
        label = L.RULE_BATTLE_SHOUT,
        ability = "Battle Shout",
        severity = "dropped",
        display = "big",
        countdown = "player",
        args = { expiring = 10 }, -- placeholder: seconds left that count as "expiring"
        states = {
            -- Dropped: in combat or targeting a hostile, and no Battle Shout (anyone's) on the player.
            { name = "dropped", when = { { "inCombat" }, { "auraMissing", "player", "@ability", false } } },
            { name = "dropped", when = { { "targetHostile" }, { "auraMissing", "player", "@ability", false } } },
            { name = "expiring", when = { { "auraExpiringWithin", "player", "@ability", "$expiring" } } },
        },
        throttle = 0.1,
    },
    {
        id = "execute",
        label = L.RULE_EXECUTE,
        ability = "Execute",
        severity = "reactive",
        display = "strip",
        when = { { "targetHostile" }, { "spellUsable", "@ability" } },
        throttle = 0.1,
    },
    {
        id = "overpower",
        label = L.RULE_OVERPOWER,
        ability = "Overpower",
        severity = "reactive",
        display = "strip",
        when = { { "spellUsable", "@ability" }, { "cooldownReady", "@ability" } },
        throttle = 0.1,
    },
    {
        -- Melee range is read through Heroic Strike, which every warrior knows from level 1 (V-22).
        id = "autoAttack",
        label = L.RULE_AUTO_ATTACK,
        ability = "Heroic Strike",
        severity = "reactive",
        display = "badge",
        when = {
            { "inCombat" }, { "targetHostile" }, { "inRange", "@ability", "target" }, { "autoAttacking", false },
        },
        delay = 1.5, -- S-04: not auto-attacking for more than 1.5s
        throttle = 0.2,
    },
    {
        id = "chargeRange",
        label = L.RULE_CHARGE,
        ability = "Charge",
        severity = "reactive",
        display = "badge",
        when = {
            { "outOfCombat" }, { "targetHostile" }, { "spellUsable", "@ability" }, { "inRange", "@ability", "target" },
            { "cooldownReady", "@ability" },
        },
        throttle = 0.2,
    },
    {
        -- Usability already covers the stance (Berserker Stance) in the Classic kit.
        id = "interceptRange",
        label = L.RULE_INTERCEPT,
        ability = "Intercept",
        severity = "reactive",
        display = "badge",
        when = {
            { "outOfCombat" }, { "targetHostile" }, { "spellUsable", "@ability" }, { "inRange", "@ability", "target" },
            { "cooldownReady", "@ability" },
        },
        throttle = 0.2,
    },
}
