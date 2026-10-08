local addonName, ns = ...

-- Bootstrap. M0 scope: namespace and `/ww version` only.
-- The module registry, event bus and SavedVariables arrive in M2.
ns.name = addonName

local L = ns.L
local Adapter = ns.Adapter

--- Builds the `/ww version` line.
-- @return string: add-on version, schema version and client interface/build
local function versionLine()
    local buildInfo = Adapter.GetBuildInfo() or {}
    return string.format(
        L.VERSION_LINE,
        L.ADDON_TITLE,
        tostring(Adapter.GetAddOnVersion() or L.UNKNOWN),
        L.SCHEMA_NOT_INITIALISED,
        tostring(buildInfo.interface or L.UNKNOWN),
        tostring(buildInfo.build or L.UNKNOWN)
    )
end

local commands = {}

function commands.version()
    Adapter.Print(versionLine())
end

local function onSlash(msg)
    local input = (msg or ""):match("^%s*(.-)%s*$")
    local command = (input:match("^(%S+)") or ""):lower()
    local handler = commands[command]
    if handler then
        handler()
    else
        Adapter.Print(string.format(L.NOT_IMPLEMENTED, input))
    end
end

SLASH_WW1 = "/ww"
SlashCmdList.WW = onSlash
