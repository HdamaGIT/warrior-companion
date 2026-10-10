local addonName, ns = ...

-- Bootstrap: namespace, module registry, saved-variables initialisation, lifecycle and the /ww dispatcher.
ns.name = addonName

local L = ns.L
local Adapter = ns.Adapter
local Events = ns.Events
local DB = ns.DB
local Log = ns.Log

-- Module registry (ordered by registration) ---------------------------------------------------------------

ns.modules = {}
local modulesByName = {}

--- Registers a module. Modules call this at file load; OnInitialize/OnEnable run in registration order.
-- @param name string unique module name
-- @return table the new module (fields: name; add OnInitialize / OnEnable methods)
function ns:NewModule(name)
    if modulesByName[name] then
        error("module already registered: " .. tostring(name), 2)
    end
    local module = { name = name }
    modulesByName[name] = module
    ns.modules[#ns.modules + 1] = module
    return module
end

--- Looks up a registered module.
-- @param name string
-- @return table|nil
function ns:GetModule(name)
    return modulesByName[name]
end

local function runModules(method)
    for _, module in ipairs(ns.modules) do
        local handler = module[method]
        if type(handler) == "function" then
            local ok, err = pcall(handler, module)
            if not ok then
                Log.WarnOnce("module:" .. module.name .. ":" .. method,
                    string.format(L.MODULE_ERROR, module.name, method, tostring(err)))
            end
        end
    end
end

-- Lifecycle -----------------------------------------------------------------------------------------------

local Core = { initialised = false }
ns.Core = Core

local SCOPE_LABELS = { account = L.SCOPE_ACCOUNT, character = L.SCOPE_CHARACTER }

local function reportBackups(report)
    for scope, status in pairs(report) do
        if status.state == "backup" then
            local reason = L.DB_REASONS[status.reason] or status.reason
            Log.WarnOnce("db-backup:" .. scope, string.format(L.DB_BACKUP_WARNING, SCOPE_LABELS[scope], reason))
        end
    end
end

--- ADDON_LOADED handler: for this add-on only, initialises saved variables then runs module OnInitialize.
-- @param loadedName string name of the add-on that finished loading
-- Side effects: assigns WarriorWorkshopDB and WarriorWorkshopCharDB.
function Core:OnAddonLoaded(loadedName)
    if loadedName ~= addonName or self.initialised then
        return
    end
    self.initialised = true
    local account, character, report = DB.Init(WarriorWorkshopDB, WarriorWorkshopCharDB, Adapter.Time())
    WarriorWorkshopDB = account
    WarriorWorkshopCharDB = character
    reportBackups(report)
    Events:Off("ADDON_LOADED", self)
    runModules("OnInitialize")
end

--- PLAYER_LOGIN handler: fills character meta, then runs module OnEnable.
-- Side effects: writes character.meta.
function Core:OnPlayerLogin()
    DB.UpdateMeta(Adapter.GetPlayerMeta())
    runModules("OnEnable")
end

--- PLAYER_LOGOUT handler: stamps character.meta.lastSeen.
-- Side effects: writes character.meta.lastSeen.
function Core:OnPlayerLogout()
    DB.StampLastSeen(Adapter.Time())
end

Events:On("ADDON_LOADED", Core, "OnAddonLoaded")
Events:On("PLAYER_LOGIN", Core, "OnPlayerLogin")
Events:On("PLAYER_LOGOUT", Core, "OnPlayerLogout")

-- Slash commands -------------------------------------------------------------------------------------------

--- Builds the `/ww version` line.
-- @return string: add-on version, schema version and client interface/build
local function versionLine()
    local buildInfo = Adapter.GetBuildInfo() or {}
    local account = DB.GetAccount()
    return string.format(
        L.VERSION_LINE,
        L.ADDON_TITLE,
        tostring(Adapter.GetAddOnVersion() or L.UNKNOWN),
        tostring(account and account.schemaVersion or L.SCHEMA_NOT_INITIALISED),
        tostring(buildInfo.interface or L.UNKNOWN),
        tostring(buildInfo.build or L.UNKNOWN)
    )
end

local commands = {}

function commands.version()
    Adapter.Print(versionLine())
end

function commands.debug()
    Adapter.Print(Log.ToggleDebug() and L.DEBUG_ON or L.DEBUG_OFF)
end

--- Registers a `/ww <name>` subcommand (D-048). A later registration of the same name replaces the earlier one.
-- @param name string lower-case subcommand
-- @param fn function(rest) called with the trimmed text after the subcommand
function Core:RegisterCommand(name, fn)
    commands[string.lower(name)] = fn
end

--- Dispatches `/ww <command>`; unknown or not-yet-built commands print a notice.
-- @param msg string text after /ww
function Core.HandleSlash(msg)
    local input = (msg or ""):match("^%s*(.-)%s*$")
    local command = (input:match("^(%S+)") or ""):lower()
    local rest = input:match("^%S+%s+(.-)$") or ""
    local handler = commands[command]
    if handler then
        handler(rest)
    else
        Adapter.Print(string.format(L.NOT_IMPLEMENTED, input))
    end
end

SLASH_WW1 = "/ww"
SlashCmdList.WW = Core.HandleSlash
