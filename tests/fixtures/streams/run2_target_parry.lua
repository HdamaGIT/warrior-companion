-- Beta run 2 (10 Oct 2026), fight 8 (GetTime 124132.131 = t 0). Charge, Rend (772) twice, Hamstring (1715) three
-- times, a PARRY on the player and a PARRY on the target (the player's attack parried) 0.98s after a Hamstring: too
-- late to be that Hamstring's result, so it must not be paired with the cast.
local SPELLS = { Charge = 100, Rend = 772, Hamstring = 1715 }
return {
    name = "run2_target_parry",
    source = "beta run 2, fight 8 (GetTime 124132.131)",
    start = { data = { spellIDs = SPELLS, secrecy = "run2", inCombat = false } },
    events = {
        { t = 0.000, event = "PLAYER_ENTER_COMBAT" },
        { t = 0.000, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-100-0", 100 } },
        { t = 0.000, event = "PLAYER_REGEN_DISABLED", data = { inCombat = true } },
        { t = 0.000, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 1 } },
        { t = 0.989, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-772-0", 772 } },
        { t = 1.342, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 2.560, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-772-1", 772 } },
        { t = 3.494, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 9, 1 } },
        { t = 3.794, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 24, 1 } },
        { t = 4.095, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-1715-0", 1715 } },
        { t = 4.095, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 4, 1 } },
        { t = 5.413, event = "UNIT_COMBAT", args = { "player", "PARRY", "", 0, 1 } },
        { t = 5.513, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 7, 1 } },
        { t = 5.613, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-1715-1", 1715 } },
        { t = 5.613, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 4, 1 } },
        { t = 6.564, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 6.597, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 23, 1 } },
        { t = 7.098, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-1715-2", 1715 } },
        { t = 7.098, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 4, 1 } },
        { t = 8.082, event = "UNIT_COMBAT", args = { "target", "PARRY", "", 0, 1 } },
        { t = 8.516, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 7, 1 } },
        { t = 8.733, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 8, 1 } },
        { t = 8.816, event = "UNIT_COMBAT", args = { "target", "WOUND", "CRITICAL", 45, 1 } },
        { t = 11.669, event = "PLAYER_LEAVE_COMBAT" },
        { t = 11.936, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 0 } },
        { t = 11.936, event = "PLAYER_REGEN_ENABLED", data = { inCombat = false } },
    },
}
