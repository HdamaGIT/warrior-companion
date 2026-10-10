local addonName, ns = ...

-- Alert strip (SPEC_V2 §7.5): up to maxIcons reactive icons in a row, in rule order (Execute, Overpower ...).
-- Shows the entries of WW_ALERTS_UPDATED whose display is "strip". Icons are created once at login and reused.
local HUD = ns.HUD
local L = ns.L

local GAP = 6

local AlertStrip = { key = "alertStrip", label = L.HUD_FRAME_ALERT_STRIP, icons = {} }

local TEST_ALERTS = {
    { id = "execute", label = L.RULE_EXECUTE, display = "strip", severity = "reactive" },
    { id = "overpower", label = L.RULE_OVERPOWER, display = "strip", severity = "reactive" },
}

--- Creates the strip and its icons.
-- @param settings table combat.hud.alertStrip { point, x, y, scale, maxIcons }
-- @param style table combat.alertStyle
function AlertStrip:Create(settings, style)
    local size = (style.reactive and style.reactive.size) or 48
    self.maxIcons = settings.maxIcons or 6
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(self.maxIcons * (size + GAP) - GAP, size + 16)
    frame:SetFrameStrata("MEDIUM")
    for index = 1, self.maxIcons do
        local widget = HUD.CreateIcon(frame, size)
        widget.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", (index - 1) * (size + GAP), 0)
        self.icons[index] = widget
    end
    self.frame = frame
end

local function show(self, alerts, count, style)
    local glow = style and style.reactive and style.reactive.glow
    local shown = 0
    for index = 1, count do
        local entry = alerts[index]
        if entry.display == "strip" and shown < self.maxIcons then
            shown = shown + 1
            local widget = self.icons[shown]
            widget.icon:SetTexture(HUD.IconFor(entry.spellID))
            widget.text:SetText(entry.label)
            widget.glow:SetShown(glow and true or false)
            widget.frame:Show()
        end
    end
    for index = shown + 1, self.maxIcons do
        self.icons[index].frame:Hide()
    end
end

--- Shows the strip entries of an alerts list.
-- @param alerts array of alert entries (WW_ALERTS_UPDATED)
-- @param count number
-- @param style table combat.alertStyle
function AlertStrip:Update(alerts, count, style)
    show(self, alerts, count, style)
end

--- Fills the strip with sample icons for positioning (/ww test).
function AlertStrip:ShowTest(style)
    show(self, TEST_ALERTS, #TEST_ALERTS, style)
end

HUD:RegisterElement(AlertStrip)
