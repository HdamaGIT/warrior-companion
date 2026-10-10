-- Beta run 2 (10 Oct 2026), fight 1, open world, level 8 warrior. Transcribed from the probe event recorder
-- (raw files are git-ignored); times are relative to the pull (GetTime 123922.563). Observed: Charge opens, a PARRY
-- on the player, a BLOCK_REDUCED descriptor on one of the player's hits, restriction type 0 on/off with
-- PLAYER_REGEN_*. UNIT_COMBAT args: unit, action, descriptor, amount, school.
local SPELLS = { Charge = 100 }
return {
    name = "run2_fight_parry",
    source = "beta run 2, fight 1 (GetTime 123922.563)",
    start = { data = { spellIDs = SPELLS, secrecy = "run2", inCombat = false } },
    events = {
        { t = 0.000, event = "PLAYER_ENTER_COMBAT" },
        { t = 0.000, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-100-0", 100 } },
        { t = 0.000, event = "PLAYER_REGEN_DISABLED", data = { inCombat = true } },
        { t = 0.000, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 1 } },
        { t = 1.291, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 21, 1 } },
        { t = 1.374, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 7, 1 } },
        { t = 3.391, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 4.532, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 21, 1 } },
        { t = 5.333, event = "UNIT_COMBAT", args = { "player", "PARRY", "", 0, 1 } },
        { t = 5.900, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 21, 1 } },
        { t = 7.268, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 8.770, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 20, 1 } },
        { t = 9.237, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 11.239, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 12.140, event = "UNIT_COMBAT", args = { "target", "WOUND", "BLOCK_REDUCED", 19, 1 } },
        { t = 13.374, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 14.659, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 22, 1 } },
        { t = 15.393, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 17.495, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 0 } },
        { t = 17.495, event = "PLAYER_REGEN_ENABLED", data = { inCombat = false } },
        { t = 18.045, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 18.496, event = "PLAYER_LEAVE_COMBAT" },
    },
}
