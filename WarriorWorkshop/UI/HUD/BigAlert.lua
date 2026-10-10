local addonName, ns = ...

-- Big alert (SPEC_V2 §7.5, U-15): one centre-screen slot for "dropped" and "expiring" alerts (Battle Shout). Size,
-- flash and sound follow combat.alertStyle; the sound plays once when an alert enters a state that has one.
local Adapter = ns.Adapter
local HUD = ns.HUD
local L = ns.L

local BigAlert = { key = "bigAlert", label = L.HUD_FRAME_BIG_ALERT }

local TEST_ALERT = { id = "battleShout", label = L.RULE_BATTLE_SHOUT, display = "big", state = "expiring",
    severity = "expiring", remaining = 8 }

--- Creates the slot (HUD places it from combat.hud.bigAlert). The frame is sized for the largest style; the icon
-- resizes per severity.
-- @param _ table combat.hud.bigAlert (unused)
-- @param style table combat.alertStyle
function BigAlert:Create(_, style)
    local largest = 64
    for _, entry in pairs(style) do
        if type(entry) == "table" and type(entry.size) == "number" and entry.size > largest then
            largest = entry.size
        end
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(largest, largest + 24)
    frame:SetFrameStrata("HIGH")
    local widget = HUD.CreateIcon(frame, largest)
    widget.frame:SetPoint("TOP", frame, "TOP", 0, 0)
    widget.text:SetFontObject("GameFontNormalLarge")
    -- Flash: an alpha pulse when the client provides animation groups (guarded: not every environment does).
    if widget.frame.CreateAnimationGroup then
        local group = widget.frame:CreateAnimationGroup()
        if group and group.CreateAnimation then
            group:SetLooping("BOUNCE")
            local fade = group:CreateAnimation("Alpha")
            if fade then
                fade:SetFromAlpha(1)
                fade:SetToAlpha(0.3)
                fade:SetDuration(0.4)
            end
            self.flash = group
        end
    end
    self.widget, self.frame = widget, frame
end

local function stateText(entry)
    if entry.state == "expiring" and entry.remaining then
        return entry.label .. " " .. string.format(L.STATE_EXPIRING, math.ceil(entry.remaining))
    elseif entry.state == "dropped" then
        return entry.label .. " " .. L.STATE_DROPPED
    end
    return entry.label
end

local function setFlash(self, on)
    if not self.flash then
        return
    end
    if on and not self.flashing then
        self.flash:Play()
    elseif not on and self.flashing then
        self.flash:Stop()
    end
    self.flashing = on
end

local function show(self, entry, style, silent)
    local widget = self.widget
    if not entry then
        widget.frame:Hide()
        setFlash(self, false)
        self.lastKey = nil
        return
    end
    local severityStyle = style and style[entry.severity] or {}
    local size = severityStyle.size or 64
    widget.frame:SetSize(size, size)
    widget.icon:SetTexture(HUD.IconFor(entry.spellID))
    widget.glow:SetShown(severityStyle.glow and true or false)
    widget.text:SetText(stateText(entry))
    widget.frame:Show()
    setFlash(self, severityStyle.flash and true or false)
    local key = entry.id .. ":" .. tostring(entry.state)
    if key ~= self.lastKey then
        self.lastKey = key
        if severityStyle.sound and not silent then
            Adapter.PlaySound(severityStyle.sound)
        end
    end
end

--- Shows the first "big" entry of an alerts list, or hides the slot.
-- @param alerts array of alert entries (WW_ALERTS_UPDATED)
-- @param count number
-- @param style table combat.alertStyle
-- Side effects: may play the style's sound once per state change.
function BigAlert:Update(alerts, count, style)
    for index = 1, count do
        local entry = alerts[index]
        if entry.display == "big" then
            show(self, entry, style, false)
            return
        end
    end
    show(self, nil, style)
end

--- Shows a sample Battle Shout countdown for positioning (/ww test); no sound.
function BigAlert:ShowTest(style)
    show(self, TEST_ALERT, style, true)
end

HUD:RegisterElement(BigAlert)
