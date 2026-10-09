local addonName, ns = ...

-- Player-facing strings (enUS/enGB). Game terms use the game's spellings.
local L = {}
ns.L = L

L.ADDON_TITLE = "Warrior Workshop"
L.UNKNOWN = "unknown"

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
