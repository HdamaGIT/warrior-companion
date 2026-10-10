-- Combat accessors in the real Core/Adapter.lua (SPEC_V2 §5.4, D-036, D-045, D-048). WoW APIs are stubbed in a
-- sandbox environment for the Adapter chunk only. Secret values are newproxy userdata that raise on any use other
-- than type() (tests/helpers/probe_client.lua), so a missing secrecy check fails the test with an error.
local H = dofile("tests/helpers/load_addon.lua")
local PC = dofile("tests/helpers/probe_client.lua")
local secret = PC.Secret

local now = 1000

--- Loads the real Adapter with stubs. Every stub sees `now` through GetTime.
local function loadAdapter(stubs)
    local env = setmetatable({ GetTime = function()
        return now
    end }, { __index = _G })
    for key, value in pairs(stubs or {}) do
        env[key] = value
    end
    local ns = H.newNs({ "Locale/enUS.lua", "Core/Util.lua", "Core/Log.lua", "Core/Adapter.lua" }, { env = env })
    ns.Adapter.Print = function() end
    return ns.Adapter
end

-- issecretvalue that recognises the test proxies.
local function checker(value)
    return PC.IsSecret(value)
end

describe("adapter combat accessors", function()
    describe("secrecy checks", function()
        it("returns nil, never errors, when a value is a secret proxy", function()
            local Adapter = loadAdapter({
                issecretvalue = checker,
                UnitPower = function()
                    return secret()
                end,
                UnitPowerMax = function()
                    return 100
                end,
                C_Spell = {
                    IsSpellUsable = function()
                        return secret(), secret()
                    end,
                    IsSpellInRange = function()
                        return secret()
                    end,
                    IsCurrentSpell = function()
                        return secret()
                    end,
                },
            })
            assert.has_no.errors(function()
                assert.is_nil(Adapter.GetRage())
                assert.is_nil(Adapter.IsSpellUsable(1))
                assert.is_nil(Adapter.IsSpellInRange(1, "target"))
                assert.is_nil(Adapter.IsAutoAttacking())
            end)
        end)

        it("without a checker, treats values as readable unless a restriction is active (D-036)", function()
            local Adapter = loadAdapter({
                issecretvalue = false,
                C_Spell = { IsSpellUsable = function()
                    return true, false
                end },
            })
            assert.is_true((Adapter.IsSpellUsable(1)))
            Adapter.SetSecretFallback(true)
            assert.is_nil(Adapter.IsSpellUsable(1))
            Adapter.SetSecretFallback(false)
            assert.is_true((Adapter.IsSpellUsable(1)))
        end)

        it("returns nil when the API is missing", function()
            local Adapter = loadAdapter({ C_Spell = false, C_UnitAuras = false, UnitPower = false })
            assert.is_nil(Adapter.IsSpellUsable(1))
            assert.is_nil(Adapter.GetAura("player", "Battle Shout"))
            assert.is_nil(Adapter.GetRage())
            assert.is_nil(Adapter.GetSpellCooldownRemaining(1))
        end)

        it("returns nil when the API raises", function()
            local Adapter = loadAdapter({ C_Spell = { IsSpellUsable = function()
                error("boom")
            end } })
            assert.is_nil(Adapter.IsSpellUsable(1))
        end)
    end)

    describe("GetAura", function()
        local auraData
        local calls

        local function aurasAdapter(shouldBeSecret)
            calls = 0
            return loadAdapter({
                issecretvalue = checker,
                C_Secrets = { ShouldAurasBeSecret = function()
                    return shouldBeSecret
                end },
                C_UnitAuras = { GetAuraDataBySpellName = function()
                    calls = calls + 1
                    return auraData
                end },
            })
        end

        before_each(function()
            auraData = { applications = 0, expirationTime = now + 120, duration = 180, sourceUnit = "player",
                isFromPlayerOrPlayerPet = true, spellId = 6673 }
        end)

        it("reads stacks, remaining, fromPlayer and duration out of combat", function()
            local stacks, remaining, fromPlayer, duration = aurasAdapter(false).GetAura("player", "Battle Shout")
            assert.are.same({ 0, 120, true, 180 }, { stacks, remaining, fromPlayer, duration })
        end)

        it("returns false (absent) when the by-name read is nil and auras are not secret", function()
            auraData = nil
            assert.is_false(aurasAdapter(false).GetAura("player", "Battle Shout"))
        end)

        it("returns nil (unknown), not false, when ShouldAurasBeSecret is true and the API would return nil", function()
            auraData = nil -- run 2: the by-name call returns nil in combat, indistinguishable from "absent"
            local Adapter = aurasAdapter(true)
            assert.is_nil(Adapter.GetAura("player", "Battle Shout"))
            assert.are.equal(0, calls) -- the pre-check skips the call entirely (D-045)
        end)

        it("without C_Secrets, a nil read in combat is unknown (nil), not absent; out of combat it is absent (D-036)",
            function()
                auraData = nil
                local inCombat = true
                local Adapter = loadAdapter({
                    issecretvalue = checker,
                    C_Secrets = false,
                    InCombatLockdown = function()
                        return inCombat
                    end,
                    C_UnitAuras = { GetAuraDataBySpellName = function()
                        return auraData
                    end },
                })
                assert.is_nil(Adapter.GetAura("player", "Battle Shout"))
                inCombat = false
                assert.is_false(Adapter.GetAura("player", "Battle Shout"))
            end)

        it("when ShouldAurasBeSecret errors in combat, the read is unknown", function()
            auraData = nil
            local Adapter = loadAdapter({
                C_Secrets = { ShouldAurasBeSecret = function()
                    error("boom")
                end },
                InCombatLockdown = function()
                    return true
                end,
                C_UnitAuras = { GetAuraDataBySpellName = function()
                    return auraData
                end },
            })
            assert.is_nil(Adapter.GetAura("player", "Battle Shout"))
        end)

        it("returns nil when a field is secret", function()
            auraData.expirationTime = secret()
            assert.is_nil(aurasAdapter(false).GetAura("player", "Battle Shout"))
        end)

        it("treats expirationTime 0 as permanent and a past expiry as absent", function()
            auraData.expirationTime = 0
            local _, remaining = aurasAdapter(false).GetAura("player", "Battle Shout")
            assert.are.equal(math.huge, remaining)
            auraData.expirationTime = now - 1
            assert.is_false(aurasAdapter(false).GetAura("player", "Battle Shout"))
        end)

        it("falls back to sourceUnit when isFromPlayerOrPlayerPet is missing", function()
            auraData.isFromPlayerOrPlayerPet = nil
            auraData.sourceUnit = "party1"
            local _, _, fromPlayer = aurasAdapter(false).GetAura("player", "Battle Shout")
            assert.is_false(fromPlayer)
        end)
    end)

    describe("GetSpellCooldownRemaining", function()
        local info
        local cooldownsSecret

        local function cdAdapter()
            return loadAdapter({
                issecretvalue = checker,
                C_Secrets = { ShouldCooldownsBeSecret = function()
                    return cooldownsSecret
                end },
                C_Spell = { GetSpellCooldown = function()
                    return info
                end },
            })
        end

        before_each(function()
            cooldownsSecret = false
            info = { startTime = now - 5, duration = 15, modRate = 1, isActive = true, isEnabled = true }
        end)

        it("computes the remaining time out of combat", function()
            assert.are.equal(10, cdAdapter().GetSpellCooldownRemaining(100))
        end)

        it("is 0 when the spell is ready", function()
            info.startTime, info.duration, info.isActive = 0, 0, false
            assert.are.equal(0, cdAdapter().GetSpellCooldownRemaining(100))
        end)

        it("uses isActive when the times are secret (run 2 in combat)", function()
            info.startTime, info.duration, info.modRate = secret(), secret(), secret()
            assert.is_nil(cdAdapter().GetSpellCooldownRemaining(100))
            info.isActive = false
            assert.are.equal(0, cdAdapter().GetSpellCooldownRemaining(100))
        end)

        it("without C_Secrets, skips the times in combat and uses isActive (D-036)", function()
            local inCombat = true
            local Adapter = loadAdapter({
                issecretvalue = checker,
                C_Secrets = false,
                InCombatLockdown = function()
                    return inCombat
                end,
                C_Spell = { GetSpellCooldown = function()
                    return info
                end },
            })
            assert.is_nil(Adapter.GetSpellCooldownRemaining(100))
            info.isActive = false
            assert.are.equal(0, Adapter.GetSpellCooldownRemaining(100))
            inCombat = false
            info.isActive = true
            assert.are.equal(10, Adapter.GetSpellCooldownRemaining(100))
        end)

        it("skips the times when ShouldCooldownsBeSecret is true", function()
            cooldownsSecret = true
            assert.is_nil(cdAdapter().GetSpellCooldownRemaining(100))
            info.isActive = false
            assert.are.equal(0, cdAdapter().GetSpellCooldownRemaining(100))
        end)
    end)

    describe("rage and health", function()
        it("returns nil when C_Secrets says power and health are secret (run 2: always)", function()
            local Adapter = loadAdapter({
                issecretvalue = checker,
                C_Secrets = {
                    ShouldUnitPowerBeSecret = function()
                        return true
                    end,
                    ShouldUnitHealthMaxBeSecret = function()
                        return true
                    end,
                },
                UnitPower = function()
                    error("must not be called")
                end,
                UnitPowerMax = function()
                    return 100
                end,
                UnitHealth = function()
                    error("must not be called")
                end,
                UnitHealthMax = function()
                    return 100
                end,
            })
            assert.is_nil(Adapter.GetRage())
            assert.is_nil(Adapter.GetHealthPct("target"))
        end)

        it("returns plain values when readable", function()
            local Adapter = loadAdapter({
                issecretvalue = checker,
                UnitPower = function()
                    return 35
                end,
                UnitPowerMax = function()
                    return 100
                end,
                UnitHealth = function()
                    return 25
                end,
                UnitHealthMax = function()
                    return 100
                end,
            })
            assert.are.same({ 35, 100 }, { Adapter.GetRage() })
            assert.are.equal(0.25, Adapter.GetHealthPct("target"))
        end)
    end)

    describe("target, stance, auto-attack", function()
        it("reports a living attackable target as hostile and a dead one as not", function()
            local dead = false
            local Adapter = loadAdapter({
                issecretvalue = checker,
                UnitExists = function()
                    return true
                end,
                UnitCanAttack = function()
                    return true
                end,
                UnitIsDeadOrGhost = function()
                    return dead
                end,
            })
            assert.are.same({ true, true }, { Adapter.GetTargetState() })
            dead = true
            assert.are.same({ true, false }, { Adapter.GetTargetState() })
        end)

        it("reports no target as false, false", function()
            local Adapter = loadAdapter({
                UnitExists = function()
                    return false
                end,
                UnitCanAttack = function()
                    return false
                end,
            })
            assert.are.same({ false, false }, { Adapter.GetTargetState() })
        end)

        it("names the stance from GetShapeshiftFormInfo's spellID (run 2: 2457 Battle Stance)", function()
            local Adapter = loadAdapter({
                GetShapeshiftForm = function()
                    return 1
                end,
                GetShapeshiftFormInfo = function()
                    return 132349, true, true, 2457
                end,
                C_Spell = { GetSpellName = function(id)
                    return id == 2457 and "Battle Stance" or nil
                end },
            })
            assert.are.same({ 1, "Battle Stance" }, { Adapter.GetStance() })
        end)

        it("checks auto-attack with IsCurrentSpell(6603)", function()
            local asked
            local Adapter = loadAdapter({ C_Spell = { IsCurrentSpell = function(id)
                asked = id
                return true
            end } })
            assert.is_true(Adapter.IsAutoAttacking())
            assert.are.equal(6603, asked)
        end)
    end)

    describe("GetRestrictionFlags (D-045)", function()
        local states

        local function restrictionAdapter()
            return loadAdapter({
                Enum = {
                    AddOnRestrictionType = {
                        Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5,
                    },
                    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
                },
                C_RestrictedActions = { GetAddOnRestrictionState = function(restrictionType)
                    return states[restrictionType] or 0
                end },
            })
        end

        it("ignores the Combat restriction that every open-world fight activates", function()
            states = { [0] = 2 }
            assert.are.same({ false, false, false }, { restrictionAdapter().GetRestrictionFlags() })
        end)

        it("reports Encounter, ChallengeMode and PvPMatch when Active", function()
            states = { [1] = 2, [3] = 2 }
            assert.are.same({ true, false, true }, { restrictionAdapter().GetRestrictionFlags() })
            states = { [1] = 1 } -- Activating is not Active
            assert.are.same({ false, false, false }, { restrictionAdapter().GetRestrictionFlags() })
        end)

        it("returns nil when C_RestrictedActions is missing", function()
            assert.is_nil(loadAdapter({ C_RestrictedActions = false }).GetRestrictionFlags())
        end)
    end)

    describe("normalised events", function()
        it("passes readable UNIT_COMBAT fields through and drops secret ones", function()
            local Adapter = loadAdapter({ issecretvalue = checker })
            assert.are.same({ "player", "PARRY", "", 0 }, { Adapter.ReadUnitCombat("player", "PARRY", "", 0, 1) })
            assert.are.same({ "target", "WOUND" }, { Adapter.ReadUnitCombat("target", "WOUND", secret(), secret()) })
            assert.is_nil(Adapter.ReadUnitCombat(secret(), "PARRY", "", 0))
        end)

        it("reads an own cast's unit and spellID", function()
            local Adapter = loadAdapter({ issecretvalue = checker })
            assert.are.same({ "player", 6673 }, { Adapter.ReadSpellcast("player", "Cast-1", 6673) })
            assert.is_nil(Adapter.ReadSpellcast("player", "Cast-1", secret()))
        end)
    end)
end)
