local addonName, ns = ...

-- Pure helpers. No WoW globals; safe to unit test directly.
local L = ns.L
local Util = {}
ns.Util = Util

--- Deep-copies a value. Tables are copied recursively (cycles preserved); metatables are not copied.
-- @param value any
-- @param seen table|nil internal cycle map
-- @return a copy of value (non-table values are returned unchanged)
function Util.DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[key] = Util.DeepCopy(item, seen)
    end
    return copy
end

--- Fills missing keys in target from defaults, recursively. Existing values are never overwritten,
-- including when the user's value has a different type from the default.
-- @param target table modified in place
-- @param defaults table read only; copied before insertion
-- @return target
function Util.MergeDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        local current = target[key]
        if current == nil then
            target[key] = Util.DeepCopy(defaultValue)
        elseif type(current) == "table" and type(defaultValue) == "table" then
            Util.MergeDefaults(current, defaultValue)
        end
    end
    return target
end

--- Appends to an array used as a ring buffer; the oldest entries are dropped beyond cap.
-- @param buffer table array, modified in place
-- @param value any appended value
-- @param cap number maximum length
-- @return buffer
function Util.RingPush(buffer, value, cap)
    buffer[#buffer + 1] = value
    local count = #buffer
    local excess = count - cap
    if excess > 0 then
        for index = 1, count - excess do
            buffer[index] = buffer[index + excess]
        end
        for index = count - excess + 1, count do
            buffer[index] = nil
        end
    end
    return buffer
end

--- Trims whitespace from both ends of a string.
-- @param text string
-- @return string
function Util.Trim(text)
    return (string.match(text, "^%s*(.-)%s*$"))
end

--- Splits a string on a plain (non-pattern) separator. Empty fields are kept.
-- @param text string
-- @param separator string; an empty separator returns the whole string as one field
-- @return array of strings
function Util.Split(text, separator)
    if separator == nil or separator == "" then
        return { text }
    end
    local parts = {}
    local start = 1
    while true do
        local first, last = string.find(text, separator, start, true)
        if not first then
            parts[#parts + 1] = string.sub(text, start)
            break
        end
        parts[#parts + 1] = string.sub(text, start, first - 1)
        start = last + 1
    end
    return parts
end

--- Formats integer copper as plain text, e.g. 12345 -> "1g 23s 45c". Zero units are omitted.
-- @param copper number (fractions are floored); negative values get a leading "-"
-- @return string; "0c" for zero
function Util.FormatMoney(copper)
    local amount = math.floor(tonumber(copper) or 0)
    local negative = amount < 0
    if negative then
        amount = -amount
    end
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local rest = amount % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = string.format(L.MONEY_GOLD, gold)
    end
    if silver > 0 then
        parts[#parts + 1] = string.format(L.MONEY_SILVER, silver)
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = string.format(L.MONEY_COPPER, rest)
    end
    return (negative and "-" or "") .. table.concat(parts, " ")
end
