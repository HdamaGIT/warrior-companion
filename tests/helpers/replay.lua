-- Replay harness (SPEC_V2 §13, D-048): feeds a recorded event stream into the add-on through the mock adapter's
-- event frame, on the mock clock. Streams live in tests/fixtures/streams/*.lua and look like:
--
--   return {
--     name = "...", source = "where the timings came from",
--     start = { data = { ... } },               -- merged into mock.data before the first entry
--     events = {
--       { t = 0.0, event = "PLAYER_REGEN_DISABLED", data = { inCombat = true } },
--       { t = 1.3, event = "UNIT_COMBAT", args = { "player", "PARRY", "", 0, 1 } },
--       { t = 2.0, data = { combat = { autoAttacking = false } } },   -- state change only
--     },
--   }
--
-- Times are seconds from the start of the stream. For each entry the clock advances to start + t (running due
-- timers, such as the combat ticker), then `data` is merged into mock.data (so handlers already see the new state),
-- then the event fires. Replay.CLEAR as a data value removes that key.
local R = {}

R.CLEAR = setmetatable({}, { __tostring = function()
    return "Replay.CLEAR"
end })

local function merge(target, source)
    for key, value in pairs(source) do
        if value == R.CLEAR then
            target[key] = nil
        elseif type(value) == "table" and type(target[key]) == "table" then
            merge(target[key], value)
        elseif type(value) == "table" then
            local copy = {}
            merge(copy, value)
            target[key] = copy
        else
            target[key] = value
        end
    end
end
R.merge = merge

--- Loads a stream fixture by name.
-- @param name string file name under tests/fixtures/streams/ without .lua
-- @return stream table
function R.load(name)
    return dofile("tests/fixtures/streams/" .. name .. ".lua")
end

--- Replays a stream.
-- @param mock table mock adapter (tests/helpers/mock_adapter.lua) whose event frame the add-on registered on
-- @param stream table stream (see above) or a fixture name
-- @param opts table|nil { frame = event frame (default mock.frame), after = function(entry, index) called after
--   each entry, offset = seconds added to every t (default: current clock), tail = seconds to advance after the last
--   entry (default 0) }
-- @return number of entries replayed
function R.run(mock, stream, opts)
    opts = opts or {}
    if type(stream) == "string" then
        stream = R.load(stream)
    end
    local frame = opts.frame or mock.frame
    local base = opts.offset or mock.Now()
    if stream.start and stream.start.data then
        merge(mock.data, stream.start.data)
    end
    for index, entry in ipairs(stream.events) do
        mock.clockObj.advanceTo(base + entry.t)
        if entry.data then
            merge(mock.data, entry.data)
        end
        if entry.event then
            local args = entry.args or {}
            frame:Fire(entry.event, unpack(args, 1, entry.n or #args))
        end
        if opts.after then
            opts.after(entry, index)
        end
    end
    if opts.tail then
        mock.advance(opts.tail)
    end
    return #stream.events
end

return R
