local addonName, ns = ...

-- Player-facing strings (enUS/enGB). Game terms use the game's spellings.
local L = {}
ns.L = L

L.ADDON_TITLE = "Warrior Workshop"
L.UNKNOWN = "unknown"
L.NONE = "none"

-- /ww version: title, add-on version, schema version, interface, build
L.VERSION_LINE = "%s %s - schema %s - interface %s (build %s)"
L.SCHEMA_NOT_INITIALISED = "n/a"

L.NOT_IMPLEMENTED = "'/ww %s' is not available yet. Try /ww version."

-- Logging and Adapter warnings
L.API_UNAVAILABLE = "API unavailable: %s"
L.UNKNOWN_STAT = "Unknown item stat key: %s"
L.DEBUG_PREFIX = "[debug] "
L.DEBUG_ON = "Debug logging is on."
L.DEBUG_OFF = "Debug logging is off."

-- Event bus and module errors (name, handler, error text)
L.EVENT_REGISTER_FAILED = "Could not register game event %s."
L.HANDLER_MISSING = "Handler %s is missing for event %s."
L.HANDLER_ERROR = "Error in %s handler for %s: %s"
L.MODULE_ERROR = "Error in module %s during %s: %s"

-- Spell map (debug): resolved count, registered count, unknown names
L.SPELLMAP_REFRESHED = "Spell map: %d of %d abilities resolved; unknown: %s"

-- Saved variables
L.SCOPE_ACCOUNT = "account"
L.SCOPE_CHARACTER = "character"
L.DB_BACKUP_WARNING =
    "Saved %s data could not be used (%s). A backup was kept inside the saved variables and defaults were restored."
L.DB_REASONS = {
    corrupt = "corrupt data",
    future = "saved by a newer version",
    migration_failed = "migration failed",
}

-- Money (integer copper formatted for display)
L.MONEY_GOLD = "%dg"
L.MONEY_SILVER = "%ds"
L.MONEY_COPPER = "%dc"

-- Combat companion (M5). Ability names in rules use the game's spellings; labels below are what the HUD shows.
L.RULE_BATTLE_SHOUT = "Battle Shout"
L.RULE_EXECUTE = "Execute"
L.RULE_OVERPOWER = "Overpower"
L.RULE_AUTO_ATTACK = "Auto-attack off"
L.RULE_CHARGE = "Charge"
L.RULE_INTERCEPT = "Intercept"
L.STATE_DROPPED = "missing"
L.STATE_EXPIRING = "%ds"
L.RULE_DISABLED = "Combat rule %s is off: %s %s"
L.RULE_REASONS = {
    disabled = "switched off",
    unknownAbility = "ability not known:",
    unknownCondition = "unknown condition:",
}

-- HUD and /ww commands (M5)
L.HUD_SUSPENDED = "Suspended"
L.HUD_SUSPENDED_HINT = "Combat alerts are paused here (boss, Mythic+ or PvP restriction)."
L.HUD_UNLOCKED = "HUD unlocked: drag the frames, then /ww lock."
L.HUD_LOCKED = "HUD locked."
L.HUD_ON = "Combat alerts on."
L.HUD_OFF = "Combat alerts off."
L.HUD_USAGE = "Usage: /ww hud on|off"
L.HUD_TEST_ON = "HUD test: showing every display with sample data. /ww test again to stop."
L.HUD_TEST_OFF = "HUD test stopped."
L.HUD_IN_COMBAT = "Not in combat: try again when combat ends."
L.HUD_FRAME_ALERT_STRIP = "Alert strip"
L.HUD_FRAME_BIG_ALERT = "Big alert"
L.HUD_FRAME_BADGES = "Badges"
