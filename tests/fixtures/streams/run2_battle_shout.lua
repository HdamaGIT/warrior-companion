-- Beta run 2 (10 Oct 2026), fight 2. Battle Shout (6673) cast out of combat 6.1s before the pull (GetTime 123989.334
-- = t 0). The real aura was readable out of combat (duration 180, sourceUnit player) and unreadable in combat. The
-- `data` steps model what the client would report; with secrecy "run2" the mock hides auras while in combat.
-- Auto-attack drops and restarts twice mid-fight (PLAYER_LEAVE_COMBAT / PLAYER_ENTER_COMBAT pairs). The aura `expires`
-- is in stream time, so replay this fixture from clock 0.
local SPELLS = { Charge = 100, ["Battle Shout"] = 6673 }
return {
    name = "run2_battle_shout",
    source = "beta run 2, fight 2 (GetTime 123989.334)",
    start = { data = { spellIDs = SPELLS, secrecy = "run2", inCombat = false,
        combat = { auras = { player = { ["Battle Shout"] = false } } } } },
    events = {
        { t = 0.000, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-6673-0", 6673 },
            data = { combat = { auras = { player = { ["Battle Shout"] =
                { stacks = 0, expires = 180.000, duration = 180, fromPlayer = true } } } } } },
        { t = 0.000, event = "UNIT_AURA", args = { "player" } },
        { t = 6.122, event = "PLAYER_ENTER_COMBAT", data = { combat = { autoAttacking = true } } },
        { t = 6.122, event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "Cast-3-0-0-0-100-0", 100 } },
        { t = 6.122, event = "PLAYER_REGEN_DISABLED", data = { inCombat = true } },
        { t = 6.122, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 1 } },
        { t = 7.507, event = "UNIT_COMBAT", args = { "player", "PARRY", "", 0, 1 } },
        { t = 7.741, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 25, 1 } },
        { t = 9.526, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 5, 1 } },
        { t = 9.543, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 24, 1 } },
        { t = 11.428, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 5, 1 } },
        { t = 12.429, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 24, 1 } },
        { t = 13.521, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 6, 1 } },
        { t = 13.571, event = "PLAYER_LEAVE_COMBAT", data = { combat = { autoAttacking = false } } },
        { t = 13.571, event = "PLAYER_ENTER_COMBAT", data = { combat = { autoAttacking = true } } },
        { t = 15.081, event = "PLAYER_LEAVE_COMBAT", data = { combat = { autoAttacking = false } } },
        { t = 15.081, event = "PLAYER_ENTER_COMBAT", data = { combat = { autoAttacking = true } } },
        { t = 15.499, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 6, 1 } },
        { t = 17.484, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 6, 1 } },
        { t = 18.585, event = "UNIT_COMBAT", args = { "target", "WOUND", "", 23, 1 } },
        { t = 19.653, event = "UNIT_COMBAT", args = { "player", "WOUND", "", 6, 1 } },
        { t = 20.903, event = "PLAYER_LEAVE_COMBAT", data = { combat = { autoAttacking = false } } },
        { t = 21.537, event = "ADDON_RESTRICTION_STATE_CHANGED", args = { 0, 0 } },
        { t = 21.537, event = "PLAYER_REGEN_ENABLED", data = { inCombat = false } },
    },
}
