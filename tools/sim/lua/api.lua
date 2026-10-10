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
    def("IsInInstance", "KNOWN", function()
        local kind = world.instanceType or "none"
        return kind ~= "none", kind
    end)
    def("UnitIsDeadOrGhost", "KNOWN", function(unit)
        if unit == "target" then
            return world.target ~= nil and world.target.dead == true
        end
        return unit == "player" and world.dead == true
    end)

    -- Encounters and spells (Context / SpellMap, M2). Spell IDs in scenarios are fake (9xxxxx).
    def("IsEncounterInProgress", "ASSUMED", function() return world.encounter == true end)
    def("C_Spell.GetSpellInfo", "ASSUMED", function(name)
        local spellID = world.spells and world.spells[name]
        if not spellID then
            return nil
        end
        return { name = name, spellID = spellID, iconID = 0, castTime = 0, minRange = 0, maxRange = 0 }
    end)
    def("IsPlayerSpell", "ASSUMED", function(spellID)
        for _, known in pairs(world.spells or {}) do
            if known == spellID then
                return true
            end
        end
        return false
    end)

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

    ---------------------------------------------------------------- Restrictions and secret values (M5)
    -- What beta run 2 (10 Oct 2026, open world, solo) recorded; see docs/PROBE_RESULTS.md "Run 2":
    --   * Restriction type 0 (Combat) is Active (state 2) for the whole of every fight. The event
    --     ADDON_RESTRICTION_STATE_CHANGED fired with (0, 1) right after PLAYER_REGEN_DISABLED and (0, 0) right before
    --     PLAYER_REGEN_ENABLED, at the same GetTime; no (0, 2) event and no 1 -> 2 transition was seen. Reading the
    --     second argument as an active flag (not the state enum) is ASSUMED. Client.set_combat fires that order.
    --   * While type 0 is active: aura reads are secret (by name: nil; by index: an error), cooldown startTime /
    --     duration / modRate are secret (isActive, isEnabled readable). Rage and health were secret even out of combat.
    --   * Usability, range, IsCurrentSpell, stance, target reaction/attackable and event payloads stay readable.
    -- world.secretsOff = true turns every secret off (for testing the readable path).
    --
    -- Secret values are userdata proxies, ported from tests/helpers/probe_client.lua. They raise on indexing,
    -- arithmetic, concatenation, ordering (<, <=), length, call and tostring, like real secrets. Lua 5.1 cannot catch
    -- three misuses, so the simulator does NOT detect them:
    --   * secret == x against a non-secret is silently false (__eq only runs when both sides are userdata);
    --   * t[secret] = x and t[secret] reads are not intercepted;
    --   * `if secret then` is always true (truthiness cannot be intercepted).
    local function secretError()
        error("attempt to use a secret value", 2)
    end
    local secretPrototype = newproxy(true)
    do
        local meta = getmetatable(secretPrototype)
        for _, event in ipairs({ "__index", "__newindex", "__add", "__sub", "__mul", "__div", "__mod", "__pow",
            "__unm", "__concat", "__len", "__lt", "__le", "__call", "__tostring" }) do
            meta[event] = secretError
        end
    end
    local secretSet = setmetatable({}, { __mode = "k" })
    local function secret()
        local value = newproxy(secretPrototype)
        secretSet[value] = true
        return value
    end
    sim.secret = secret

    local function restrictionState(restrictionType)
        local states = world.restrictions
        return states and states[restrictionType] or 0
    end
    local function combatSecrets()
        return world.secretsOff ~= true and restrictionState(0) == 2
    end
    local function alwaysSecret()
        return world.secretsOff ~= true
    end
    local function maybeSecret(isSecret, value)
        if isSecret and value ~= nil then
            return secret()
        end
        return value
    end

    def("issecretvalue", "KNOWN", function(value)
        return type(value) == "userdata" and secretSet[value] == true
    end)

    G.Enum = G.Enum or {}
    -- KNOWN (run 2 static dump).
    G.Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
    G.Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }

    def("C_RestrictedActions.GetAddOnRestrictionState", "KNOWN", function(restrictionType)
        return restrictionState(restrictionType)
    end)
    def("C_RestrictedActions.IsAddOnRestrictionActive", "KNOWN", function(restrictionType)
        return restrictionState(restrictionType) == 2
    end)

    def("C_Secrets.ShouldAurasBeSecret", "KNOWN", function() return combatSecrets() end)
    def("C_Secrets.ShouldCooldownsBeSecret", "KNOWN", function() return combatSecrets() end)
    def("C_Secrets.ShouldUnitPowerBeSecret", "KNOWN", function() return alwaysSecret() end)
    def("C_Secrets.ShouldUnitHealthMaxBeSecret", "KNOWN", function() return alwaysSecret() end)

    ---------------------------------------------------------------- Combat state (M5)
    -- World shape (spell names as in world.spells; IDs in scenarios are fake 9xxxxx):
    --   target = { exists, hostile, dead }, autoAttack = bool, stance = { index, spellID },
    --   spellState = { [name] = { usable, noPower, inRange, cdStart, cdDuration } },
    --   auras = { player = { [name] = { duration, expirationTime, applications, sourceUnit } } },
    --   power = { rage, rageMax }, targetHealth = { cur, max }
    local function spellName(spellID)
        for name, id in pairs(world.spells or {}) do
            if id == spellID then
                return name
            end
        end
        return nil
    end
    local function spellState(spell)
        local name = type(spell) == "number" and spellName(spell) or spell
        return name and world.spellState and world.spellState[name] or nil
    end
    local function target()
        local t = world.target
        if t and t.exists then
            return t
        end
        return nil
    end

    def("UnitExists", "KNOWN", function(unit)
        if unit == "player" then
            return true
        end
        return unit == "target" and target() ~= nil
    end)
    def("UnitCanAttack", "KNOWN", function(_, unit)
        local t = unit == "target" and target()
        return t ~= nil and t ~= false and t.hostile == true
    end)
    def("UnitPower", "KNOWN", function()
        local power = world.power or {}
        return maybeSecret(alwaysSecret(), power.rage or 0)
    end)
    def("UnitPowerMax", "KNOWN", function()
        local power = world.power or {}
        return power.rageMax or 100 -- rageMax was readable in run 2
    end)
    def("UnitHealth", "KNOWN", function(unit)
        local health = world.targetHealth or {}
        return maybeSecret(alwaysSecret(), unit == "target" and (health.cur or 100) or 100)
    end)
    def("UnitHealthMax", "KNOWN", function(unit)
        local health = world.targetHealth or {}
        return maybeSecret(alwaysSecret(), unit == "target" and (health.max or 100) or 100)
    end)

    def("C_Spell.IsSpellUsable", "KNOWN", function(spell)
        local state = spellState(spell)
        if not state then
            return false, false
        end
        return state.usable == true, state.noPower == true
    end)
    def("C_Spell.IsSpellInRange", "KNOWN", function(spell, unit)
        local state = spellState(spell)
        if unit ~= "target" or not target() or not state or state.inRange == nil then
            return nil
        end
        return state.inRange == true
    end)
    def("C_Spell.IsCurrentSpell", "KNOWN", function(spell)
        if spell == 6603 then -- Auto Attack (V-23)
            return world.autoAttack == true
        end
        return false
    end)
    -- Fields the run 2 sampler saw; anything else on the real table is ASSUMED absent here.
    def("C_Spell.GetSpellCooldown", "KNOWN", function(spell)
        local state = spellState(spell) or {}
        local start, duration = state.cdStart or 0, state.cdDuration or 0
        local active = duration > 0 and start + duration > sim.now
        local hide = combatSecrets()
        return {
            startTime = maybeSecret(hide, start),
            duration = maybeSecret(hide, duration),
            modRate = maybeSecret(hide, 1),
            isActive = active,
            isEnabled = true,
        }
    end)
    def("C_Spell.GetSpellName", "ASSUMED", function(spellID)
        return spellName(spellID)
    end)
    def("C_Spell.GetSpellTexture", "ASSUMED", function(spellID)
        return spellName(spellID) and (130000 + spellID % 100000) or nil
    end)

    local function auraData(unit, name)
        local byUnit = world.auras and world.auras[unit]
        local aura = byUnit and byUnit[name]
        if not aura then
            return nil
        end
        if aura.expirationTime and aura.expirationTime > 0 and aura.expirationTime <= sim.now then
            return nil
        end
        return {
            name = name,
            applications = aura.applications or 0,
            duration = aura.duration or 0,
            expirationTime = aura.expirationTime or 0,
            sourceUnit = aura.sourceUnit or "player",
            isFromPlayerOrPlayerPet = (aura.sourceUnit or "player") == "player",
            isHarmful = false,
            spellId = world.spells and world.spells[name] or 0,
            timeMod = 1,
        }
    end
    def("C_UnitAuras.GetAuraDataBySpellName", "KNOWN", function(unit, name)
        if combatSecrets() then
            return nil -- run 2: nil in combat, indistinguishable from "absent"
        end
        return auraData(unit, name)
    end)
    def("C_UnitAuras.GetAuraDataByIndex", "KNOWN", function(unit, index)
        if combatSecrets() then
            error("Auras cannot be accessed when secret while tainted", 2) -- run 2
        end
        local byUnit = world.auras and world.auras[unit] or {}
        local names = {}
        for name in pairs(byUnit) do
            names[#names + 1] = name
        end
        table.sort(names)
        return names[index] and auraData(unit, names[index]) or nil
    end)

    def("GetShapeshiftForm", "KNOWN", function()
        return world.stance and world.stance.index or 0
    end)
    def("GetShapeshiftFormInfo", "KNOWN", function(index) -- run 2: icon, active, castable, spellID
        local stance = world.stance
        if not stance or stance.index ~= index then
            return nil
        end
        return 132349, true, true, stance.spellID
    end)

    def("PlaySound", "ASSUMED", function(soundKitID)
        sim.sounds = sim.sounds or {}
        sim.sounds[#sim.sounds + 1] = soundKitID
        return true
    end)
    G.SOUNDKIT = G.SOUNDKIT or { RAID_WARNING = 8959 } -- ASSUMED value
end
