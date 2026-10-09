-- Smoke tests for add-on packaging: the commonest load failures are a .toc that
-- lists a missing file or forgets a SavedVariables declaration.

local function readLines(path)
    local file = assert(io.open(path, "r"), "cannot open " .. path)
    local lines = {}
    for line in file:lines() do
        lines[#lines + 1] = (line:gsub("\r$", ""))
    end
    file:close()
    return lines
end

--- Parses a .toc into { meta = { [key] = value }, files = { "dir/file.lua", ... } }.
local function parseToc(path)
    local toc = { meta = {}, files = {} }
    for _, line in ipairs(readLines(path)) do
        local key, value = line:match("^##%s*([%w%-_]+)%s*:%s*(.-)%s*$")
        if key then
            toc.meta[key] = value
        elseif line:match("%S") and not line:match("^%s*#") then
            toc.files[#toc.files + 1] = (line:match("^%s*(.-)%s*$"):gsub("\\", "/"))
        end
    end
    return toc
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

describe("runtime", function()
    it("is Lua 5.1, matching the WoW client", function()
        assert.are.equal("Lua 5.1", _VERSION)
    end)
end)

local addons = {
    {
        dir = "WarriorWorkshop",
        savedVariables = "WarriorWorkshopDB",
        savedVariablesPerCharacter = "WarriorWorkshopCharDB",
    },
    {
        dir = "WarriorWorkshopProbe",
        savedVariables = "WarriorWorkshopProbeDB",
    },
}

for _, addon in ipairs(addons) do
    describe(addon.dir .. ".toc", function()
        local toc = parseToc(addon.dir .. "/" .. addon.dir .. ".toc")

        it("declares a numeric Interface", function()
            assert.is_truthy(toc.meta.Interface and toc.meta.Interface:match("^%d+$"))
        end)

        it("declares its SavedVariables", function()
            assert.are.equal(addon.savedVariables, toc.meta.SavedVariables)
            if addon.savedVariablesPerCharacter then
                assert.are.equal(addon.savedVariablesPerCharacter, toc.meta.SavedVariablesPerCharacter)
            end
        end)

        it("lists at least one file, and every listed file exists", function()
            assert.is_true(#toc.files > 0)
            for _, relPath in ipairs(toc.files) do
                assert.is_true(fileExists(addon.dir .. "/" .. relPath), "missing file in .toc: " .. relPath)
            end
        end)
    end)
end

describe("WarriorWorkshop.toc load order", function()
    it("lists the Core files first, in the order the test helpers load them", function()
        local helpers = dofile("tests/helpers/load_addon.lua")
        local toc = parseToc("WarriorWorkshop/WarriorWorkshop.toc")
        for index, relPath in ipairs(helpers.CORE_FILES) do
            assert.are.equal(relPath, toc.files[index])
        end
    end)
end)
