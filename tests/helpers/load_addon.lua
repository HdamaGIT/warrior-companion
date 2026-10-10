-- Loads add-on files the way the WoW client does: each file is a chunk called with (addonName, ns).
-- Paths are relative to the repository root (busted and CI run from there).
local H = {}

H.mockAdapter = dofile("tests/helpers/mock_adapter.lua")

-- The Core files in .toc order.
H.CORE_FILES = {
    "Locale/enUS.lua",
    "Core/Util.lua",
    "Core/Log.lua",
    "Core/Adapter.lua",
    "Core/Events.lua",
    "Core/Migrations.lua",
    "Core/DB.lua",
    "Core/Init.lua",
    "Core/Context.lua",
    "Core/SpellMap.lua",
}

--- Loads one add-on file into ns.
-- @param ns table the shared namespace
-- @param relPath string path under WarriorWorkshop/
-- @param env table|nil optional sandbox environment for the chunk (setfenv)
function H.loadFile(ns, relPath, env)
    local chunk = assert(loadfile("WarriorWorkshop/" .. relPath))
    if env then
        setfenv(chunk, env)
    end
    return chunk("WarriorWorkshop", ns)
end

--- Builds a namespace by loading files in order.
-- @param files array of paths under WarriorWorkshop/ (default: all Core files)
-- @param opts table|nil { adapter = mock (installed as ns.Adapter; Core/Adapter.lua is then skipped),
--   env = sandbox environment }
-- @return ns
function H.newNs(files, opts)
    opts = opts or {}
    local ns = {}
    if opts.adapter then
        ns.Adapter = opts.adapter
    end
    for _, relPath in ipairs(files or H.CORE_FILES) do
        if not (opts.adapter and relPath == "Core/Adapter.lua") then
            H.loadFile(ns, relPath, opts.env)
        end
    end
    return ns
end

--- Core files up to and including DB.lua: everything before Init.lua, which writes slash-command globals and
-- defines ns:NewModule (so the module files after it need it too).
function H.pureFiles()
    local files = {}
    for _, relPath in ipairs(H.CORE_FILES) do
        if relPath == "Core/Init.lua" then
            break
        end
        files[#files + 1] = relPath
    end
    return files
end

-- The Combat files in .toc order (M5). Pure modules: no WoW globals, so they load in busted as they are.
H.COMBAT_FILES = {
    "Combat/Conditions.lua",
    "Combat/AuraTracker.lua",
    "Combat/Snapshot.lua",
    "Combat/Rules.lua",
    "Combat/Avoidance.lua",
    "Combat/RulePacks/WarriorDefault.lua",
    "Combat/Companion.lua",
}

--- Loads all Core files, including Init.lua, into a sandbox environment.
-- The sandbox reads through to _G; writes land in env, so tests can see which globals the files create.
-- @param opts table|nil { adapter = mock, stubs = table of extra environment fields, extraFiles = array of paths
--   loaded after the Core files (e.g. H.COMBAT_FILES or a prefix of it) }
-- @return ns, env
function H.bootSandbox(opts)
    opts = opts or {}
    local env = setmetatable({ SlashCmdList = {} }, { __index = _G })
    for key, value in pairs(opts.stubs or {}) do
        env[key] = value
    end
    local files = {}
    for _, relPath in ipairs(H.CORE_FILES) do
        files[#files + 1] = relPath
    end
    for _, relPath in ipairs(opts.extraFiles or {}) do
        files[#files + 1] = relPath
    end
    local ns = H.newNs(files, { adapter = opts.adapter, env = env })
    return ns, env
end

--- Boots the add-on (Core plus extraFiles) against a mock adapter and runs ADDON_LOADED and PLAYER_LOGIN.
-- @param mock table mock adapter
-- @param extraFiles array|nil paths after the Core files (default H.COMBAT_FILES)
-- @return ns, env
function H.boot(mock, extraFiles)
    local ns, env = H.bootSandbox({ adapter = mock, extraFiles = extraFiles or H.COMBAT_FILES })
    mock.frame:Fire("ADDON_LOADED", "WarriorWorkshop")
    mock.frame:Fire("PLAYER_LOGIN")
    return ns, env
end

return H
