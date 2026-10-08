local addonName, ns = ...

-- The ONLY file that calls Blizzard data APIs (D-002). Every function degrades
-- gracefully: if the underlying API is missing it returns nil and warns once.
-- M0 surface: GetBuildInfo, GetAddOnVersion, Print. Extended in M2 from probe results.
local Adapter = {}
ns.Adapter = Adapter

local CHAT_PREFIX = "|cffc79c6eWarrior Workshop|r: " -- warrior class colour

local warned = {}

local function warnOnce(apiName)
    if warned[apiName] then
        return
    end
    warned[apiName] = true
    Adapter.Print("API unavailable: " .. apiName)
end

--- Prints a line to the default chat frame with the add-on prefix.
-- @param msg any value; converted with tostring
-- Side effects: chat output only.
function Adapter.Print(msg)
    local line = CHAT_PREFIX .. tostring(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(line)
    else
        print(line)
    end
end

--- Returns client build information.
-- @return { version = string, build = string, interface = number } or nil if unavailable
function Adapter.GetBuildInfo()
    if type(GetBuildInfo) ~= "function" then
        warnOnce("GetBuildInfo")
        return nil
    end
    local version, build, _, interface = GetBuildInfo()
    return { version = version, build = build, interface = interface }
end

--- Returns this add-on's version from the .toc `## Version:` field.
-- @return string or nil if unavailable
function Adapter.GetAddOnVersion()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata
    if type(getMetadata) ~= "function" then
        warnOnce("C_AddOns.GetAddOnMetadata")
        return nil
    end
    return getMetadata(addonName, "Version")
end
