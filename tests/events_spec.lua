local H = dofile("tests/helpers/load_addon.lua")

describe("events", function()
    local ns, mock, Events

    local function newReceiver(name)
        local receiver = { name = name, calls = {} }
        function receiver:Handle(...)
            self.calls[#self.calls + 1] = { ... }
        end
        return receiver
    end

    before_each(function()
        mock = H.mockAdapter.new()
        ns = H.newNs({ "Locale/enUS.lua", "Core/Util.lua", "Core/Log.lua", "Core/Events.lua" }, { adapter = mock })
        Events = ns.Events
    end)

    describe("subscription", function()
        it("creates the frame and registers a game event only on first subscription", function()
            assert.are.equal(0, #mock.frames)
            Events:On("BAG_UPDATE_DELAYED", newReceiver("a"), "Handle")
            assert.are.equal(1, #mock.frames)
            assert.is_true(mock.frame.registered.BAG_UPDATE_DELAYED)
        end)

        it("registers a game event once however many subscribers there are", function()
            Events:On("BAG_UPDATE_DELAYED", newReceiver("a"), "Handle")
            Events:On("BAG_UPDATE_DELAYED", newReceiver("b"), "Handle")
            assert.are.equal(1, #mock.frame.registerCalls)
            assert.are.equal(1, #mock.frames)
        end)

        it("never registers internal WW_ messages on the frame", function()
            Events:On("WW_INVENTORY_CHANGED", newReceiver("a"), "Handle")
            assert.are.equal(0, #mock.frames)
        end)

        it("ignores a duplicate subscription", function()
            local receiver = newReceiver("a")
            Events:On("WW_X", receiver, "Handle")
            Events:On("WW_X", receiver, "Handle")
            Events:Fire("WW_X")
            assert.are.equal(1, #receiver.calls)
        end)

        it("warns once and carries on when the client rejects an event", function()
            local frame = H.mockAdapter.newFrame()
            frame.rejectEvents = { NOT_A_REAL_EVENT = true }
            mock.CreateEventFrame = function()
                return frame
            end
            local receiver = newReceiver("a")
            assert.has_no.errors(function()
                Events:On("NOT_A_REAL_EVENT", receiver, "Handle")
                Events:On("NOT_A_REAL_EVENT", newReceiver("b"), "Handle")
            end)
            assert.is_nil(frame.registered.NOT_A_REAL_EVENT)
            assert.are.equal(1, #mock.printed)
        end)
    end)

    describe("dispatch", function()
        it("delivers a game event to module:method with its arguments", function()
            local receiver = newReceiver("a")
            Events:On("PLAYER_EQUIPMENT_CHANGED", receiver, "Handle")
            mock.frame:Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
            assert.are.equal(1, #receiver.calls)
            assert.are.same({ 16, true }, receiver.calls[1])
        end)

        it("delivers internal messages with Fire and reports how many handlers ran", function()
            local first, second = newReceiver("a"), newReceiver("b")
            Events:On("WW_INVENTORY_CHANGED", first, "Handle")
            Events:On("WW_INVENTORY_CHANGED", second, "Handle")
            assert.are.equal(2, Events:Fire("WW_INVENTORY_CHANGED", "bags"))
            assert.are.same({ "bags" }, first.calls[1])
            assert.are.same({ "bags" }, second.calls[1])
        end)

        it("does nothing for an event with no subscribers", function()
            assert.are.equal(0, Events:Fire("WW_NOBODY"))
        end)

        it("keeps dispatching when a handler errors, and warns once", function()
            local bad = { name = "Bad" }
            function bad.Explode()
                error("kaboom")
            end
            local good = newReceiver("Good")
            Events:On("WW_X", bad, "Explode")
            Events:On("WW_X", good, "Handle")
            assert.are.equal(1, Events:Fire("WW_X"))
            Events:Fire("WW_X")
            assert.are.equal(2, #good.calls)
            assert.are.equal(1, #mock.printed)
            assert.is_truthy(string.find(mock.printed[1], "kaboom", 1, true))
        end)

        it("warns once when the named method does not exist", function()
            Events:On("WW_X", { name = "Empty" }, "Missing")
            assert.has_no.errors(function()
                Events:Fire("WW_X")
                Events:Fire("WW_X")
            end)
            assert.are.equal(1, #mock.printed)
        end)

        it("lets a handler unsubscribe itself mid-dispatch without skipping others", function()
            local later = newReceiver("later")
            local once = { name = "once" }
            function once:Handle()
                Events:Off("WW_X", self)
            end
            Events:On("WW_X", once, "Handle")
            Events:On("WW_X", later, "Handle")
            Events:Fire("WW_X")
            Events:Fire("WW_X")
            assert.are.equal(2, #later.calls)
        end)
    end)

    describe("Off", function()
        it("stops delivery and unregisters the raw event when nobody is left", function()
            local receiver = newReceiver("a")
            Events:On("PLAYER_LOGIN", receiver, "Handle")
            Events:Off("PLAYER_LOGIN", receiver)
            mock.frame:Fire("PLAYER_LOGIN")
            assert.are.equal(0, #receiver.calls)
            assert.is_nil(mock.frame.registered.PLAYER_LOGIN)
        end)

        it("keeps the raw event registered while another module still listens", function()
            local first, second = newReceiver("a"), newReceiver("b")
            Events:On("PLAYER_LOGIN", first, "Handle")
            Events:On("PLAYER_LOGIN", second, "Handle")
            Events:Off("PLAYER_LOGIN", first)
            assert.is_true(mock.frame.registered.PLAYER_LOGIN)
            mock.frame:Fire("PLAYER_LOGIN")
            assert.are.equal(0, #first.calls)
            assert.are.equal(1, #second.calls)
        end)

        it("ignores an event that has no subscribers", function()
            assert.has_no.errors(function()
                Events:Off("WW_NOBODY", newReceiver("a"))
            end)
        end)
    end)

    describe("Debounce", function()
        it("collapses a burst into one call after the delay", function()
            local runs = 0
            for _ = 1, 5 do
                Events:Debounce("bags", 0.5, function()
                    runs = runs + 1
                end)
            end
            mock.advance(0.4)
            assert.are.equal(0, runs)
            mock.advance(0.2)
            assert.are.equal(1, runs)
            mock.flush()
            assert.are.equal(1, runs)
        end)

        it("runs the most recently supplied function", function()
            local ran = {}
            Events:Debounce("k", 1, function()
                ran[#ran + 1] = "first"
            end)
            Events:Debounce("k", 1, function()
                ran[#ran + 1] = "second"
            end)
            mock.flush()
            assert.are.same({ "second" }, ran)
        end)

        it("can fire again for a later burst", function()
            local runs = 0
            local function bump()
                runs = runs + 1
            end
            Events:Debounce("k", 0.5, bump)
            mock.flush()
            Events:Debounce("k", 0.5, bump)
            mock.flush()
            assert.are.equal(2, runs)
        end)

        it("keeps keys independent", function()
            local ran = {}
            Events:Debounce("a", 0.5, function()
                ran[#ran + 1] = "a"
            end)
            Events:Debounce("b", 0.5, function()
                ran[#ran + 1] = "b"
            end)
            mock.flush()
            assert.are.same({ "a", "b" }, ran)
        end)

        it("logs a failing function instead of throwing", function()
            Events:Debounce("k", 0.5, function()
                error("late failure")
            end)
            assert.has_no.errors(function()
                mock.flush()
            end)
            assert.are.equal(1, #mock.printed)
        end)

        it("does not get stuck if the timer API is unavailable", function()
            local runs = 0
            local function bump()
                runs = runs + 1
            end
            mock.failAfter = true
            Events:Debounce("k", 0.5, bump)
            mock.failAfter = false
            Events:Debounce("k", 0.5, bump)
            mock.flush()
            assert.are.equal(1, runs)
        end)
    end)
end)
