-- luacheck: ignore (simulator and fixture code defines WoW globals on purpose; see D-011)
-- Headless WoW client simulator: data APIs backed by the scenario `world` (D-011).
-- Every fake carries a status:
--   KNOWN   long-standing API whose signature is not in doubt.
--   ASSUMED shape or existence not yet confirmed in Forever (see docs/PROBE_RESULTS.md).
--           Passing a test against an ASSUMED fake proves the code matches our guess, not the client.
-- Promote ASSUMED to KNOWN only when PROBE_RESULTS.md records the real behaviour.
-- Not linted: it defines WoW globals on purpose.

return function(sim)
    local G = _G
    local world = sim.world
    local player = world.player

    local function def(path, status, fn)
        local container, key = G, path
        local first, rest = path:match("^([^.]+)%.(.+)$")
        while first do
            container[first] = container[first] or {}
            container, key = container[first], rest
            first, rest = key:match("^([^.]+)%.(.+)$")
        end
        container[key] = function(...)
            sim.apiUsed[path] = status
            return fn(...)
        end
    end

    local function itemLink(itemID)
        local item = world.items and world.items[itemID]
        local name = item and item.name or ("item" .. tostring(itemID))
        return string.format("|cffffffff|Hitem:%d|h[%s]|h|r", itemID, name)
    end

    -- Build and add-ons
    def("GetBuildInfo", "KNOWN", function()
        local b = world.build
        return b.version, b.build, b.date, b.interface, b.version
    end)
    def("C_AddOns.GetAddOnMetadata", "KNOWN", function(name, field)
        local meta = sim.meta[name]
        return meta and meta[field] or nil
    end)
    def("C_AddOns.IsAddOnLoaded", "KNOWN", function(name)
        return sim.loadedNames[name] == true
    end)

    -- Player and state
    def("UnitName", "KNOWN", function(unit)
        if unit == "player" then return player.name, nil end
    end)
    def("UnitClass", "KNOWN", function(unit)
        if unit == "player" then return player.classLocalised, player.class, player.classID end
    end)
    def("UnitLevel", "KNOWN", function(unit)
        if unit == "player" then return player.level end
    end)
    def("GetRealmName", "KNOWN", function() return player.realm end)
    def("GetMoney", "KNOWN", function() return world.money or 0 end)
    def("InCombatLockdown", "KNOWN", function() return world.inCombat == true end)
    def("UnitAffectingCombat", "KNOWN", function(unit)
        return unit == "player" and world.inCombat == true
    end)
    def("IsInGroup", "KNOWN", function() return world.inGroup == true end)
    def("IsInRaid", "KNOWN", function() return world.inRaid == true end)

    -- Containers (Midnight bank-tab layout is unconfirmed: bags here are plain numbered containers)
    def("C_Container.GetContainerNumSlots", "ASSUMED", function(bag)
        local container = world.bags and world.bags[bag]
        return container and container.slots or 0
    end)
    def("C_Container.GetContainerItemInfo", "ASSUMED", function(bag, slot)
        local container = world.bags and world.bags[bag]
        local entry = container and container.items and container.items[slot]
        if not entry then
            return nil
        end
        local item = world.items and world.items[entry.itemID] or {}
        return {
            iconFileID = item.icon or 0,
            stackCount = entry.count or 1,
            isLocked = false,
            quality = item.quality or 1,
            isReadable = false,
            hasLoot = false,
            hyperlink = itemLink(entry.itemID),
            isFiltered = false,
            hasNoValue = false,
            itemID = entry.itemID,
            isBound = entry.bound == true,
        }
    end)

    -- Items
    def("C_Item.GetItemInfo", "ASSUMED", function(itemID)
        local item = world.items and world.items[itemID]
        if not item then
            return nil
        end
        return item.name, itemLink(itemID), item.quality or 1, item.itemLevel or 1, item.minLevel or 1,
            item.itemType or "", item.subType or "", item.stack or 1, item.equipLoc or "", item.icon or 0,
            item.sellPrice or 0
    end)
end
