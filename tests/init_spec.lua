local H = dofile("tests/helpers/load_addon.lua")

local ADDON = "WarriorWorkshop"

describe("init", function()
    local mock, ns, env

    --- Boots all Core files against the mock adapter. stubs sets saved-variables globals in the sandbox.
    local function boot(stubs)
        mock = H.mockAdapter.new({
            time = 4242,
            playerMeta = { name = "Hugh", realm = "Realm", classFile = "WARRIOR", level = 80 },
        })
        ns, env = H.bootSandbox({ adapter = mock, stubs = stubs })
    end

    --- Records lifecycle calls into the shared calls list.
    local function newRecorder(name, calls)
        local module = ns:NewModule(name)
        function module:OnInitialize()
            calls[#calls + 1] = name .. ":init"
        end
        function module:OnEnable()
            calls[#calls + 1] = name .. ":enable"
        end
        return module
    end

    describe("module registry", function()
        before_each(function()
            boot()
        end)

        it("returns a named table and keeps registration order", function()
            local first = ns:NewModule("Alpha")
            local second = ns:NewModule("Beta")
            assert.are.equal("Alpha", first.name)
            assert.are.same({ first, second }, ns.modules)
        end)

        it("finds modules by name", function()
            local module = ns:NewModule("Alpha")
            assert.are.equal(module, ns:GetModule("Alpha"))
            assert.is_nil(ns:GetModule("Nope"))
        end)

        it("rejects a duplicate name", function()
            ns:NewModule("Alpha")
            assert.has_error(function()
                ns:NewModule("Alpha")
            end)
        end)
    end)

    describe("lifecycle", function()
        it("initialises saved variables then modules on this add-on's ADDON_LOADED only", function()
            boot()
            local calls = {}
            newRecorder("A", calls)
            newRecorder("B", calls)
            mock.frame:Fire("ADDON_LOADED", "SomeOtherAddon")
            assert.are.same({}, calls)
            assert.is_nil(env.WarriorWorkshopDB)
            mock.frame:Fire("ADDON_LOADED", ADDON)
            assert.are.same({ "A:init", "B:init" }, calls)
            assert.are.equal(1, env.WarriorWorkshopDB.schemaVersion)
            assert.are.equal(1, env.WarriorWorkshopCharDB.schemaVersion)
            assert.are.equal(env.WarriorWorkshopDB, ns.DB.GetAccount())
        end)

        it("handles ADDON_LOADED once", function()
            boot()
            local calls = {}
            newRecorder("A", calls)
            mock.frame:Fire("ADDON_LOADED", ADDON)
            mock.frame:Fire("ADDON_LOADED", ADDON)
            assert.are.same({ "A:init" }, calls)
            assert.is_nil(mock.frame.registered.ADDON_LOADED)
        end)

        it("enables modules in order at PLAYER_LOGIN and fills character meta", function()
            boot()
            local calls = {}
            newRecorder("A", calls)
            newRecorder("B", calls)
            mock.frame:Fire("ADDON_LOADED", ADDON)
            assert.are.same({ "A:init", "B:init" }, calls)
            mock.frame:Fire("PLAYER_LOGIN")
            assert.are.same({ "A:init", "B:init", "A:enable", "B:enable" }, calls)
            assert.are.same({ name = "Hugh", realm = "Realm", classFile = "WARRIOR", level = 80 },
                env.WarriorWorkshopCharDB.meta)
        end)

        it("stamps lastSeen at PLAYER_LOGOUT", function()
            boot()
            mock.frame:Fire("ADDON_LOADED", ADDON)
            mock.frame:Fire("PLAYER_LOGIN")
            mock.frame:Fire("PLAYER_LOGOUT")
            assert.are.equal(4242, env.WarriorWorkshopCharDB.meta.lastSeen)
        end)

        it("keeps going when a module errors, and says so", function()
            boot()
            local calls = {}
            local broken = ns:NewModule("Broken")
            function broken:OnInitialize()
                error("init failed")
            end
            newRecorder("Good", calls)
            mock.frame:Fire("ADDON_LOADED", ADDON)
            assert.are.same({ "Good:init" }, calls)
            assert.are.equal(1, #mock.printed)
            assert.is_truthy(string.find(mock.printed[1], "Broken", 1, true))
        end)

        it("preserves saved data and fills in missing defaults", function()
            boot({ WarriorWorkshopDB = dofile("tests/fixtures/saved_account.lua") })
            mock.frame:Fire("ADDON_LOADED", ADDON)
            local account = env.WarriorWorkshopDB
            assert.are.equal(9, account.settings.batchSize)
            assert.is_true(account.settings.hideInCombat)
            assert.are.equal(1500, account.prices[12345].value)
        end)

        it("warns and keeps a backup inside the table when saved data is from a newer version", function()
            boot({ WarriorWorkshopDB = { schemaVersion = 99 } })
            mock.frame:Fire("ADDON_LOADED", ADDON)
            assert.are.equal(1, env.WarriorWorkshopDB.schemaVersion)
            assert.are.equal(99, env.WarriorWorkshopDB._backup.data.schemaVersion)
            assert.are.equal(1, #mock.printed)
            assert.is_truthy(string.find(mock.printed[1], "newer version", 1, true))
            assert.is_nil(env.WarriorWorkshopDB_backup)
        end)
    end)

    describe("slash commands", function()
        before_each(function()
            boot()
        end)

        it("registers /ww", function()
            assert.are.equal("/ww", env.SLASH_WW1)
            assert.is_function(env.SlashCmdList.WW)
        end)

        it("/ww version shows the real schema version", function()
            mock.frame:Fire("ADDON_LOADED", ADDON)
            env.SlashCmdList.WW("version")
            assert.are.equal("Warrior Workshop 0.0.1 - schema 1 - interface 120105 (build 66666)", mock.printed[1])
        end)

        it("/ww version before initialisation says the schema is not available", function()
            env.SlashCmdList.WW("version")
            assert.is_truthy(string.find(mock.printed[1], "schema n/a", 1, true))
        end)

        it("/ww debug toggles the setting and reports it", function()
            mock.frame:Fire("ADDON_LOADED", ADDON)
            env.SlashCmdList.WW("debug")
            assert.is_true(env.WarriorWorkshopDB.settings.debug)
            assert.are.equal("Debug logging is on.", mock.printed[1])
            env.SlashCmdList.WW("  DEBUG ")
            assert.is_false(env.WarriorWorkshopDB.settings.debug)
            assert.are.equal("Debug logging is off.", mock.printed[2])
        end)

        it("other commands say they are not available yet", function()
            mock.frame:Fire("ADDON_LOADED", ADDON)
            env.SlashCmdList.WW("foo")
            env.SlashCmdList.WW("reset confirm")
            assert.are.equal("'/ww foo' is not available yet. Try /ww version.", mock.printed[1])
            assert.are.equal("'/ww reset confirm' is not available yet. Try /ww version.", mock.printed[2])
        end)

        it("keeps settings across a simulated /reload", function()
            mock.frame:Fire("ADDON_LOADED", ADDON)
            env.SlashCmdList.WW("debug")
            local savedAccount, savedCharacter = env.WarriorWorkshopDB, env.WarriorWorkshopCharDB
            boot({ WarriorWorkshopDB = savedAccount, WarriorWorkshopCharDB = savedCharacter })
            mock.frame:Fire("ADDON_LOADED", ADDON)
            assert.is_true(ns.DB.GetSettings().debug)
            assert.is_true(ns.Log.IsDebug())
        end)
    end)
end)

describe("globals", function()
    it("only the saved variables and the slash command are created", function()
        local frame
        local chat = {}
        local stubs = {
            CreateFrame = function()
                frame = H.mockAdapter.newFrame()
                return frame
            end,
            DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chat[#chat + 1] = line
                end,
            },
        }
        -- The real Adapter is loaded here, with only the two stubs above standing in for the client.
        local _, env = H.bootSandbox({ stubs = stubs })
        local before = { SlashCmdList = true, CreateFrame = true, DEFAULT_CHAT_FRAME = true }

        frame:Fire("ADDON_LOADED", ADDON)
        frame:Fire("PLAYER_LOGIN")
        frame:Fire("PLAYER_LOGOUT")
        env.SlashCmdList.WW("version")
        env.SlashCmdList.WW("debug")

        local created = {}
        for key in pairs(env) do
            if not before[key] then
                created[#created + 1] = key
            end
        end
        table.sort(created)
        assert.are.same({ "SLASH_WW1", "WarriorWorkshopCharDB", "WarriorWorkshopDB" }, created)
        assert.are.same({ WW = env.SlashCmdList.WW }, env.SlashCmdList)
        assert.is_true(#chat > 0)
    end)

    it("leaves _G untouched while the Core files load", function()
        local snapshot = {}
        for key in pairs(_G) do
            snapshot[key] = true
        end
        H.bootSandbox({ stubs = { CreateFrame = H.mockAdapter.newFrame } })
        local added = {}
        for key in pairs(_G) do
            if not snapshot[key] then
                added[#added + 1] = tostring(key)
            end
        end
        assert.are.same({}, added)
    end)
end)
