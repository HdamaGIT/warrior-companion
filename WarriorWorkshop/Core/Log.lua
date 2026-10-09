local addonName, ns = ...

-- Debug and warn-once output. Prints through the Adapter; the debug flag lives in settings.debug.
-- Resolves ns.Adapter and ns.DB lazily because it loads before both.
local Log = {}
ns.Log = Log

local warned = {}

--- Returns whether debug logging is on.
-- @return boolean
function Log.IsDebug()
    local db = ns.DB
    local settings = db and db.GetSettings and db.GetSettings()
    return settings ~= nil and settings.debug == true
end

--- Prints the arguments (space separated, via tostring) when debug logging is on.
-- @param ... values; only pass values known not to be secret
-- Side effects: chat output when settings.debug is true.
function Log.Debug(...)
    if not Log.IsDebug() then
        return
    end
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring((select(index, ...)))
    end
    ns.Adapter.Print(ns.L.DEBUG_PREFIX .. table.concat(parts, " "))
end

--- Prints a message the first time a key is seen; later calls with the same key are ignored.
-- @param key string identifying the warning
-- @param msg string|nil text to print (defaults to key)
-- @return boolean true if printed
-- Side effects: chat output once per key per session.
function Log.WarnOnce(key, msg)
    if warned[key] then
        return false
    end
    warned[key] = true
    ns.Adapter.Print(msg or key)
    return true
end

--- Sets and persists the debug flag.
-- @param enabled boolean
-- @return boolean the new state (false if the database is not ready)
-- Side effects: writes settings.debug.
function Log.SetDebug(enabled)
    local settings = ns.DB and ns.DB.GetSettings and ns.DB.GetSettings()
    if not settings then
        return false
    end
    settings.debug = enabled == true
    return settings.debug
end

--- Toggles the debug flag.
-- @return boolean the new state
function Log.ToggleDebug()
    return Log.SetDebug(not Log.IsDebug())
end
