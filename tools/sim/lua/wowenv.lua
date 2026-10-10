-- luacheck: ignore (simulator and fixture code defines WoW globals on purpose; see D-011)
-- Headless WoW client simulator: engine (D-011).
-- Provides the Lua extensions, frames, event dispatch, timers, slash commands, chat log,
-- add-on loading and SavedVariables lifecycle. Data APIs live in api.lua.
-- Returns a function(world) that installs the environment into _G and returns the `sim` table.
-- Not linted: it defines WoW globals on purpose.

return function(world)
    local G = _G
    local sim = {
        world = world,
        chat = {},
        errors = {},
        frames = {},
        timers = {},
        timerSeq = 0,
        now = world.time or 1000,
        meta = {},
        loaded = {},
        loadedNames = {},
        registered = {},
        apiUsed = {},
        stubbed = {},
        templates = {},
    }

    local errorHandler = function(e) return e end

    local function safecall(fn, ...)
        local n, args = select("#", ...), { ... }
        local ok, err = xpcall(function()
            return fn(unpack(args, 1, n))
        end, function(e)
            return tostring(e) .. "\n" .. debug.traceback("", 2)
        end)
        if not ok then
            sim.errors[#sim.errors + 1] = err
            pcall(errorHandler, err)
        end
        return ok, err
    end
    sim.safecall = safecall

    ---------------------------------------------------------------- Lua extensions WoW provides
    G.time = os.time
    G.date = os.date
    G.format = string.format
    G.tinsert = table.insert
    G.tremove = table.remove
    G.debugstack = function() return debug.traceback("", 2) end
    G.geterrorhandler = function() return errorHandler end
    G.seterrorhandler = function(fn) errorHandler = fn end
    G.GetTime = function() return sim.now end

    function G.wipe(t)
        for k in pairs(t) do
            t[k] = nil
        end
        return t
    end

    function G.strjoin(delim, ...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        return table.concat(parts, delim)
    end

    function G.strtrim(s, chars)
        local set = chars and ("[" .. (chars:gsub("[%]%^%-%%]", "%%%0")) .. "]") or "%s"
        return (s:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
    end

    function G.strsplit(delim, str, pieces)
        local set = "[" .. (delim:gsub("[%]%^%-%%]", "%%%0")) .. "]"
        local out, pos = {}, 1
        while true do
            if pieces and #out == pieces - 1 then
                out[#out + 1] = str:sub(pos)
                break
            end
            local s = str:find(set, pos)
            if not s then
                out[#out + 1] = str:sub(pos)
                break
            end
            out[#out + 1] = str:sub(pos, s - 1)
            pos = s + 1
        end
        return unpack(out)
    end

    ---------------------------------------------------------------- Chat
    local function addChat(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        sim.chat[#sim.chat + 1] = table.concat(parts, " ")
    end

    G.print = addChat
    G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) addChat(msg) end,
    }

    ---------------------------------------------------------------- Frames
    local frameMethods = {}
    local noop = function() end
    local frameMT = {
        -- Unknown PascalCase methods are harmless no-ops (recorded in sim.stubbed so tests can see them).
        -- Unknown lowercase fields are nil, as on real frames.
        __index = function(_, key)
            local method = frameMethods[key]
            if method then
                return method
            end
            if type(key) == "string" and key:match("^%u") then
                sim.stubbed[key] = true
                return noop
            end
        end,
    }

    local function newFrame(frameType, name, parent, template)
        local frame = setmetatable({
            _type = frameType or "Frame",
            _name = name,
            _parent = parent,
            _template = template,
            _events = {},
            _scripts = {},
            _shown = true,
            _points = {},
            _id = #sim.frames + 1,
        }, frameMT)
        if template then
            sim.templates[template] = true
        end
        if name then
            G[name] = frame
        end
        sim.frames[#sim.frames + 1] = frame
        return frame
    end

    local function runScript(frame, scriptName, ...)
        local script = frame._scripts[scriptName]
        if script then
            safecall(script, frame, ...)
        end
    end

    local function registerEvent(self, event)
        if world.rejectEvents and world.rejectEvents[event] then
            error('Frame:RegisterEvent(): Attempt to register unknown event "' .. tostring(event) .. '"', 2)
        end
        self._events[event] = true
        sim.registered[event] = true
    end

    frameMethods.RegisterEvent = registerEvent
    frameMethods.RegisterUnitEvent = registerEvent
    function frameMethods.UnregisterEvent(self, event) self._events[event] = nil end
    function frameMethods.UnregisterAllEvents(self) self._events = {} end
    function frameMethods.IsEventRegistered(self, event) return self._events[event] == true end
    function frameMethods.SetScript(self, name, fn) self._scripts[name] = fn end
    function frameMethods.GetScript(self, name) return self._scripts[name] end
    function frameMethods.HookScript(self, name, fn)
        local previous = self._scripts[name]
        self._scripts[name] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end
    function frameMethods.GetName(self) return self._name end
    function frameMethods.GetObjectType(self) return self._type end
    function frameMethods.GetParent(self) return self._parent end
    function frameMethods.IsShown(self) return self._shown end
    function frameMethods.Show(self)
        if not self._shown then
            self._shown = true
            runScript(self, "OnShow")
        end
    end
    function frameMethods.Hide(self)
        if self._shown then
            self._shown = false
            runScript(self, "OnHide")
        end
    end
    function frameMethods.SetShown(self, shown)
        if shown then self:Show() else self:Hide() end
    end
    function frameMethods.CreateFontString(self, name, _, inherits)
        -- `inherits` here names a font object (GameFontNormal...), not a frame template.
        local fontString = newFrame("FontString", name, self)
        if type(inherits) == "string" then
            fontString._fontObject = inherits
        end
        return fontString
    end
    function frameMethods.CreateTexture(self, name, _, inherits)
        return newFrame("Texture", name, self, inherits)
    end

    ---------------------------------------------------------------- Layout recording (visual preview)
    -- Recorded only; tools/sim/preview.py resolves anchors and draws the HTML snapshot.
    -- SetPoint accepts the client forms: (point), (point, x, y), (point, relativeTo),
    -- (point, relativeTo, relativePoint), (point, relativeTo, relativePoint, x, y).
    function frameMethods.SetPoint(self, point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if type(a) == "number" then
            x, y = a, b
        else
            relativeTo, relativePoint = a, b
            if type(relativePoint) == "number" then
                relativePoint, x, y = nil, b, c
            else
                x, y = c, d
            end
        end
        if type(relativeTo) == "string" then
            relativeTo = G[relativeTo]
        end
        point = point:upper()
        for i, existing in ipairs(self._points) do
            if existing.point == point then
                table.remove(self._points, i)
                break
            end
        end
        self._points[#self._points + 1] = {
            point = point,
            relativeTo = relativeTo or false, -- false means the parent, or the screen when parentless
            relativePoint = (relativePoint or point):upper(),
            x = x or 0,
            y = y or 0,
        }
    end
    function frameMethods.ClearAllPoints(self) self._points = {} end
    function frameMethods.SetAllPoints(self, relativeTo)
        self._points = {}
        frameMethods.SetPoint(self, "TOPLEFT", relativeTo or false, "TOPLEFT", 0, 0)
        frameMethods.SetPoint(self, "BOTTOMRIGHT", relativeTo or false, "BOTTOMRIGHT", 0, 0)
    end
    function frameMethods.GetNumPoints(self) return #self._points end
    function frameMethods.SetSize(self, w, h) self._width, self._height = w, h end
    function frameMethods.SetWidth(self, w) self._width = w end
    function frameMethods.SetHeight(self, h) self._height = h end
    function frameMethods.GetWidth(self) return self._width or 0 end
    function frameMethods.GetHeight(self) return self._height or 0 end
    function frameMethods.GetSize(self) return self._width or 0, self._height or 0 end
    function frameMethods.SetText(self, text)
        if text == nil then self._text = nil else self._text = tostring(text) end
    end
    function frameMethods.SetFormattedText(self, fmt, ...) self._text = string.format(fmt, ...) end
    function frameMethods.GetText(self) return self._text end
    function frameMethods.SetTextColor(self, r, g, b, a) self._textColor = { r, g, b, a or 1 } end
    function frameMethods.SetJustifyH(self, justify) self._justifyH = justify end
    function frameMethods.SetFont(self, _, size) self._fontSize = size end
    function frameMethods.SetFontObject(self, fontObject)
        if type(fontObject) == "string" then self._fontObject = fontObject end
    end
    function frameMethods.SetColorTexture(self, r, g, b, a) self._color = { r, g, b, a or 1 } end
    function frameMethods.SetVertexColor(self, r, g, b, a) self._vertexColor = { r, g, b, a or 1 } end
    function frameMethods.SetTexture(self, texture)
        if type(texture) == "number" or type(texture) == "string" then
            self._texture = texture
        end
    end
    function frameMethods.SetAtlas(self, atlas) self._texture = atlas end
    function frameMethods.SetBackdropColor(self, r, g, b, a) self._backdropColor = { r, g, b, a or 1 } end
    function frameMethods.SetBackdropBorderColor(self, r, g, b, a) self._borderColor = { r, g, b, a or 1 } end
    function frameMethods.SetAlpha(self, alpha) self._alpha = alpha end
    function frameMethods.GetAlpha(self) return self._alpha or 1 end
    function frameMethods.SetFrameStrata(self, strata) self._strata = strata end
    function frameMethods.GetFrameStrata(self) return self._strata or "MEDIUM" end
    function frameMethods.SetFrameLevel(self, level) self._level = level end
    function frameMethods.SetParent(self, parent) self._parent = parent end
    function frameMethods.SetValue(self, value) self._value = value end
    function frameMethods.GetValue(self) return self._value end
    function frameMethods.SetMinMaxValues(self, minValue, maxValue) self._min, self._max = minValue, maxValue end
    function frameMethods.SetStatusBarColor(self, r, g, b, a) self._barColor = { r, g, b, a or 1 } end

    local function isVisible(frame)
        while frame do
            if not frame._shown then
                return false
            end
            frame = frame._parent
        end
        return true
    end
    function frameMethods.IsVisible(self) return isVisible(self) end

    --- Exports every frame's recorded layout as plain tables for the preview renderer.
    function sim.dumpFrames()
        local out = {}
        for _, f in ipairs(sim.frames) do
            local points = {}
            for i, p in ipairs(f._points) do
                points[i] = {
                    point = p.point,
                    relativeTo = p.relativeTo and p.relativeTo._id or nil,
                    relativePoint = p.relativePoint,
                    x = p.x,
                    y = p.y,
                }
            end
            out[#out + 1] = {
                id = f._id, type = f._type, name = f._name, template = f._template,
                parent = f._parent and f._parent._id or nil,
                shown = f._shown, visible = isVisible(f),
                width = f._width, height = f._height, points = points,
                text = f._text, textColor = f._textColor, justifyH = f._justifyH,
                fontSize = f._fontSize, fontObject = f._fontObject,
                color = f._color, vertexColor = f._vertexColor,
                texture = f._texture and tostring(f._texture) or nil,
                backdropColor = f._backdropColor, borderColor = f._borderColor,
                alpha = f._alpha, strata = f._strata, level = f._level,
                value = f._value, min = f._min, max = f._max, barColor = f._barColor,
            }
        end
        return out
    end

    G.CreateFrame = function(frameType, name, parent, template)
        return newFrame(frameType, name, parent, template)
    end
    G.UIParent = newFrame("Frame", "UIParent")
    G.UIParent:SetSize(world.screen and world.screen.width or 1920, world.screen and world.screen.height or 1080)
    G.GameTooltip = newFrame("GameTooltip", "GameTooltip", G.UIParent)

    --- Delivers a game event to every frame registered for it.
    function sim.fire(event, ...)
        local targets = {}
        for i, frame in ipairs(sim.frames) do
            targets[i] = frame
        end
        for _, frame in ipairs(targets) do
            if frame._events[event] then
                runScript(frame, "OnEvent", event, ...)
            end
        end
    end

    ---------------------------------------------------------------- Timers (simulated clock)
    G.C_Timer = {
        After = function(seconds, fn)
            sim.timerSeq = sim.timerSeq + 1
            sim.timers[#sim.timers + 1] = { due = sim.now + seconds, seq = sim.timerSeq, fn = fn }
        end,
    }

    --- Advances the simulated clock, running due timers in order.
    function sim.advance(seconds)
        local target = sim.now + seconds
        while true do
            local best, bestIndex
            for i, timer in ipairs(sim.timers) do
                if timer.due <= target
                    and (not best or timer.due < best.due or (timer.due == best.due and timer.seq < best.seq)) then
                    best, bestIndex = timer, i
                end
            end
            if not best then
                break
            end
            table.remove(sim.timers, bestIndex)
            if best.due > sim.now then
                sim.now = best.due
            end
            safecall(best.fn)
        end
        sim.now = target
    end

    ---------------------------------------------------------------- Slash commands
    G.SlashCmdList = {}

    --- Runs a typed slash command line. Returns true if a registered command handled it.
    function sim.slash(line)
        local command, rest = line:match("^(/%S+)%s*(.*)$")
        if not command then
            return false
        end
        command = command:lower()
        for key, handler in pairs(G.SlashCmdList) do
            local i = 1
            while G["SLASH_" .. key .. i] do
                if G["SLASH_" .. key .. i]:lower() == command then
                    safecall(handler, rest, {})
                    return true
                end
                i = i + 1
            end
        end
        return false
    end

    ---------------------------------------------------------------- SavedVariables
    local function isSerialisable(value)
        local t = type(value)
        return t == "number" or t == "string" or t == "boolean" or t == "table"
    end

    local function keyLess(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta == "number"
        end
        return a < b
    end

    local function serialise(value, depth)
        local t = type(value)
        if t == "number" then
            if value ~= value or value == math.huge or value == -math.huge then
                return "0"
            end
            if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
                return string.format("%d", value)
            end
            return string.format("%.17g", value)
        elseif t == "string" then
            return string.format("%q", value)
        elseif t == "boolean" then
            return tostring(value)
        end
        if depth > 60 then
            error("SavedVariables: table too deep or cyclic")
        end
        local keys = {}
        for k, v in pairs(value) do
            if (type(k) == "string" or type(k) == "number") and isSerialisable(v) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, keyLess)
        local pad = string.rep("    ", depth + 1)
        local lines = {}
        for _, k in ipairs(keys) do
            local keyText = type(k) == "number" and ("[" .. serialise(k, depth) .. "]") or ("[" .. string.format("%q", k) .. "]")
            lines[#lines + 1] = pad .. keyText .. " = " .. serialise(value[k], depth + 1) .. ","
        end
        if #lines == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(lines, "\n") .. "\n" .. string.rep("    ", depth) .. "}"
    end

    local function readFile(path)
        local handle = io.open(path, "rb")
        if not handle then
            return nil
        end
        local text = handle:read("*a")
        handle:close()
        if text:sub(1, 3) == "\239\187\191" then
            text = text:sub(4)
        end
        return text
    end

    local function svPath(scopeDir, addonName)
        return scopeDir .. "/" .. addonName .. ".lua"
    end

    local function loadSavedVars(info)
        for _, dir in ipairs({ world.svAccountDir, world.svCharDir }) do
            local path = svPath(dir, info.name)
            local text = readFile(path)
            if text then
                local chunk, err = loadstring(text, "@" .. path)
                if chunk then
                    safecall(chunk)
                else
                    sim.errors[#sim.errors + 1] = "SavedVariables unreadable: " .. tostring(err)
                end
            end
        end
    end

    --- Writes every loaded add-on's SavedVariables to disk (what the client does on logout/reload).
    function sim.saveSavedVars()
        for _, info in ipairs(sim.loaded) do
            for _, scope in ipairs({
                { dir = world.svAccountDir, names = info.savedVars },
                { dir = world.svCharDir, names = info.savedVarsChar },
            }) do
                local parts = {}
                for _, varName in ipairs(scope.names) do
                    local value = G[varName]
                    if value ~= nil and isSerialisable(value) then
                        parts[#parts + 1] = varName .. " = " .. serialise(value, 0) .. "\n"
                    end
                end
                if #parts > 0 then
                    local handle = assert(io.open(svPath(scope.dir, info.name), "wb"))
                    handle:write(table.concat(parts))
                    handle:close()
                end
            end
        end
    end

    ---------------------------------------------------------------- Add-on loading
    --- Runs an add-on's .toc files in order with (addonName, ns), then loads its SavedVariables and
    --- fires ADDON_LOADED. A runtime error stops that add-on loading, as in the client.
    -- @param info { name, dir, files = {...}, meta = {...}, savedVars = {...}, savedVarsChar = {...} }
    function sim.loadAddon(info)
        local ns = {}
        sim.meta[info.name] = info.meta
        sim.loaded[#sim.loaded + 1] = info
        for _, relative in ipairs(info.files) do
            local path = info.dir .. "/" .. relative
            local text = readFile(path)
            if not text then
                sim.errors[#sim.errors + 1] = info.name .. ": couldn't open " .. relative
                return false
            end
            local chunk, err = loadstring(text, "@" .. info.name .. "/" .. relative)
            if not chunk then
                sim.errors[#sim.errors + 1] = tostring(err)
                return false
            end
            if not safecall(chunk, info.name, ns) then
                return false
            end
        end
        loadSavedVars(info)
        sim.loadedNames[info.name] = true
        sim.fire("ADDON_LOADED", info.name)
        return true
    end

    -- Data APIs (separate file so each fake can carry a KNOWN / ASSUMED tag).
    return sim
end
