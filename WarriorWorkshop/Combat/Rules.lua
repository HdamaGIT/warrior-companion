local addonName, ns = ...

-- Rule engine (SPEC_V2 §7.1, D-019, D-048). Pure: compiles declarative rule definitions against the spell map and
-- sparse user overrides (D-039), then evaluates them over a snapshot. No WoW globals, no SavedVariables reads: the
-- caller passes overrides and spell IDs in.
--
-- Evaluation: the first state whose conditions are all true is the candidate (three-valued AND: unknown hides,
-- D-020). A candidate must hold for `delay` seconds before it shows; hiding is immediate. The visible state changes at
-- most once per `throttle` seconds. Rules outside their contexts, or while restricted or dead, are hidden.
local Conditions = ns.Conditions

local Rules = {}
ns.Rules = Rules

Rules.SEVERITIES = { reactive = true, expiring = true, dropped = true }
Rules.DISPLAYS = { strip = true, big = true, badge = true }
Rules.DEFAULT_CONTEXTS = { "openWorld", "instance" }

-- Which argument of each condition names an ability, and whether it needs spell reads or an aura read.
local SPELL_ARG = { spellUsable = 1, cooldownReady = 1, inRange = 1, notInRange = 1 }
local AURA_ARGS = { auraMissing = true, auraExpiringWithin = true, auraStacksBelow = true }

local function resolveArg(value, def, args)
    if value == "@ability" then
        return def.ability
    end
    if type(value) == "string" and string.sub(value, 1, 1) == "$" then
        return args[string.sub(value, 2)]
    end
    return value
end

local function mergeArgs(defaults, override)
    local args = {}
    for key, value in pairs(defaults or {}) do
        args[key] = value
    end
    if type(override) == "table" then
        for key, value in pairs(override) do
            if defaults and defaults[key] ~= nil and type(value) == type(defaults[key]) then
                args[key] = value
            end
        end
    end
    return args
end

-- Compiles one condition tuple. Returns the compiled condition or nil, reason, detail.
local function compileCondition(tuple, def, args, needs)
    local name = tuple[1]
    local fn = Conditions.evaluators[name]
    if not fn then
        return nil, "unknownCondition", tostring(name)
    end
    local a1, a2, a3 = resolveArg(tuple[2], def, args), resolveArg(tuple[3], def, args), resolveArg(tuple[4], def, args)
    if SPELL_ARG[name] then
        needs.spells[#needs.spells + 1] = a1
    elseif AURA_ARGS[name] then
        needs.auras[#needs.auras + 1] = { a1, a2 }
    end
    -- Aura timers change a condition's answer with no game event; Evaluate reports when (retryIn).
    if name == "auraExpiringWithin" and type(a3) == "number" then
        needs.timed[#needs.timed + 1] = { a1, a2, a3 }
    elseif name == "auraMissing" then
        needs.timed[#needs.timed + 1] = { a1, a2, 0 }
    end
    return { fn, a1, a2, a3 }
end

local function abilityKnown(name, spellIDs)
    return type(name) == "string" and spellIDs[name] ~= nil
end

-- Compiles one rule. Returns the compiled rule (or nil) and, if disabled, reason and detail.
local function compileRule(def, override, spellIDs)
    if override and override.enabled == false then
        return nil, "disabled"
    end
    if def.enabled == false and not (override and override.enabled == true) then
        return nil, "disabled"
    end
    if not abilityKnown(def.ability, spellIDs) then
        return nil, "unknownAbility", tostring(def.ability)
    end
    local args = mergeArgs(def.args, override and override.args)
    local needs = { spells = {}, auras = {}, timed = {} }
    local stateDefs = def.states or { { name = def.severity, when = def.when or {} } }
    local states = {}
    for index, stateDef in ipairs(stateDefs) do
        local conditions = {}
        for _, tuple in ipairs(stateDef.when or {}) do
            local compiled, reason, detail = compileCondition(tuple, def, args, needs)
            if not compiled then
                return nil, reason, detail
            end
            conditions[#conditions + 1] = compiled
        end
        local severity = stateDef.severity or (Rules.SEVERITIES[stateDef.name] and stateDef.name) or def.severity
        states[index] = { name = stateDef.name or def.severity, severity = severity, conditions = conditions }
    end
    for _, name in ipairs(needs.spells) do
        if not abilityKnown(name, spellIDs) then
            return nil, "unknownAbility", tostring(name)
        end
    end
    local contexts = {}
    for _, zone in ipairs(def.contexts or Rules.DEFAULT_CONTEXTS) do
        contexts[zone] = true
    end
    local rule = {
        id = def.id, label = def.label, ability = def.ability, spellID = spellIDs[def.ability],
        display = Rules.DISPLAYS[def.display] and def.display or "strip",
        countdown = def.countdown, contexts = contexts, states = states, args = args, timed = needs.timed,
        delay = type(def.delay) == "number" and def.delay or 0,
        throttle = type(def.throttle) == "number" and def.throttle or 0,
        -- runtime
        candidate = 0, candidateSince = 0, shown = 0, changedAt = nil, shownSeconds = nil,
    }
    -- Preallocated output entry, refilled in place (no allocation in Evaluate).
    rule.entry = { id = rule.id, label = rule.label, ability = rule.ability, spellID = rule.spellID,
        display = rule.display, state = nil, severity = nil, remaining = nil }
    return rule, nil, nil, needs
end

local function addNeeds(total, seenSpells, seenAuras, needs)
    for _, name in ipairs(needs.spells) do
        if not seenSpells[name] then
            seenSpells[name] = true
            total.spells[#total.spells + 1] = name
        end
    end
    for _, pair in ipairs(needs.auras) do
        local key = tostring(pair[1]) .. "\0" .. tostring(pair[2])
        if not seenAuras[key] then
            seenAuras[key] = true
            total.auras[#total.auras + 1] = pair
        end
    end
end

--- Compiles a rule pack. Pure.
-- @param pack array of rule definitions (SPEC_V2 §7.1 schema)
-- @param overrides table|nil { [ruleID] = { enabled = bool, args = { ... } } } (sparse, D-039)
-- @param spellIDs table { [abilityName] = spellID } for known abilities (SpellMap)
-- @return compiled { rules = array, needs = { spells, auras }, disabled = array of { id, reason, detail } }
function Rules.Compile(pack, overrides, spellIDs)
    local compiled = { rules = {}, needs = { spells = {}, auras = {} }, disabled = {} }
    local seenSpells, seenAuras = {}, {}
    for _, def in ipairs(pack) do
        local rule, reason, detail, needs = compileRule(def, overrides and overrides[def.id], spellIDs or {})
        if rule then
            compiled.rules[#compiled.rules + 1] = rule
            addNeeds(compiled.needs, seenSpells, seenAuras, needs)
        else
            compiled.disabled[#compiled.disabled + 1] = { id = def.id, reason = reason, detail = detail }
        end
    end
    return compiled
end

--- Lists every ability name a rule pack refers to (rule abilities and ability arguments of conditions), so they can
-- be registered with the SpellMap before it resolves. Pure.
-- @param pack array of rule definitions
-- @return array of names, in first-seen order
function Rules.AbilityNames(pack)
    local names, seen = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "@ability" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    for _, def in ipairs(pack) do
        add(def.ability)
        for _, stateDef in ipairs(def.states or { { when = def.when or {} } }) do
            for _, tuple in ipairs(stateDef.when or {}) do
                local name = tuple[1]
                if SPELL_ARG[name] then
                    add(tuple[2])
                elseif AURA_ARGS[name] then
                    add(tuple[3])
                end
            end
        end
    end
    return names
end

-- Seconds until one of a rule's aura timers crosses its threshold, or nil.
local function nextTimedChange(rule, snapshot)
    local soonest
    local timed = rule.timed
    for index = 1, #timed do
        local item = timed[index]
        local byUnit = snapshot.auras and snapshot.auras[item[1]]
        local aura = byUnit and byUnit[item[2]]
        if aura and aura.state and aura.remaining and aura.remaining ~= math.huge then
            local wait = aura.remaining - item[3]
            if wait > 0 and (soonest == nil or wait < soonest) then
                soonest = wait
            end
        end
    end
    return soonest
end

local function wholeSeconds(value)
    if value == nil or value == math.huge then
        return nil
    end
    return math.ceil(value)
end

--- Evaluates every compiled rule. Pure apart from the rules' runtime fields and the output array.
-- @param compiled table from Rules.Compile
-- @param snapshot table (Combat/Snapshot.lua)
-- @param context table { zone, restricted, dead } (Core/Context.lua)
-- @param now number session time
-- @param out array refilled with the visible entries in rule order; trailing slots are cleared
-- @return count (number of entries), changed (boolean: anything visible changed, including a countdown's
--   whole seconds), retryIn (number|nil: seconds until a delayed or throttled change could apply, or an aura timer
--   crosses a threshold; the caller re-evaluates then if nothing else does)
function Rules.Evaluate(compiled, snapshot, context, now, out)
    local count, changed, retryIn = 0, false, nil
    local allowed = context and not context.restricted and not context.dead
    local rules = compiled.rules
    for index = 1, #rules do
        local rule = rules[index]
        local candidate = 0
        if allowed and rule.contexts[context.zone] then
            for stateIndex = 1, #rule.states do
                if Conditions.All(rule.states[stateIndex].conditions, snapshot) == true then
                    candidate = stateIndex
                    break
                end
            end
            local wait = nextTimedChange(rule, snapshot)
            if wait then
                retryIn = (retryIn == nil or wait < retryIn) and wait or retryIn
            end
        end
        if candidate ~= rule.candidate then
            rule.candidate, rule.candidateSince = candidate, now
        end
        local wanted = 0
        if candidate > 0 then
            local held = now - rule.candidateSince
            if held >= rule.delay then
                wanted = candidate
            else
                wanted = rule.shown
                local wait = rule.delay - held
                retryIn = (retryIn == nil or wait < retryIn) and wait or retryIn
            end
        end
        if wanted ~= rule.shown then
            local since = rule.changedAt and (now - rule.changedAt) or math.huge
            if since >= rule.throttle then
                rule.shown, rule.changedAt = wanted, now
                changed = true
            else
                local wait = rule.throttle - since
                retryIn = (retryIn == nil or wait < retryIn) and wait or retryIn
            end
        end
        if rule.shown > 0 then
            local state = rule.states[rule.shown]
            local entry = rule.entry
            entry.state, entry.severity = state.name, state.severity
            local remaining
            if rule.countdown then
                local byUnit = snapshot.auras and snapshot.auras[rule.countdown]
                local aura = byUnit and byUnit[rule.ability]
                remaining = aura and aura.state and aura.remaining or nil
            end
            entry.remaining = remaining
            local seconds = wholeSeconds(remaining)
            if seconds ~= rule.shownSeconds then
                rule.shownSeconds = seconds
                changed = true
            end
            count = count + 1
            out[count] = entry
        else
            rule.shownSeconds = nil
        end
    end
    for index = count + 1, #out do
        out[index] = nil
    end
    return count, changed, retryIn
end

--- Hides every rule at once (suspend). Pure apart from runtime fields.
-- @param compiled table
-- @return boolean true if anything was visible
function Rules.Reset(compiled)
    local any = false
    for _, rule in ipairs(compiled.rules) do
        if rule.shown > 0 then
            any = true
        end
        rule.shown, rule.candidate, rule.changedAt, rule.shownSeconds = 0, 0, nil, nil
    end
    return any
end
