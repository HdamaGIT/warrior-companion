-- luacheck: ignore (simulator and fixture code defines WoW globals on purpose; see D-011)
local addonName, ns = ...
ns.fileA = true

local pending = false
local frame = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "BAG_UPDATE_DELAYED",
                         "PLAYER_REGEN_DISABLED" }) do
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        FakeDB = FakeDB or { loads = 0, events = {}, bagScans = 0 }
        FakeCharDB = FakeCharDB or { visits = 0 }
        FakeDB.loads = FakeDB.loads + 1
        FakeCharDB.visits = FakeCharDB.visits + 1
        print("loaded " .. tostring(ns.fileA) .. tostring(ns.fileB))
    end
    if event == "PLAYER_REGEN_DISABLED" then
        error("boom")
    end
    if event == "BAG_UPDATE_DELAYED" then
        if pending then return end
        pending = true
        C_Timer.After(0.5, function()
            pending = false
            FakeDB.bagScans = FakeDB.bagScans + 1
        end)
        return
    end
    FakeDB.events[#FakeDB.events + 1] = event
end)

SLASH_FAKE1 = "/fake"
SlashCmdList.FAKE = function(msg) print("fake:" .. msg) end
