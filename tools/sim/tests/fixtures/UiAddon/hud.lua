-- luacheck: ignore (simulator fixture; see D-011)
-- A small HUD shaped like the M5 combat HUD, for preview tests and demos. Not the real add-on.
local _, ns = ...

local hud = CreateFrame("Frame", "UiAddonHUD", UIParent)
hud:SetSize(240, 80)
hud:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
hud:SetFrameStrata("MEDIUM")

local bg = hud:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", hud, "TOPLEFT", 8, -6)
title:SetText("Warrior HUD")

local status = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPRIGHT", -8, -8)
status:SetText("|cff00ff00ready|r")

local icons = {}
for i = 1, 3 do
    local icon = hud:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 8 + (i - 1) * 38, 8)
    icon:SetColorTexture(0.8, 0.2 * i, 0.1, 1)
    icons[i] = icon
end

local bar = CreateFrame("StatusBar", nil, hud)
bar:SetPoint("BOTTOMLEFT", icons[3], "BOTTOMRIGHT", 8, 0)
bar:SetPoint("TOPRIGHT", hud, "BOTTOMRIGHT", -8, 40)
bar:SetMinMaxValues(0, 100)
bar:SetValue(25)
bar:SetStatusBarColor(0.8, 0.1, 0.1)

local suspended = hud:CreateFontString("UiAddonSuspended", "OVERLAY", "GameFontRed")
suspended:SetPoint("BOTTOM", hud, "TOP", 0, 4)
suspended:SetText("Suspended")
suspended:Hide()

local button = CreateFrame("Button", "UiAddonLock", hud, "UIPanelButtonTemplate")
button:SetSize(60, 20)
button:SetPoint("TOPRIGHT", hud, "BOTTOMRIGHT", 0, -4)

ns.hud, ns.suspended = hud, suspended

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    suspended:SetShown(event == "PLAYER_REGEN_DISABLED")
    status:SetText(event == "PLAYER_REGEN_DISABLED" and "|cffff0000combat|r" or "|cff00ff00ready|r")
end)
