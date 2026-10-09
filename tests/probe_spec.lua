-- Smoke tests for WarriorWorkshopProbe (M1 + M3) against a fake client. They prove the probe loads, every
-- command runs without a Lua error in each mode, and no secret value is ever stored in the saved table.
-- They do not prove anything about Forever's real API (that is what the beta run is for).

local C = dofile("tests/helpers/probe_client.lua")

-- Every command, in an order a real session might use them.
local COMMANDS = {
    "", "help", "status", "prof", "item 12345", "gear", "bags", "ping", "combat on", "spells", "trainer", "tank",
    "chat", "chat say", "chatkey", "sets", "sets 1", "sets 9", "swapbtn", "swapbtn item:11 item:12",
    "swapbtn restore", "macro", "macro keep", "rec off", "rec on", "nonsense", "combat off",
}

local ALLOWED_GLOBALS = {
    WarriorWorkshopProbeDB = true, SLASH_WWPROBE1 = true, BINDING_HEADER_WWPROBE = true,
    BINDING_NAME_WWPROBE_CHATKEY = true, WWProbe_ChatKey = true, WWProbeSwapButton = true,
}

local function boot(mode)
    local client = C.New(mode)
    local before = {}
    for key in pairs(client.env) do
        before[key] = true
    end
    client.before = before
    C.Load(client)
    return client
end

local function db(client)
    return client.env.WarriorWorkshopProbeDB
end

local function runEverything(client)
    for _, command in ipairs(COMMANDS) do
        C.Slash(client, command)
        C.RunTimers(client, 10)
    end
    C.Slash(client, "combat on")
    C.Fire(client, "PLAYER_REGEN_DISABLED")
    C.Tick(client, 3)
    C.Fire(client, "COMBAT_LOG_EVENT_UNFILTERED")
    C.Fire(client, "UNIT_COMBAT", "player", "PARRY", "", 0, 1)
    C.Fire(client, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    C.Fire(client, "ENCOUNTER_START", 1, "Boss", 1, 5)
    C.Tick(client, 2)
    C.Fire(client, "ENCOUNTER_END", 1, "Boss", 1, 5, 1)
    C.Fire(client, "PLAYER_REGEN_ENABLED")
    C.Fire(client, "TRAINER_SHOW")
    C.RunTimers(client, 10)
    client.hardware = true
    client.env.WWProbe_ChatKey()
    client.hardware = false
    C.RunTimers(client, 10)
    local swapButton = client.env.WWProbeSwapButton
    if swapButton then
        swapButton:Click("LeftButton", true)
        C.RunTimers(client, 10)
    end
    C.Slash(client, "clear")
    C.Slash(client, "status")
end

for _, mode in ipairs({ "full", "missing", "secret", "nochecker" }) do
    describe("probe in " .. mode .. " mode", function()
        local client

        before_each(function()
            client = boot(mode)
        end)

        it("loads, registers the slash command and initialises its saved table on PLAYER_LOGIN", function()
            assert.is_function(client.env.SlashCmdList.WWPROBE)
            assert.are.equal("/wwprobe", client.env.SLASH_WWPROBE1)
            local data = db(client)
            assert.are.equal(2, data.probeVersion)
            for _, key in ipairs({ "events", "combat", "cleu", "chat", "bindings", "sets", "swap", "trainer" }) do
                assert.is_truthy(data[key], "missing db." .. key)
            end
        end)

        it("runs every command and event without a Lua error", function()
            assert.has_no.errors(function()
                runEverything(client)
            end)
        end)

        it("records no handler errors", function()
            runEverything(client)
            local errors = db(client).handlerErrors
            assert.is_nil(errors and errors[1], errors and errors[1] and (errors[1].key .. ": " .. errors[1].error))
        end)

        it("never stores a secret value", function()
            runEverything(client)
            assert.is_nil(C.FindSecret(db(client)))
        end)

        it("creates no globals beyond the allowed list", function()
            runEverything(client)
            for key in pairs(client.env) do
                if not client.before[key] then
                    assert.is_true(ALLOWED_GLOBALS[key] == true, "unexpected global " .. tostring(key))
                end
            end
        end)
    end)
end

describe("probe recorder details (full mode)", function()
    local client

    before_each(function()
        client = boot("full")
    end)

    it("records failed event registrations instead of erroring", function()
        local failing = C.New("full")
        failing.forbiddenEvents.COMBAT_LOG_EVENT_UNFILTERED = true
        C.Load(failing)
        local registrations = failing.env.WarriorWorkshopProbeDB.registrations
        assert.is_truthy(type(registrations.COMBAT_LOG_EVENT_UNFILTERED) == "string")
        assert.is_true(registrations.PLAYER_LOGIN)
    end)

    it("keys unit-filtered registrations by event and units", function()
        local registrations = db(client).registrations
        assert.is_true(registrations["UNIT_SPELLCAST_SUCCEEDED@player"])
        assert.is_true(registrations["UNIT_SPELLCAST_START@target"])
        assert.is_true(registrations["UNIT_COMBAT@player,target"])
    end)

    it("samples only in combat or with a hostile target, aggregated per context", function()
        C.Slash(client, "combat on")
        C.Tick(client, 2)
        local openWorld = db(client).combat.byContext.openWorld
        assert.are.equal(2, openWorld.samples) -- hostile target in the stub
        assert.are.same({ 500 }, openWorld.fields.targetHealth.examples)
        assert.are.equal(2, openWorld.fields.targetHealth.readable)
        assert.are.equal(2, openWorld.fields["aura:player:Battle Shout.duration"].readable)
        C.Fire(client, "ENCOUNTER_START", 1, "Boss", 1, 5)
        C.Tick(client, 1)
        assert.are.equal(1, db(client).combat.byContext.encounter.samples)
    end)

    it("records usability transitions for reactive abilities", function()
        C.Slash(client, "combat on")
        C.Tick(client, 3)
        local overpower = {}
        for _, transition in ipairs(db(client).combat.transitions) do
            if transition.key == "usable:Overpower" then
                overpower[#overpower + 1] = transition.value
            end
        end
        assert.are.same({ true, false, true }, overpower) -- the stub toggles Overpower on every call
        assert.are.equal(5, #db(client).combat.transitions) -- plus the first reading of Revenge and Execute
    end)

    it("counts CLEU subevents and miss types", function()
        C.Fire(client, "COMBAT_LOG_EVENT_UNFILTERED")
        local cleu = db(client).cleu
        assert.are.equal(1, cleu.subevents.openWorld.SWING_MISSED)
        assert.are.equal(1, cleu.missTypes.openWorld.PARRY)
        assert.are.equal(1, #cleu.events)
    end)

    it("counts UNIT_COMBAT actions as an avoidance fallback", function()
        C.Fire(client, "UNIT_COMBAT", "player", "DODGE", "", 0, 1)
        C.Fire(client, "UNIT_COMBAT", "focus", "DODGE", "", 0, 1) -- filtered out by the unit filter
        assert.are.equal(1, db(client).unitCombat.openWorld["player:DODGE"])
    end)

    it("judges chat by echoes and blocked events, not by pcall", function()
        C.Slash(client, "chat")
        C.RunTimers(client, 10)
        local byChannel = {}
        for _, attempt in ipairs(db(client).chat.attempts) do
            byChannel[attempt.channel] = attempt
        end
        assert.are.equal("CHAT_MSG_PARTY", byChannel.PARTY.echoed)
        assert.is_nil(byChannel.SAY.echoed)
        assert.are.equal("ADDON_ACTION_BLOCKED:SendChatMessage", byChannel.SAY.blocked)
        assert.are.equal("timer", byChannel.SAY.trigger)
    end)

    it("sends SAY from the key binding and counts the press", function()
        client.hardware = true
        client.env.WWProbe_ChatKey()
        local attempt = db(client).chat.attempts[1]
        assert.are.equal("key", attempt.trigger)
        assert.are.equal("CHAT_MSG_SAY", attempt.echoed)
        assert.are.equal(1, db(client).bindings.pressed)
        assert.are.equal(1, #db(client).bindings.checks) -- the login check (V-30 persistence)
    end)

    it("applies an equipment set and checks the slots afterwards", function()
        C.Slash(client, "sets 2")
        C.RunTimers(client, 2)
        local attempt = db(client).sets.attempts[1]
        assert.are.equal(2, attempt.setID)
        assert.are.equal(1, attempt.matched)
        assert.are.equal(1, attempt.total)
    end)

    it("builds the swap button with key-down clicks and remembers the previous binding", function()
        C.Slash(client, "swapbtn |cff|Hitem:11::|h[Big Sword]|h|r |cff|Hitem:12::|h[Shield]|h|r")
        local button = client.env.WWProbeSwapButton
        assert.are.equal("macro", button.attributes.type)
        assert.are.equal("/equipslot 16 item:11\n/equipslot 17 item:12", button.attributes.macrotext)
        assert.are.same({ "AnyUp", "AnyDown" }, button.clicks)
        assert.are.equal("", db(client).swap.previousAction)
        button:Click("LeftButton", true)
        assert.are.equal(1, #db(client).swap.clicks)
    end)

    it("refuses to build the swap button in combat", function()
        client.inCombatLockdown = true
        C.Slash(client, "swapbtn item:11")
        assert.is_nil(client.env.WWProbeSwapButton)
    end)

    it("creates, edits and deletes the test macro", function()
        C.Slash(client, "macro")
        local macro = db(client).macro
        assert.are.equal(121, macro.index)
        assert.is_true(macro.edit.ok)
        assert.is_truthy(macro.delete)
    end)

    it("dumps spells, named abilities and stances", function()
        C.Slash(client, "spells")
        local spells = db(client).spells
        assert.are.equal(6, #spells.items)
        assert.are.equal(3, #spells.stances.forms)
        assert.are.equal(100, spells.named.Charge.info.returns[1].spellID)
    end)
end)
