-- luacheck configuration for Warrior Workshop.
-- WoW globals are whitelisted ONLY for the files allowed to touch the game API:
-- Core/Adapter.lua, Core/Init.lua (slash registration), UI/ and the probe.
-- Everything else (Modules, other Core files) is pure Lua 5.1 and any WoW global
-- there is a lint error by design. See CLAUDE.md "Architecture rules".

std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
    ".idea/",
    "lua_modules/",
    ".luarocks/",
}

ignore = {
    "211/addonName", -- mandated header `local addonName, ns = ...` is often unused
    "212/self",      -- unused self in module methods
}

-- The only globals any add-on file may create (SavedVariables).
globals = {
    "WarriorWorkshopDB",
    "WarriorWorkshopCharDB",
}

-- WoW API surface used by the whitelisted files. Extend as the Adapter grows.
stds.wow = {
    read_globals = {
        -- Lua extensions WoW provides
        "time", "date", "strsplit", "strtrim", "strjoin", "wipe", "tinsert", "tremove",
        "format", "debugstack", "geterrorhandler",
        -- Build / chat output
        "GetBuildInfo", "DEFAULT_CHAT_FRAME", "GetTime",
        -- Frames
        "CreateFrame", "UIParent", "GameTooltip",
        -- Combat / group state
        "InCombatLockdown", "UnitAffectingCombat", "IsInGroup", "IsInRaid",
        "LE_PARTY_CATEGORY_INSTANCE", "SendChatMessage",
        -- Namespaces
        "C_AddOns", "C_ChatInfo", "C_Container", "C_EquipmentSet", "C_Item",
        "C_TradeSkillUI", "C_Timer", "Enum", "Item",
        -- Unit, inventory and item data (Adapter only)
        "UnitName", "UnitClass", "UnitLevel", "GetRealmName", "GetInventoryItemID", "GetInventoryItemLink",
        "GetInventoryItemDurability", "GetItemStats", "GetItemInfo", "IsUsableItem",
    },
}

files["WarriorWorkshop/Core/Adapter.lua"] = { std = "+wow" }

-- Init.lua may additionally register the slash command.
files["WarriorWorkshop/Core/Init.lua"] = {
    std = "+wow",
    globals = { "SlashCmdList", "SLASH_WW1", "WarriorWorkshopDB", "WarriorWorkshopCharDB" },
}

files["WarriorWorkshop/UI/*.lua"] = { std = "+wow" }

files["WarriorWorkshopProbe/*.lua"] = {
    std = "+wow",
    globals = {
        "WarriorWorkshopProbeDB", "SlashCmdList", "SLASH_WWPROBE1",
        -- Bindings.xml (M3): header/name labels and the binding handler
        "BINDING_HEADER_WWPROBE", "BINDING_NAME_WWPROBE_CHATKEY", "WWProbe_ChatKey",
    },
}

files["tests/*.lua"] = { std = "+busted" }
files["tests/helpers/*.lua"] = { std = "+busted" }
