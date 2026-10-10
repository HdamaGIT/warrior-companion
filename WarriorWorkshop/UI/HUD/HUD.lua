local addonName, ns = ...

-- Combat HUD (SPEC_V2 §7.5): shared lifecycle for the HUD elements (alert strip, big alert, badges), moving and
-- saving positions, and the /ww unlock|lock|hud|test commands.
--   * Frames are plain, non-secure CreateFrame frames anchored to UIParent, created once at PLAYER_LOGIN and never
--     created or re-parented in combat.
--   * The HUD reads view-models from WW_* messages only (WW_ALERTS_UPDATED, WW_COMBAT_SUSPENDED, WW_COMBAT_ENABLED,
--     WW_CONTEXT_CHANGED); positions and styles come from the character's combat settings.
-- Element files (UI/HUD/*.lua, loaded after this one) register themselves with HUD:RegisterElement.
local Adapter = ns.Adapter
local DB = ns.DB
local Events = ns.Events
local L = ns.L

local HUD = ns:NewModule("HUD")
ns.HUD = HUD

HUD.elements = {} -- in registration order
HUD.FALLBACK_ICON = 134400 -- question-mark icon file ID. [VERIFY in game]

--- Registers an element. Called at file load by each element file.
-- @param element table { key = settings key under combat.hud, label = string, Create(self, settings, style),
--   Update(self, alerts, count, style), ShowTest(self, style), SetSuspended(self, suspended) optional }
function HUD:RegisterElement(element)
    self.elements[#self.elements + 1] = element
end

--- Creates an icon widget: a square frame with an icon texture, a glow behind it and a text line under it.
-- @param parent Frame
-- @param size number
-- @return table { frame, icon, glow, text }
function HUD.CreateIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    glow:SetColorTexture(1.0, 0.82, 0.0, 0.6)
    glow:Hide()
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexture(HUD.FALLBACK_ICON)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    frame:Hide()
    return { frame = frame, icon = icon, glow = glow, text = text }
end

local iconCache = {}

--- Icon file for a spell, cached (read once per spell through the Adapter).
-- @param spellID number|nil
-- @return number|string icon
function HUD.IconFor(spellID)
    if spellID == nil then
        return HUD.FALLBACK_ICON
    end
    local icon = iconCache[spellID]
    if icon == nil then
        icon = Adapter.GetSpellIcon(spellID) or HUD.FALLBACK_ICON
        iconCache[spellID] = icon
    end
    return icon
end

local function combatSettings()
    local character = DB.GetCharacter()
    return character and character.combat
end

--- Places a frame from its saved position (point relative to the same point of UIParent).
-- @param frame Frame
-- @param settings table { point, x, y, scale }
function HUD.ApplyPosition(frame, settings)
    frame:ClearAllPoints()
    local point = settings.point or "CENTER"
    frame:SetPoint(point, UIParent, point, settings.x or 0, settings.y or 0)
    if settings.scale then
        frame:SetScale(settings.scale)
    end
end

local function savePosition(frame, settings)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end
    -- After dragging, the client anchors the frame to UIParent with matching points. [VERIFY in game]
    settings.point = point
    settings.x = math.floor(x + 0.5)
    settings.y = math.floor(y + 0.5)
    if relativePoint ~= point then
        ns.Log.Debug("HUD: dragged frame anchored " .. tostring(point) .. " to " .. tostring(relativePoint))
    end
end

-- Adds a mover overlay to an element's root frame: shown only while unlocked.
local function addMover(element, settings)
    local frame = element.frame
    local overlay = frame:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints(frame)
    overlay:SetColorTexture(0.1, 0.5, 1.0, 0.35)
    overlay:Hide()
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    label:SetText(element.label)
    label:Hide()
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not Adapter.InCombat() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, settings)
    end)
    element.mover, element.moverLabel = overlay, label
end

local function setMovers(unlocked)
    for _, element in ipairs(HUD.elements) do
        if element.frame then
            element.frame:EnableMouse(unlocked)
            element.mover:SetShown(unlocked)
            element.moverLabel:SetShown(unlocked)
            if unlocked then
                element.frame:Show()
            end
        end
    end
end

-- Redraws every element from the last alerts (or test data), honouring enabled / unlocked / test states.
function HUD:Refresh()
    local combat = combatSettings()
    if not combat or not self.created then
        return
    end
    local style = combat.alertStyle
    local enabled = combat.enabled ~= false
    for _, element in ipairs(self.elements) do
        if element.SetSuspended then
            element:SetSuspended((self.suspended and enabled) and true or false)
        end
        if self.testing then
            element:ShowTest(style)
        else
            element:Update(self.alerts, enabled and self.count or 0, style)
        end
        if element.frame then
            element.frame:SetShown(enabled or self.testing or combat.hud.locked == false)
        end
    end
    setMovers(combat.hud.locked == false)
end

-- Message handlers ------------------------------------------------------------------------------------------------

function HUD:OnAlertsUpdated(alerts, count)
    self.alerts, self.count = alerts, count
    if not self.testing then
        for _, element in ipairs(self.elements) do
            element:Update(alerts, count, combatSettings().alertStyle)
        end
    end
end

function HUD:OnSuspended(suspended)
    self.suspended = suspended
    self:Refresh()
end

function HUD:OnEnabled()
    self:Refresh()
end

-- Test mode and unlocking end on entering combat.
function HUD:OnContextChanged(state)
    if state.inCombat and (self.testing or combatSettings().hud.locked == false) then
        self.testing = false
        combatSettings().hud.locked = true
        self:Refresh()
    end
end

-- Commands ------------------------------------------------------------------------------------------------------

local function refuseInCombat()
    if Adapter.InCombat() then
        Adapter.Print(L.HUD_IN_COMBAT)
        return true
    end
    return false
end

--- /ww unlock: show movers so the frames can be dragged (out of combat only).
function HUD:Unlock()
    if refuseInCombat() then
        return
    end
    combatSettings().hud.locked = false
    self:Refresh()
    Adapter.Print(L.HUD_UNLOCKED)
end

--- /ww lock: hide movers; positions were saved on each drag.
function HUD:Lock()
    combatSettings().hud.locked = true
    self:Refresh()
    Adapter.Print(L.HUD_LOCKED)
end

--- /ww hud on|off: switches combat alerts on or off (combat.enabled).
-- @param arg string "on" | "off"
function HUD:Toggle(arg)
    arg = string.lower(arg or "")
    if arg ~= "on" and arg ~= "off" then
        Adapter.Print(L.HUD_USAGE)
        return
    end
    ns.Companion:SetEnabled(arg == "on")
    Adapter.Print(arg == "on" and L.HUD_ON or L.HUD_OFF)
end

--- /ww test: shows every display with sample data for positioning; again to stop (out of combat only).
function HUD:Test()
    if not self.testing and refuseInCombat() then
        return
    end
    self.testing = not self.testing
    self:Refresh()
    Adapter.Print(self.testing and L.HUD_TEST_ON or L.HUD_TEST_OFF)
end

-- Lifecycle -----------------------------------------------------------------------------------------------------

--- PLAYER_LOGIN: creates every element's frames, places them and subscribes to WW_* messages.
-- Side effects: frames; event subscriptions; /ww commands.
function HUD:OnEnable()
    local combat = combatSettings()
    if not combat then
        return
    end
    self.alerts, self.count = {}, 0
    combat.hud.locked = true -- always start locked
    for _, element in ipairs(self.elements) do
        local settings = combat.hud[element.key]
        element:Create(settings, combat.alertStyle)
        HUD.ApplyPosition(element.frame, settings)
        addMover(element, settings)
    end
    self.created = true
    Events:On("WW_ALERTS_UPDATED", self, "OnAlertsUpdated")
    Events:On("WW_COMBAT_SUSPENDED", self, "OnSuspended")
    Events:On("WW_COMBAT_ENABLED", self, "OnEnabled")
    Events:On("WW_CONTEXT_CHANGED", self, "OnContextChanged")
    self.suspended = ns.Context:Current().restricted
    self:Refresh()
    ns.Companion:Republish()
end

ns.Core:RegisterCommand("unlock", function()
    HUD:Unlock()
end)
ns.Core:RegisterCommand("lock", function()
    HUD:Lock()
end)
ns.Core:RegisterCommand("hud", function(rest)
    HUD:Toggle(rest)
end)
ns.Core:RegisterCommand("test", function()
    HUD:Test()
end)
