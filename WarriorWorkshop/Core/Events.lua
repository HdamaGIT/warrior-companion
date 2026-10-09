local addonName, ns = ...

-- Event bus. Game events are received on one frame from the Adapter (D-012) and registered lazily on the
-- first subscription. Internal messages are prefixed WW_ and are never registered on the frame.
local L = ns.L
local Events = { subscribers = {}, rawRegistered = {}, pending = {} }
ns.Events = Events

local function isInternal(event)
    return string.sub(event, 1, 3) == "WW_"
end

local function getFrame()
    if Events.frame == nil then
        local frame = ns.Adapter.CreateEventFrame()
        if frame then
            frame:SetScript("OnEvent", function(_, event, ...)
                Events:Dispatch(event, ...)
            end)
            Events.frame = frame
        end
    end
    return Events.frame
end

--- Subscribes module:methodName to a game event or a WW_ message.
-- Subscribing the same module and method twice is a no-op.
-- @param event string game event or WW_* message
-- @param module table receiver; the handler is called as module[methodName](module, ...)
-- @param methodName string
-- Side effects: registers the raw event on the shared frame the first time it is subscribed.
function Events:On(event, module, methodName)
    local list = self.subscribers[event]
    if not list then
        list = {}
        self.subscribers[event] = list
    end
    for _, subscription in ipairs(list) do
        if subscription.module == module and subscription.method == methodName then
            return
        end
    end
    list[#list + 1] = { module = module, method = methodName }
    if not isInternal(event) and not self.rawRegistered[event] then
        local frame = getFrame()
        if frame then
            if pcall(frame.RegisterEvent, frame, event) then
                self.rawRegistered[event] = true
            else
                ns.Log.WarnOnce("event:" .. event, string.format(L.EVENT_REGISTER_FAILED, event))
            end
        end
    end
end

--- Removes every subscription a module has for an event; unregisters the raw event when none remain.
-- @param event string
-- @param module table
function Events:Off(event, module)
    local list = self.subscribers[event]
    if not list then
        return
    end
    for index = #list, 1, -1 do
        if list[index].module == module then
            table.remove(list, index)
        end
    end
    if #list == 0 then
        self.subscribers[event] = nil
        if self.rawRegistered[event] and self.frame then
            pcall(self.frame.UnregisterEvent, self.frame, event)
            self.rawRegistered[event] = nil
        end
    end
end

--- Calls every subscriber of an event with the given arguments. A failing handler is logged and does not
-- stop the others. Subscribers added or removed during dispatch take effect from the next dispatch.
-- @param event string
-- @param ... arguments passed to handlers unchanged (never inspected here)
-- @return number of handlers that ran without error
function Events:Dispatch(event, ...)
    local list = self.subscribers[event]
    if not list then
        return 0
    end
    local snapshot = {}
    for index, subscription in ipairs(list) do
        snapshot[index] = subscription
    end
    local succeeded = 0
    for _, subscription in ipairs(snapshot) do
        local module, method = subscription.module, subscription.method
        local handler = module[method]
        local label = tostring(module.name or method)
        if type(handler) ~= "function" then
            ns.Log.WarnOnce("missing:" .. event .. ":" .. tostring(method),
                string.format(L.HANDLER_MISSING, tostring(method), event))
        else
            local ok, err = pcall(handler, module, ...)
            if ok then
                succeeded = succeeded + 1
            else
                ns.Log.WarnOnce("handler:" .. event .. ":" .. tostring(method),
                    string.format(L.HANDLER_ERROR, label, event, tostring(err)))
                ns.Log.Debug(tostring(err))
            end
        end
    end
    return succeeded
end

--- Publishes an internal WW_* message to its subscribers.
-- @param message string, e.g. "WW_INVENTORY_CHANGED"
-- @param ... arguments passed to handlers
-- @return number of handlers that ran without error
function Events:Fire(message, ...)
    return self:Dispatch(message, ...)
end

--- Collapses a burst of calls into one run, delay seconds after the first call (trailing edge, no restart).
-- Later calls with the same key before it runs replace the stored function.
-- @param key string identifying the burst
-- @param delay number seconds
-- @param fn function run once with no arguments; errors are logged
-- Side effects: schedules a timer via Adapter.After.
function Events:Debounce(key, delay, fn)
    local entry = self.pending[key]
    if entry then
        entry.fn = fn
        return
    end
    self.pending[key] = { fn = fn }
    if not ns.Adapter.After(delay, function()
        local due = self.pending[key]
        self.pending[key] = nil
        if due then
            local ok, err = pcall(due.fn)
            if not ok then
                ns.Log.WarnOnce("debounce:" .. key, string.format(L.HANDLER_ERROR, key, "debounce", tostring(err)))
            end
        end
    end) then
        self.pending[key] = nil
    end
end
