-- ASSUMED, not observed. Run 2 saw only WOUND, PARRY and MISS (plus the BLOCK_REDUCED descriptor on a target WOUND).
-- DODGE, BLOCK, RESIST, a player-side BLOCK_REDUCED and a taunt resist are shaped like the observed events (unit,
-- action, descriptor, amount, school) so the avoidance detector can be tested before run 3 confirms them
-- [VERIFY V-16]. Spell IDs are fake (9xxxxx).
local SPELLS = { Taunt = 900355, ["Heroic Strike"] = 900078 }
return {
    name = "assumed_avoidance",
    source = "synthetic (ASSUMED shapes)",
    start = { data = { spellIDs = SPELLS, secrecy = "run2", inCombat = false } },
    events = {
        { t = 0.000, event = "PLAYER_REGEN_DISABLED", data = { inCombat = true } },
        { t = 0.000, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 1 } },
        { t = 1.000, event = "UNIT_COMBAT", args = { "player", "DODGE", "", 0, 1 } },
        { t = 2.000, event = "UNIT_COMBAT", args = { "player", "BLOCK", "", 0, 1 } },
        { t = 3.000, event = "UNIT_COMBAT", args = { "player", "WOUND", "BLOCK_REDUCED", 12, 1 } },
        { t = 4.000, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-0", 900355 } },
        { t = 4.100, event = "UNIT_COMBAT", args = { "target", "RESIST", "", 0, 1 } },
        { t = 5.000, event = "UNIT_COMBAT", args = { "target", "DODGE", "", 0, 1 } },
        { t = 6.000, event = "UNIT_COMBAT", args = { "nameplate3", "PARRY", "", 0, 1 } },
        { t = 7.000, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 0 } },
        { t = 7.000, event = "PLAYER_REGEN_ENABLED", data = { inCombat = false } },
    },
}
