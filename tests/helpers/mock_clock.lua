-- Manual clock for tests: a session time (GetTime-like) and one-shot timers that run when the clock is advanced.
-- No WoW globals are involved. Used by mock_adapter.lua (Adapter.Now / Adapter.After) and the replay harness.
local M = {}

--- Creates a clock.
-- @param start number|nil initial time in seconds (default 0)
-- @return clock with fields now and methods after, advance, advanceTo, flush, pending
function M.new(start)
    local clock = { now = start or 0, timers = {}, seq = 0 }

    --- Schedules fn to run once, delay seconds from now. Timers due at the same time run in scheduling order.
    function clock.after(delay, fn)
        clock.seq = clock.seq + 1
        clock.timers[#clock.timers + 1] = { due = clock.now + delay, seq = clock.seq, fn = fn }
    end

    -- Removes and returns the earliest timer due at or before limit (any timer if limit is nil).
    local function popEarliest(limit)
        local best
        for index, timer in ipairs(clock.timers) do
            if limit == nil or timer.due <= limit then
                local current = best and clock.timers[best]
                if not current or timer.due < current.due or (timer.due == current.due and timer.seq < current.seq) then
                    best = index
                end
            end
        end
        if best then
            return table.remove(clock.timers, best)
        end
        return nil
    end

    --- Moves the clock to an absolute time, running every timer that falls due (timers may schedule more).
    function clock.advanceTo(target)
        local timer = popEarliest(target)
        while timer do
            clock.now = math.max(clock.now, timer.due)
            timer.fn()
            timer = popEarliest(target)
        end
        if target > clock.now then
            clock.now = target
        end
    end

    --- Moves the clock forward by seconds.
    function clock.advance(seconds)
        clock.advanceTo(clock.now + seconds)
    end

    --- Runs every pending timer, moving the clock to each one's due time.
    function clock.flush()
        local timer = popEarliest(nil)
        while timer do
            clock.now = math.max(clock.now, timer.due)
            timer.fn()
            timer = popEarliest(nil)
        end
    end

    --- Number of timers not yet run.
    function clock.pending()
        return #clock.timers
    end

    return clock
end

return M
