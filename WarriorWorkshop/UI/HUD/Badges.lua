local addonName, ns = ...

-- Badges (SPEC_V2 §7.5): small text lines for "badge" alerts (auto-attack off, Charge / Intercept in range) and the
-- "Suspended" badge shown while a restricted context pauses combat alerts (D-021).
local HUD = ns.HUD
local L = ns.L

local ROWS = 4
local ROW_HEIGHT = 18
local WIDTH = 160

local Badges = { key = "badges", label = L.HUD_FRAME_BADGES, rows = {} }

local TEST_ALERTS = {
    { id = "autoAttack", label = L.RULE_AUTO_ATTACK, display = "badge", severity = "reactive" },
    { id = "chargeRange", label = L.RULE_CHARGE, display = "badge", severity = "reactive" },
}

-- Badge colours: suspended grey, auto-attack (a fault) orange, range badges green.
local COLOURS = {
    suspended = { 0.7, 0.7, 0.7 },
    autoAttack = { 1.0, 0.5, 0.1 },
    default = { 0.3, 1.0, 0.3 },
}

--- Creates the badge column (HUD places it from combat.hud.badges).
function Badges:Create()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(WIDTH, ROWS * ROW_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    for index = 1, ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH, ROW_HEIGHT - 2)
        row:SetPoint("TOP", frame, "TOP", 0, -(index - 1) * ROW_HEIGHT)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(row)
        background:SetColorTexture(0, 0, 0, 0.5)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("CENTER", row, "CENTER", 0, 0)
        row:Hide()
        self.rows[index] = { frame = row, text = text }
    end
    self.frame = frame
end

local function setRow(row, label, colour)
    row.text:SetText(label)
    row.text:SetTextColor(colour[1], colour[2], colour[3], 1)
    row.frame:Show()
end

local function show(self, alerts, count)
    local used = 0
    if self.suspended then
        used = 1
        setRow(self.rows[1], L.HUD_SUSPENDED, COLOURS.suspended)
    end
    for index = 1, count do
        local entry = alerts[index]
        if entry.display == "badge" and used < ROWS then
            used = used + 1
            setRow(self.rows[used], entry.label, COLOURS[entry.id] or COLOURS.default)
        end
    end
    for index = used + 1, ROWS do
        self.rows[index].frame:Hide()
    end
end

--- Shows the badge entries of an alerts list (plus "Suspended" if set).
-- @param alerts array of alert entries (WW_ALERTS_UPDATED)
-- @param count number
function Badges:Update(alerts, count)
    self.alerts, self.count = alerts, count
    show(self, alerts, count)
end

--- Shows or hides the "Suspended" badge.
-- @param suspended boolean
function Badges:SetSuspended(suspended)
    if self.suspended ~= suspended then
        self.suspended = suspended
        show(self, self.alerts or TEST_ALERTS, self.alerts and self.count or 0)
    end
end

--- Sample badges, with "Suspended" on top, for positioning (/ww test). Leaves the real suspended state alone.
function Badges:ShowTest()
    setRow(self.rows[1], L.HUD_SUSPENDED, COLOURS.suspended)
    local used = 1
    for _, entry in ipairs(TEST_ALERTS) do
        used = used + 1
        setRow(self.rows[used], entry.label, COLOURS[entry.id] or COLOURS.default)
    end
    for index = used + 1, ROWS do
        self.rows[index].frame:Hide()
    end
end

HUD:RegisterElement(Badges)
