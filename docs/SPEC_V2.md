# Warrior Workshop — Specification and Build Plan (v2)

| | |
|---|---|
| **Document** | `docs/SPEC_V2.md` |
| **Version** | 2.1 (beta run 2 findings: D-035, D-044–D-046; 10 Oct 2026) |
| **Date** | 9 October 2026 |
| **Owner** | Hugh |
| **Target client** | World of Warcraft: Forever (beta to 21 Oct 2026; launch 4 Nov 2026) |
| **Supersedes** | `docs/SPEC.md` v0.1 (8 Oct 2026) and `docs/SPEC_LEVELLING.md` v0.1 (9 Oct 2026, if present) |
| **Backlog** | `docs/IDEAS_BACKLOG.md` — triaged idea list; items rated 3 or Pass are not in this spec |
| **Status** | Approved for build from the current milestone onwards |

---

## 0. How to use this document

This is the single source of truth for the Warrior Workshop add-on. Claude Code reads it at the start of every build session, alongside `CLAUDE.md`, `docs/HANDOFF.md` and `docs/DECISIONS.md`.

- **Section 3** is the roadmap; **Section 15** is the build plan with milestones, acceptance criteria and human checkpoints. Section 16 maps old milestone numbers to new ones.
- Anything marked **[VERIFY]** depends on Forever API behaviour not yet confirmed. Do not build hard dependencies on a [VERIFY] item until its result is recorded in `docs/PROBE_RESULTS.md` and, where it changes scope, in `docs/DECISIONS.md`.
- Where this spec and the code disagree, the spec wins unless a later entry in `docs/DECISIONS.md` says otherwise.
- Backlog item IDs (e.g. `U-01`, `A-02`) are referenced throughout so features trace back to the triage.

### 0.1 What changed from v0.1

| Change | Why |
|---|---|
| Product re-centred on a **warrior combat companion**, a **tank announcer** and **gear keybinds**, delivered before the original professions/itemisation scope ("Workshop") | Hugh's triage: highest value in levelling and grouping from launch day |
| In-combat features are now in scope **in the open world and dungeon trash**; they suspend in restricted contexts | On Midnight's rules, restrictions apply only in boss encounters and Mythic+ |
| Levelling analytics (XP dashboard, session review, mob intel, fight log) **removed** | Triage: Pass |
| Swing timer **removed** | Triage: Pass — Hugh reports a built-in swing timer [VERIFY V-31] |
| Pull check, death recap and other survival tooling moved to backlog | Triage: 3 |
| Probe extended with combat, chat, gear-set, macro and keybinding checks | New tracks depend on them |
| Workshop scope (professions planner, gear advisor, readiness) retained, moved after the combat/announce/gear tracks; tank stat sheet added to the gear advisor | Still wanted; less urgent |
| Saved data moves to schema 2: `hideInCombat` → `hideMainInCombat`, v1 `gear` (stat-weight profiles) → `advisor`, new `combat`/`announce`/`gear` sections; a v1→v2 migration does this | New tracks need the `gear` name; no user data dropped (D-029) |

---

## 1. Vision and principles

**Vision.** A warrior-centric class support add-on for WoW: Forever that uses the game's add-on capabilities to their fullest within Blizzard's rules: combat signposting while levelling and tanking, a tank announcer, gear-set control, and later profession and itemisation planning.

**Questions the add-on answers**

1. *In combat:* "What should I be reacting to right now, and has anything important dropped?"
2. *In a group:* "Does my group know what I've just done or what just failed?"
3. *Between pulls:* "Am I in the right gear, one key press away from the next set?"
4. *Later (Workshop):* "What is the cheapest next step that makes me stronger and levels my professions?"

**Design principles**

1. **Open world first; suspend when restricted.** Combat features target open-world play and dungeon trash. In boss encounters, Mythic+ or anything Forever restricts, they suspend cleanly: no errors, no stale displays, a small "suspended" badge.
2. **Display, don't decide.** Alerts highlight reactive windows, upkeep and failures. No "press this next" rotation engine.
3. **Secret-safe by construction.** Every combat value passes through an Adapter accessor that checks secrecy first. A secret or unavailable value returns `nil`; any condition depending on it is **unknown**, and unknown means **not shown**. Nothing errors on a secret value.
4. **Rules as data.** Alerts and announcements are declarative tables evaluated by small engines. Forever's revamped warrior kit is mapped by editing tables, not code. No `loadstring`, no user Lua.
5. **Respect protected actions.** Anything Blizzard protects (equipping armour in combat, SAY/YELL outdoors, binding changes in combat) goes through keybinds, secure buttons or out-of-combat paths only. No workarounds.
6. **Thin API adapter.** All Blizzard data API calls go through `Core/Adapter.lua`; secure frames and bindings live in a single `Core/Secure.lua`.
7. **Observe, don't hardcode.** Abilities are resolved by name at login and auto-disabled if unknown. Stat weights, thresholds and messages are configuration with labelled placeholders.
8. **Check the built-ins.** Where Blizzard ships a tool (Cooldown Manager, swing timer, floating combat text, loss-of-control frame), confirm in the beta before building a duplicate.
9. **Zero external libraries** (Ace3, LibStub etc.) until a decision says otherwise.

---

## 2. Platform constraints

### 2.1 Facts (publicly reported)

- Forever shares Mainline WoW's UI architecture, including most APIs available in patch 12.1.5 (Midnight).
- Midnight introduced **secret values**: combat state can be displayed by add-ons but not read or branched on.
- Restrictions apply **during boss encounters and Mythic+**; open-world combat is unaffected (Blizzard's 2026 relaxation).
- In restricted contexts, `COMBAT_LOG_EVENT_UNFILTERED` is unavailable to add-ons and add-on communication is blocked.
- The player's own spell casts remain detectable; the player's own cooldowns are secret in restricted contexts.
- Blizzard ships a built-in Cooldown Manager and damage meter in Forever.
- Classic-era add-ons do not run; add-ons target the Mainline API.
- Long-standing Retail rules: armour cannot be changed in combat; `SendChatMessage` to SAY/YELL outside instances requires a hardware event (key press or click); key bindings cannot be changed in combat; secure frames cannot be created or modified in combat.

### 2.2 Inferences

- Profession and item APIs follow the Mainline `C_TradeSkillUI`, `C_Container`, `C_Item`, `C_Spell`, `C_UnitAuras` namespaces.
- Recipe difficulty is a relative-difficulty field, not numeric thresholds. Bank contents are readable only while the bank is open.
- Weapon swaps in combat are possible through secure action buttons (`/equip`, `/equipslot`) triggered by a key press.

### 2.3 Verification register [VERIFY]

**Answered or answerable by the existing probe (M1):**

| ID | Question | Used by |
|---|---|---|
| V-01 | Interface number for `.toc`; client folder name | Everything |
| V-02 | `C_TradeSkillUI` functions and recipe info fields | Workshop planner |
| V-03 | Craft-completion event; skill-up signal | Craft log |
| V-04 | `C_Item.GetItemStats` keys | Gear advisor |
| V-05 | `C_EquipmentSet` exists and works | Gear sets, readiness |
| V-06 | `ENCOUNTER_START`/`END` fire for add-ons | Context (restricted detection) |
| V-07 | Own `UNIT_SPELLCAST_SUCCEEDED` readable in encounters | Announcer in encounters |
| V-08 | Add-on messages during encounters | Later raid features |
| V-09 | Tagged party/raid chat readable during encounters | Later raid features |
| V-10 | `issecretvalue` exists; which values are secret where | Everything combat |

**Added by the probe extension (M3):**

| ID | Question | Used by |
|---|---|---|
| V-11 | Open world: target health readable (`UnitHealth`/`UnitHealthMax` or %) | Execute |
| V-12 | Open world: player rage readable | Rage conditions |
| V-13 | Open world: own spell cooldowns readable (`C_Spell.GetSpellCooldown`) | Cooldown tracker, conditions |
| V-14 | `C_Spell.IsSpellUsable` reflects Overpower/Revenge/Execute windows | Reactive alerts |
| V-15 | Player and target auras readable via `C_UnitAuras`, with duration/expiry and source | Battle Shout, Sunder, Rend, Hamstring, Thunder Clap |
| V-16 | Open world: CLEU unavailable (D-035), UNIT_COMBAT is the source. Originally: CLEU fires; fields readable; miss types (DODGE, PARRY, BLOCK, RESIST, IMMUNE) present | Avoidance detector, announcer |
| V-17 | Target casting info incl. not-interruptible flag | Interrupt prompt |
| V-18 | `C_Spell.IsSpellInRange` for Charge/Intercept | Charge range |
| V-19 | Nameplate units expose level/classification/reaction/threat | Threat lead (backlog) |
| V-21 | A direct "restricted context" signal exists | Context |
| V-22 | Forever warrior kit at levels 1–20+: spell names and IDs for Overpower, Revenge, Execute, Charge, Intercept, Pummel, Shield Bash, Battle Shout, Demoralising Shout, Thunder Clap, Rend, Sunder Armor, Hamstring, Taunt, Mocking Blow, Challenging Shout, Shield Wall, Last Stand, Disarm, Intimidating Shout, Bloodrage, Berserker Rage; stances | Rule packs, announcer, macros |
| V-23 | `C_Spell.IsCurrentSpell` readable | Auto-attack detection |
| V-24 | `TRAINER_SHOW` exposes services with level requirements | Trainer reminder |
| V-25 | **Chat sending from an event handler (no key press):** PARTY, RAID, INSTANCE_CHAT in open world and dungeon trash; SAY/YELL outdoors (expected blocked) and inside an instance | Announcer |
| V-26 | Chat sending during a boss encounter | Announcer suspend rules |
| V-27 | `C_EquipmentSet.UseEquipmentSet` out of combat; what happens if called in combat | Gear sets |
| V-28 | Secure action button with `/equip` or `/equipslot` macrotext, bound via `SetBindingClick`, swaps weapons in combat | In-combat weapon swap |
| V-29 | `CreateMacro`/`EditMacro` work; macro slot limits (account and character) | Macro generator |
| V-30 | Custom bindings declared in `Bindings.xml` appear in the Key Bindings UI; `SetBinding`/`SetBindingClick` persist | Gear keybinds |
| V-31 | **Built-ins:** what the Cooldown Manager can show for a warrior; whether a swing timer exists; floating combat text options for parry/dodge/block; loss-of-control frame | Build-or-skip decisions |
| V-32 | Party unit auras (`party1`–`party4`) readable in open world and instances; `UnitInRange` readable | Battle Shout party coverage |
| V-33 | Tank stat APIs: `GetDodgeChance`, `GetParryChance`, `GetBlockChance`, defense/armour, and any Forever-specific stats | Tank stat sheet |

(V-20, XP events, is retired with the analytics scope.)

Results: see `docs/PROBE_RESULTS.md` (runs 1–2) and the decision gate (D-044).

---

## 3. Roadmap

| Phase | Name | Contents | Status |
|---|---|---|---|
| **A** | Foundations | M0 scaffold, M1 probe, M2 core, M3 probe extension, M4 inventory | M0–M3 built; beta runs 1–2 done (9–10 Oct); group run pending |
| **B** | Combat companion | M5 combat core + must-have alerts; M6 main window, config and should-have alerts | Build next |
| **C** | Announcer | M7 tank announcer | Build |
| **D** | Gear control | M8 gear sets, keybinds, swap queue, weapon swap, macro generator | Build |
| — | **Launch kit release** | M9 hardening, `v0.5.0` | Build |
| **E** | Workshop | M10 professions, M11 prices and planner, M12 planner tab, M13 gear advisor + tank stat sheet, M14 readiness, M15 `v1.0.0` | Build after D |
| **F** | Later | Backlog items rated 3; raid coordination (cooldown plans, assignments, Python analysis loop) | Outline only (§17) |

**Launch target (4 November 2026):** M5 complete (without X-06 combat text and R-06 unless V-31 shows the built-ins cannot cover them, D-043), M7 core (A-01 to A-04, A-07) complete. M6 and M8 within the first week or two after launch. Workshop in the weeks after.

---

## 4. Repository structure

```
warrior-workshop/
├── README.md
├── CLAUDE.md
├── LICENSE
├── .gitignore  .editorconfig  .luacheckrc  .busted
├── .github/workflows/ci.yml, release.yml
├── docs/
│   ├── SPEC_V2.md                # this document
│   ├── SPEC.md                   # v0.1, superseded
│   ├── IDEAS_BACKLOG.md          # triaged ideas
│   ├── DECISIONS.md
│   ├── HANDOFF.md
│   ├── PROBE_RESULTS.md
│   ├── DEV_SETUP.md
│   └── verification/M<n>.md
├── WarriorWorkshop/
│   ├── WarriorWorkshop.toc
│   ├── Bindings.xml              # gear set + weapon swap bindings (M8)
│   ├── Core/
│   │   ├── Init.lua  Events.lua  DB.lua  Migrations.lua  Log.lua  Util.lua
│   │   ├── Adapter.lua           # ALL Blizzard data API calls
│   │   ├── Secure.lua            # secure buttons, bindings, macro writes (M8)
│   │   ├── Context.lua           # openWorld / instance / restricted / inCombat (M5)
│   │   └── SpellMap.lua          # resolve ability names → spellIDs at login (M5)
│   ├── Combat/
│   │   ├── Snapshot.lua          # per-tick read model of combat state
│   │   ├── Conditions.lua        # pure condition evaluators
│   │   ├── Rules.lua             # rule engine
│   │   ├── AuraTracker.lua       # own-cast aura timers when auras are secret (U-01, D-048)
│   │   ├── Companion.lua         # module wiring: events, 0.2s ticker, suspend (D-048)
│   │   ├── Avoidance.lua         # shared parry/dodge/block/resist detector (UNIT_COMBAT)
│   │   └── RulePacks/WarriorDefault.lua
│   ├── Announce/
│   │   ├── Announcer.lua         # event → message → channel routing
│   │   └── Events.lua            # announce event definitions
│   ├── Gear/
│   │   ├── Sets.lua              # set list, apply, queue
│   │   └── Macros.lua            # macro templates + generator
│   ├── Modules/                  # Workshop (Phase E)
│   │   ├── Inventory.lua  Professions.lua  Prices.lua  Planner.lua
│   │   ├── Advisor.lua           # gear advisor + tank stat sheet
│   │   └── Readiness.lua
│   ├── UI/
│   │   ├── MainFrame.lua  Widgets.lua
│   │   ├── HUD/HUD.lua  # shared lifecycle, unlock/lock, positions, /ww hud commands (D-048)
│   │   ├── HUD/AlertStrip.lua  HUD/BigAlert.lua  HUD/CombatText.lua  HUD/Badges.lua
│   │   ├── Tabs/AlertsTab.lua  Tabs/AnnounceTab.lua  Tabs/SetsTab.lua
│   │   └── Tabs/PlannerTab.lua  Tabs/UpgradesTab.lua  Tabs/ReadyTab.lua   # Phase E
│   └── Locale/enUS.lua
├── WarriorWorkshopProbe/         # M1 + M3
├── tests/
│   ├── helpers/mock_adapter.lua  helpers/replay.lua  helpers/mock_clock.lua
│   ├── fixtures/                 # items, recipes, inventory, streams/*.lua
│   └── *_spec.lua
└── tools/
    ├── sim/                      # offline client simulator (D-011); tests run in CI
    ├── wowdev.py                 # install into the client, collect SavedVariables (D-034)
    └── analysis/README.md        # placeholder (Phase F)
```

Placeholder files for later phases are fine; do not implement ahead of the current milestone. The v0.1 placeholders moved to this layout: `Modules/Gear.lua` → `Modules/Advisor.lua`, `UI/*Tab.lua` → `UI/Tabs/` (D-029).

---

## 5. Architecture

### 5.1 Layers

```
UI (HUD frames, main window tabs)        reads view-models; subscribes to WW_* messages
   ▲
Feature modules                           Combat, Announce, Gear, Workshop modules
   (pure logic over snapshots/events)     testable with mock Adapter + replay harness
   ▲
Core                                      Events, DB, Context, SpellMap,
                                          Adapter (data APIs), Secure (protected UI)
```

Rules:

- **Only `Core/Adapter.lua` calls Blizzard data APIs. Only `Core/Secure.lua` creates secure frames, sets bindings or writes macros.** UI files may use frame APIs for non-secure display frames.
- Feature logic is pure over explicit inputs: snapshots, normalised events, configuration. No hidden SavedVariables reads in evaluators, scorers or rankers.
- Every file starts `local addonName, ns = ...`. No new globals except SavedVariables tables, `BINDING_*` strings required by `Bindings.xml`, binding handler functions and slash commands.
- Modules: `ns:NewModule(name)` with `OnInitialize` (after SavedVariables) and `OnEnable` (at `PLAYER_LOGIN`). Game events via `ns.Events:On(...)`; internal messages prefixed `WW_` via `ns.Events:Fire(...)`. UI listens to `WW_*` only.
- `.toc` load order: Locale → Core → Combat → Announce → Gear → Modules → UI.

### 5.2 Context (`Core/Context.lua`)

Publishes `WW_CONTEXT_CHANGED` with `{ zone = "openWorld"|"instance", restricted = bool, inCombat = bool, dead = bool, group = "solo"|"party"|"raid" }`.

| Flag | Detection |
|---|---|
| `instance` | `IsInInstance()` party/raid |
| `restricted` | `C_RestrictedActions.GetAddOnRestrictionState` reports Encounter (1), ChallengeMode (2) or PvPMatch (3) Active (`Enum.AddOnRestrictionType`), plus the existing encounter/M+ signals (`ENCOUNTER_START` without `ENCOUNTER_END`, Mythic+ active). A secret value never sets `restricted`; it only makes that value unknown (D-033, D-049). Type 0 (Combat) is the normal state of every fight and does not suspend anything (D-045) |
| `inCombat` | `PLAYER_REGEN_DISABLED` → `PLAYER_REGEN_ENABLED` |
| `dead` | `PLAYER_DEAD` → `PLAYER_ALIVE`/`PLAYER_UNGHOST` |
| `group` | `IsInRaid()` / `IsInGroup()` |

Combat and Announce modules suspend while `restricted`.

### 5.3 Spell map (`Core/SpellMap.lua`)

Resolves ability **names** (from rule packs, announce events and macro templates) to spellIDs at login and on `SPELLS_CHANGED`/`LEARNED_SPELL_IN_TAB`. Unknown names are reported in the config UI and their dependants auto-disabled. Manual ID overrides are allowed in SavedVariables.

### 5.4 Adapter surface

**Workshop (Phase E)** — unchanged from v0.1:

| Function | Returns |
|---|---|
| `GetBuildInfo()` | `{ version, build, interface }` |
| `InCombat()` | boolean |
| `GetBagContents()` / `GetBankContents()` | `{ [itemID] = count }` / or `nil` if bank closed |
| `GetEquipped()` | `{ [slotID] = { itemID, link } }` |
| `GetDurability()` | `{ [slotID] = { cur, max } }` |
| `GetItemStats(link)` | normalised stat table (§5.6) |
| `GetItemBasics(itemID, cb)` | async item info |
| `IsUsableByPlayer(itemID)` | boolean |
| `GetOpenProfession()` / `GetKnownRecipes()` | profession and recipes |
| `GetEquipmentSets()` | `{ [name] = { id, icon, [slotID] = itemID } }` or `nil` |
| `Print(msg)` | prefixed chat output (local) |

**Combat (Phase B/C)** — all return plain values or `nil` (unknown); **each checks `issecretvalue` first**:

| Function | Returns |
|---|---|
| `GetRage()` | `cur, max` or `nil` |
| `GetHealthPct(unit)` | 0–1 or `nil` |
| `IsSpellUsable(spellID)` | `usable, noPower` or `nil` |
| `GetSpellCooldownRemaining(spellID)` | seconds or `nil` |
| `IsSpellInRange(spellID, unit)` | boolean or `nil` |
| `IsCurrentSpell(spellID)` | boolean or `nil` |
| `IsAutoAttacking()` | boolean or `nil` via `IsCurrentSpell(6603)`: Auto Attack does not resolve by name, so its ID is the one documented exception to "no hardcoded spell IDs" (V-23, D-048) |
| `GetAura(unit, auraName, filter)` | by **name**, because ranks have different IDs; `stacks, remaining, sourceIsPlayer, duration` (multiple returns, D-036), `false` (absent) or `nil` (unknown) (D-048) |
| `GetCasting(unit)` | `spellID, name, interruptible, remaining` (multiple returns, D-036), `false` or `nil` |
| `GetStance()` | `index, name` or `nil` |
| `GetTargetState()` | `exists, hostile` (`UnitCanAttack` and not dead) or `nil` (D-048) |
| `GetSpellIcon(spellID)` / `PlaySound(kitName)` | icon file ID / plays a sound kit; keeps the UI free of data APIs (D-048) |
| `GetEquippedWeaponTypes()` | `{ mainHand, offHand, hasShield }` |
| `GetPartyUnits()` | array of `{ unit, inRange }` or `nil` |
| `SubscribeUnitCombat(handler)` | registers a `UNIT_COMBAT` handler (player and target) receiving a **normalised** event (`unit, action, amount, ...`); payload is readable in combat; no attacker identity (D-035) |
| `SendChat(msg, channel)` | sends to PARTY/RAID/INSTANCE_CHAT/SAY/YELL; returns `true`, or `false, reason` if blocked; never errors |
| `EquipSet(setID)` | `C_EquipmentSet.UseEquipmentSet`; out of combat only, returns `false, "combat"` otherwise (D-041) |

Before any aura or cooldown read, the Adapter checks the matching `C_Secrets.Should*BeSecret` and returns `nil` without calling; every call stays in `pcall` (D-045). Rage and health accessors exist but return `nil` while secret (D-044).

**Secure (`Core/Secure.lua`, Phase D)** — out of combat only; each call returns `false, "combat"` if attempted in combat:

| Function | Purpose |
|---|---|
| `CreateWeaponSwapButton(name, macrotext)` | secure action button for in-combat weapon swaps |
| `WriteMacro(name, icon, body, perCharacter)` | create or update a macro; returns slot or `false, reason` |

No `SetBinding*` calls: keys are assigned in Blizzard's Key Bindings UI against bindings declared in `Bindings.xml` (D-040).

### 5.5 Normalised combat events

The combat log is unavailable (`COMBAT_LOG_EVENT_UNFILTERED` and `CombatLogGetCurrentEventInfo` are absent, D-035). The Adapter converts `UNIT_COMBAT` (player, target) and own `UNIT_SPELLCAST_*` events into `{ t, kind, unit, action, spellID, spellName, amount, ... }` with secrecy pre-checked. Kinds used in v2: `UNIT_COMBAT` (action WOUND, MISS, DODGE, PARRY, BLOCK etc.) and `PLAYER_CAST_SUCCEEDED`. There is no source or destination GUID or name. This enables the **replay harness** (§13).

### 5.6 Normalised stat keys

`str, agi, sta, int, spi, armor, ap, crit, hit, haste, expertise, defense, dodge, parry, block, blockValue, weaponDps, weaponSpeed`. Unknown keys go to `other[rawKey]` and are logged once.

---

## 6. Data model (schema v2)

Two SavedVariables tables. If M2 shipped schema v1, add a migration `to = 2` that adds the new sections without touching existing data. Each migration has a unit test.

```lua
-- Account-wide
WarriorWorkshopDB = {
  schemaVersion = 2,
  settings = {
    debug = false, hideMainInCombat = true,     -- v1 `hideInCombat`, renamed by the v2 migration
    window = { point, x, y, w, h, tab = "alerts" },
    batchSize = ..., planner = { ... },         -- Phase E planner settings, kept from v1 (D-014)
  },
  -- Phase E
  prices = { [itemID] = { value, source, updatedAt } },
  calibration = { byDifficulty = { optimal = {attempts, gains}, medium = {...}, easy = {...}, trivial = {...} } },
}

-- Per character
WarriorWorkshopCharDB = {
  schemaVersion = 2,
  meta = { name, realm, classFile, level, lastSeen },

  combat = {
    enabled = true,
    hud = {
      locked = true,
      alertStrip = { point, x, y, scale = 1.0, maxIcons = 6 },
      bigAlert   = { point, x, y, scale = 1.5 },
      combatText = { point, x, y, scale = 1.0, show = { parry = true, dodge = true, block = true, crit = false } },
      badges     = { point, x, y },
    },
    alertStyle = {                    -- U-15
      expiring = { size = 64, flash = false, sound = nil },
      dropped  = { size = 128, flash = true,  sound = "RAID_WARNING" },
      reactive = { size = 48, glow = true,    sound = nil },
    },
    ruleOverrides = { [ruleID] = { enabled = bool, args = {...} } },
    spellOverrides = { [abilityName] = spellID },
  },

  announce = {
    enabled = true,
    throttle = { default = 2.0, avoidance = 5.0 },
    events = { [eventID] = { enabled = bool, channels = { solo = "self", party = "PARTY", raid = "RAID", instance = "INSTANCE_CHAT" }, text = nil } },
  },

  gear = {
    sets = { [slot 1..8] = { setID = n, name = "Tank" } },   -- keys live in Key Bindings (D-040)
    queued = nil,                     -- setID awaiting combat end; cleared at login (D-041)
    weaponSwaps = { [slot 1..4] = { name = "2H", macrotext = "/equipslot 16 ..." } },
    macros = { [templateID] = { enabled = bool, name, perCharacter = true } },
  },

  -- Phase E
  inventory = { bags = {}, bagsScannedAt, bank = {}, bankScannedAt },
  professions = { [skillLineID] = { name, rank, maxRank, scannedAt, recipes = {} } },
  targets = {}, craftLog = {}, colourObservations = {},
  advisor = { activeProfile = "dps", profiles = { dps = {...}, tank = {...} } },  -- v1 `gear` moves here
  readiness = { consumables = {}, durabilityAmber = 0.60, durabilityRed = 0.30, expectedSet = {} },
}
```

Ring buffers (craft log) evict oldest first. Corrupt or future schema versions: back up to a `_backup` field inside the same table (D-012), reinitialise, warn.

---

## 7. Phase B — Combat companion

### 7.1 Rule engine (`Combat/Rules.lua`, `Combat/Conditions.lua`, `Combat/Snapshot.lua`)

**Rule schema**

```lua
{
  id = "battleShout",
  label = "Battle Shout",
  ability = "Battle Shout",            -- resolved via SpellMap
  severity = "dropped",                -- maps to alertStyle: reactive | expiring | dropped
  states = {                           -- optional: first matching state wins
    { name = "dropped",  when = { { "auraMissing", "player", "@ability", true } } },
    { name = "expiring", when = { { "auraExpiringWithin", "player", "@ability", 10 } } },
  },
  when = nil,                          -- simple rules use `when` instead of `states`
  display = "big",                     -- strip | big | badge
  contexts = { "openWorld", "instance" },
  delay = nil,                         -- seconds the conditions must hold before the rule shows (S-04: 1.5) (D-048)
  throttle = 0.1,                      -- minimum seconds between visible state changes
}
```

**Condition vocabulary** (pure functions `(snapshot, args) → true | false | nil`; unknown → rule hidden):

| Condition | Args |
|---|---|
| `inCombat` / `outOfCombat` | — |
| `stance` | name |
| `spellUsable` | ability |
| `cooldownReady` | ability (≤ GCD remaining) |
| `rageAtLeast` | n |
| `targetHealthBelow` | 0–1 |
| `targetHostile` | — |
| `targetCasting` | `interruptible` |
| `auraMissing` | unit, ability, fromPlayer |
| `auraExpiringWithin` | unit, ability, seconds |
| `auraStacksBelow` | unit, ability, n |
| `inRange` / `notInRange` | ability, unit |
| `autoAttacking` | bool |
| `hasShield` | bool |
| `partyMissingAura` | ability, minCount |

In combat, `rageAtLeast`, `targetHealthBelow` and `targetCasting` are unavailable (rage, health and target casting are secret: value unknown, so condition unknown, so hidden; D-044). Aura conditions in combat may be satisfied by "tracked own cast" state (see U-01) when the real aura is unreadable.

New conditions require a spec change (guards against a WeakAuras clone).

**Evaluation.** Event-driven on `UNIT_POWER_UPDATE`, `UNIT_AURA` (player, target, party), `SPELL_UPDATE_USABLE`, `SPELL_UPDATE_COOLDOWN`, `UNIT_HEALTH` (target), `PLAYER_TARGET_CHANGED`, `UNIT_SPELLCAST_START/STOP` (target), `PLAYER_ENTER_COMBAT`/`PLAYER_LEAVE_COMBAT`, plus one shared 0.2s ticker for range and aura countdowns. Snapshot tables are reused; no allocation in hot paths.

### 7.2 Must-have alerts (M5)

| ID | Rule | Logic | Display |
|---|---|---|---|
| U-01, U-15 | **Battle Shout** | *Dropped*: in combat or targeting a hostile, player lacks Battle Shout → full-size flashing icon + sound. *Expiring*: ≤ 10s remaining → large icon with countdown. Thresholds configurable. **Gate (D-044): Degraded.** Track own Battle Shout casts (`UNIT_SPELLCAST_SUCCEEDED`) with the duration learned from the real aura out of combat; use the real aura whenever it is readable; in combat "dropped" only when the tracked timer runs out (cannot see dispels or other warriors' shouts) | big |
| R-03 | **Execute** | target hostile + health < 20% + Execute usable. **Gate: Degraded.** Target health is secret; use `IsSpellUsable(Execute)` alone | strip, glow |
| R-01 | **Overpower** | Overpower usable + ready. If not in Battle Stance, show a small stance hint. **Gate: Go** (usability only; window untested until level 12) | strip, glow |
| R-11 | **Interrupt** | target casting + interruptible + Pummel or Shield Bash ready (whichever the current stance/weapon allows). Optional "priority casts" list (heals, fears) shown with stronger glow. **Gate: No-go for launch** (target casting is secret); revisit if beta run 3 shows readable target cast events | strip |
| S-04 | **Auto-attack not running** | in combat + target hostile + in melee range + not auto-attacking for > 1.5s. **Gate: Go** | badge |
| X-01 | **Charge range** | out of combat + target hostile + Charge in range + ready (Intercept when in Berserker Stance). **Gate: Go** | badge |
| X-06 | **Local combat text** | from `Combat/Avoidance.lua`: show PARRY / DODGE / BLOCK (and optional crit) as large floating text near the character. **Gate: Degraded** (`UNIT_COMBAT`, no attacker name); off the launch target (D-043) | combatText |
| R-06 | **Core cooldown tracker** | icons for Mortal Strike / Bloodthirst / Shield Slam / Whirlwind (whichever known) with remaining time. **Gate:** build only if V-31 shows Blizzard's Cooldown Manager cannot cover this adequately; otherwise record a decision and configure the built-in instead. **Gate: No-go** (cooldown times are secret in combat); Blizzard's Cooldown Manager (`C_CooldownViewer`) exists | strip (secondary row) |

### 7.3 Should-have alerts (M6)

| ID | Rule | Logic |
|---|---|---|
| R-02 | Revenge | usable + ready |
| U-05 | Sunder Armor | stacks below N (default 5, configurable; off when solo by default) or ≤ 5s remaining. **No-go in combat** (target auras unreadable) unless tracked from own casts; revisit |
| U-06 | Rend | in combat + target lacks player's Rend + target health > 30%. **No-go in combat** (target auras and health unreadable) unless tracked from own casts; revisit |
| U-07 | Hamstring | target hostile + fleeing or PvP-flagged player + Hamstring missing. **No-go in combat** (target auras unreadable) unless tracked from own casts; revisit |
| U-04 | Thunder Clap | in combat + ≥ 2 enemies engaged (or in a group) + target lacks Thunder Clap. **No-go in combat** (target auras unreadable) unless tracked from own casts; revisit |
| U-02 | **Battle Shout party coverage** | in a party + N members in range missing Battle Shout → badge "BS 3/5". **Out of combat (pre-pull) only, provisional** |
| X-02 | Healing potion / healthstone | in combat + health < 35% + potion or healthstone available and off cooldown. **No-go** (health is secret) |

### 7.4 Avoidance detector (`Combat/Avoidance.lua`)

Single consumer of `UNIT_COMBAT` (D-035). `player` unit events with action DODGE, PARRY, BLOCK (and MISS) are incoming avoidance; `target` unit events are your attacks avoided. Taunt and ability resists (Taunt, Mocking Blow, Disarm, Intimidating Shout, Pummel, Shield Bash) come from pairing an own `UNIT_SPELLCAST_SUCCEEDED` with a following `UNIT_COMBAT` on the target within a short window **[VERIFY V-16]** (resists not yet observed). No source name is available. Publishes `WW_AVOIDANCE` and `WW_PLAYER_SPELL_MISSED`. Feeds X-06 (local text) and the announcer. One detector, two consumers.

### 7.5 HUD (`UI/HUD/*`)

- Frames are created at `PLAYER_LOGIN`, are non-secure, and are never created or re-parented in combat.
- **Alert strip**: up to 6 icons, priority by rule order; optional secondary row for the cooldown tracker.
- **Big alert**: one centre-screen slot for `dropped`/`expiring` severities; flash and sound per `alertStyle`.
- **Combat text**: large floating PARRY/DODGE/BLOCK.
- **Badges**: small text/icons (auto-attack, Charge range, BS coverage, "⏸ suspended").
- `/ww unlock` / `/ww lock` move frames out of combat; `/ww hud on|off`; `/ww test` cycles every display with dummy data for positioning.

### 7.6 Main window (M6)

One movable window (`/ww`), hidden on entering combat. Tabs in v2: **Alerts** (rules on/off, thresholds, alert style, unknown-ability list), **Announce** (M7), **Sets** (M8). Workshop tabs (Planner, Upgrades, Ready) are added in Phase E.

### 7.7 Phase B acceptance

- **Unit tests:** every condition (true/false/unknown); engine respects unknown→hidden, states, throttle and contexts; Battle Shout state transitions over a replayed stream; avoidance detector over fixture streams; secret-mode mock (every accessor returns `nil`) runs the whole stack with no errors and no displays.
- **In game (Hugh):** 10 open-world fights. Battle Shout expiring and dropped states fire and look right; Execute, Overpower and Interrupt appear when expected and never otherwise; auto-attack and Charge badges behave; parry/dodge/block text appears; on a dungeon boss the HUD shows "suspended" with no Lua errors.

---

## 8. Phase C — Announcer (M7)

### 8.1 Announce events (`Announce/Events.lua`)

| ID | Event | Trigger | Default text |
|---|---|---|---|
| A-01 | Parry / dodge / block | `WW_AVOIDANCE` | `Parried!` (per type; no attacker name, D-035) |
| A-02 | **Taunt resisted** | `WW_PLAYER_SPELL_MISSED` for Taunt (depends on the cast/`UNIT_COMBAT` pairing, **[VERIFY V-16]**) | `Taunt RESISTED on %target!` |
| A-03 | Challenging Shout / Mocking Blow | own `UNIT_SPELLCAST_SUCCEEDED` (+ miss for Mocking Blow, pairing [VERIFY]) | `Challenging Shout up – %dur s, heal through!` / `Mocking Blow %result on %target` |
| A-04 | Shield Wall / Last Stand | own `UNIT_SPELLCAST_SUCCEEDED`; follow-up 3s before expiry computed from cast time + known duration | `Shield Wall up (%dur s)` → `Shield Wall ending in 3s` |
| A-07 | Disarm / Intimidating Shout | own `UNIT_SPELLCAST_SUCCEEDED` (misses via pairing, [VERIFY]) | `Disarmed %target` / `Disarm %result on %target` |
| A-05 *(should)* | Interrupt | own Pummel/Shield Bash `UNIT_SPELLCAST_SUCCEEDED` followed by the target's `UNIT_SPELLCAST_INTERRUPTED` [VERIFY V-17, beta run 3]; miss via `UNIT_COMBAT` on target | `Pummel interrupted %spell` / `Pummel missed` |
| A-08 *(should)* | Low health call | player health < threshold (default 20%) in a group. **No-go** (health is secret) | `%player at %hp%!` |
| A-06 *(should)* | Sunder counter | target's Sunder stacks reach max | `%n Sunders up on %target` |

Variables (fixed set): `%player %target %src %spell %dur %hp %n %result`. Text is editable per event; a full template system (A-11) is backlog.

### 8.2 Channel routing

- Each event has a channel per group context: **solo**, **party**, **raid**, **instance**. Options: `off`, `self` (prefixed local print + big combat text), `PARTY`, `RAID`, `INSTANCE_CHAT`, `SAY`, `YELL`.
- **SAY/YELL** outside instances require a key press; announcements are triggered by combat events, not key presses, so outdoors they **fall back to `self`** and the UI explains why. Inside instances SAY/YELL are allowed (outside restricted contexts) [VERIFY V-25].
- Defaults: solo `self`; party `PARTY` (A-01 `self`, D-037); raid `RAID` for A-02/A-03/A-04, `off` for A-01; instance `INSTANCE_CHAT` (A-01 `self`).
- **instance** means "in an instance-category (LFG) group", not "zone is an instance"; a hand-made party inside a dungeon uses the **party** channel (D-038).
- Saved data holds sparse overrides only; defaults live in `Announce/Events.lua` and `RulePacks/` (D-039).
- **Throttle**: per-event minimum interval (default 2s; parry/dodge/block 5s) and a global cap of 1 message per second. Never send identical text twice within 3s.
- **Restricted context**: suspend chat sends [VERIFY V-26]; optionally queue a short summary after `ENCOUNTER_END` (backlog).
- Chat failures return `false, reason` from the Adapter and are logged once; they never error.

### 8.3 Phase C acceptance

- **Unit tests:** event detection from replayed streams (taunt resist, interrupt, cast success, avoidance); routing table per context; throttle and duplicate suppression; SAY fallback outdoors.
- **In game:** in a party, a resisted Taunt, Challenging Shout and Shield Wall each produce one correctly worded party message; parry/dodge announcements are throttled; solo output stays local; no Lua errors on a boss.

---

## 9. Phase D — Gear control (M8)

### 9.1 Gear sets and keybinds (G-01, G-10)

- Uses Blizzard's Equipment Manager sets (`C_EquipmentSet`) as the source of truth; Warrior Workshop adds keybinds, a queue and a picker. No duplicate set storage.
- Up to 8 bindable slots (e.g. Ctrl-1 DPS, Ctrl-2 Tank, Ctrl-3 Levelling, Ctrl-4 Fire Resist). Resistance sets (G-10) are simply additional named sets.
- `Bindings.xml` declares `WARRIORWORKSHOP_SET1`…`SET8`; they appear under an "Warrior Workshop" header in Key Bindings. Each calls `ns.Gear.Sets:Apply(slot)`.
- `/ww set <name>` applies by name; the Sets tab lists sets, assigns slots and shows the bound key.

### 9.2 Combat swap queue (G-02)

- If a set is requested in combat, store it in `gear.queued`, show a "⇄ Tank queued" badge, and apply on `PLAYER_REGEN_ENABLED`. A new request replaces the queued one; `/ww set cancel` clears it. The queue is cleared at login, not re-applied (D-041).

### 9.3 In-combat weapon swap (G-03)

- Up to 4 secure weapon-swap buttons, each with macrotext built from the chosen items (`/equipslot 16 <item>` / `/equipslot 17 <item>` / `/equip <2H>`), created out of combat by `Core/Secure.lua`; their bindings are declared in `Bindings.xml` as `CLICK <button>:LeftButton` and keys are set in Key Bindings (D-040).
- Editing a swap is out of combat only; the Sets tab disables controls in combat.
- [VERIFY V-28]: if secure weapon swaps don't work in Forever, fall back to the macro generator producing equivalent macros for the action bar.

### 9.4 Macro generator (X-07)

Generates or updates character macros out of combat from templates, using resolved spell names (SpellMap) and the user's weapon-swap items: Stance templates are gated on SpellMap like rules: a template whose stances are unknown is disabled (D-042).

| Template | Body (illustrative; finalised against V-22) |
|---|---|
| Charge + attack | `#showtooltip Charge` / `/cast Charge` / `/startattack` |
| Mouseover interrupt | `/cast [@mouseover,harm,nodead][] Pummel` (Shield Bash variant when a shield is equipped) |
| Stance-dance Overpower | `/cast [nostance:1] Battle Stance; Overpower` |
| Stance-dance Intercept | `/cast [nostance:3] Berserker Stance; Intercept` |
| Taunt with announce-free target | `/cast [@mouseover,harm,nodead][] Taunt` |
| Weapon swap macros | one per configured weapon swap (fallback for 9.3) |
| Shield Wall | `/cast [nostance:2] Defensive Stance; Shield Wall` |

- Macros are named `WW <name>`; the generator only touches macros with the `WW ` prefix. It reports slot usage and never overwrites user macros.
- Preview the text before writing; write on confirm.

### 9.5 Phase D acceptance

- **Unit tests:** macro body generation from fixture spell maps and items; queue state machine; binding table building.
- **In game:** each set key swaps the right set out of combat; requesting a set in combat queues it and applies on combat end; a weapon-swap key swaps weapons mid-fight (if V-28 is Go); generated macros appear, work, and re-running the generator updates rather than duplicates them.

---

## 10. Phase E — Workshop (professions and itemisation)

Unchanged in intent from v0.1 §7.1–7.7, summarised here. Detailed acceptance criteria carry over.

### 10.1 Inventory (M4 — built early because others depend on it)

Bags on `PLAYER_LOGIN` and `BAG_UPDATE_DELAYED` (debounced 0.5s); bank snapshot on `BANKFRAME_OPENED`/`PLAYERBANKSLOTS_CHANGED`; `Inventory:Count(itemID)` returns bags + cached bank with a staleness flag (> 24h). Fires `WW_INVENTORY_CHANGED`. Used by X-02 potions, the macro generator (weapon picker) and the Workshop.

### 10.2 Professions (M10)

Snapshot the open profession (rank, max, recipes with difficulty, output, reagents) per `skillLineID`; retain unseen recipes as `stale`; record colour observations; craft log with skill-up calibration (ring buffer 2,000). [VERIFY V-02, V-03]

### 10.3 Prices and planner (M11–M12)

- Unit value: manual > vendor sell price > unpriced (flagged). `/ww price <link> <amount>|clear`.
- Expected skill points: calibrated rate when ≥ 30 attempts, else placeholders (optimal 1.00, medium 0.75, easy 0.25, trivial 0).
- `netCost = max(Σ reagent cost − avg output × vendor price, 0)`; `score = netCost / p`; exclude p = 0; sort ascending; tie-break craftable-now desc, then name.
- Outputs: top 10 ranked list, next batch, shopping/mining list for top 3 × batch size, manual targets list. One batch ahead by design.

### 10.4 Gear advisor and tank stat sheet (M13)

- DPS and Tank weight profiles (placeholders, labelled "tune me"; table carried over from v0.1); score = Σ weight × stat; slot rules (weaker ring/trinket, 1H vs MH/OH, 2H vs pair, shield off-hand under Tank only, empty slot = 0).
- Candidates: bags and bank, crafted outputs, pinned wishlist items. **Double wins**: crafted upgrades that also give skill-ups.
- **Tank stat sheet (T-05):** dodge, parry, block chances, defense, armour, health; total avoidance; **crushing-blow coverage** (miss + dodge + parry + block vs the configured cap, default 102.4% for a level+3 boss in Classic rules — labelled placeholder until Forever mechanics are confirmed); effective health (health ÷ (1 − armour DR)). All formulas in one config table with sources shown. [VERIFY V-33]
- Upgrades tab: per-slot deltas with top-3 stat explanation; profile switcher; weights editor; tank sheet panel.

### 10.5 Readiness (M14)

Out of combat traffic lights: lowest durability (≥ 60% / 30–59% / < 30%), tracked consumables vs minimum, expected gear set worn (uses Phase D sets), bank snapshot freshness. `/ww ready` chat summary.

---

## 11. Event map (summary)

| Game event | Subscriber |
|---|---|
| `ADDON_LOADED` (self) | DB init, migrations, `OnInitialize` |
| `PLAYER_LOGIN` | `OnEnable`; SpellMap resolve; HUD frame creation; secure buttons rebuilt (out of combat) |
| `SPELLS_CHANGED`, `LEARNED_SPELL_IN_TAB` | SpellMap |
| `PLAYER_REGEN_DISABLED/ENABLED` | Context; main window hide; gear queue apply |
| `ENCOUNTER_START/END`, `CHALLENGE_MODE_START/COMPLETED` | Context (restricted) |
| `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, `GROUP_ROSTER_UPDATE` | Context |
| `UNIT_POWER_UPDATE`, `UNIT_AURA`, `UNIT_HEALTH`, `SPELL_UPDATE_USABLE`, `SPELL_UPDATE_COOLDOWN`, `PLAYER_TARGET_CHANGED`, `UNIT_SPELLCAST_*` (target), `PLAYER_ENTER_COMBAT/LEAVE_COMBAT`, `UPDATE_SHAPESHIFT_FORM` | Combat snapshot → Rules |
| `UNIT_COMBAT` (player, target) | Adapter → Avoidance, Announcer |
| `ADDON_RESTRICTION_STATE_CHANGED` | Context |
| `PLAYER_EQUIPMENT_CHANGED`, `EQUIPMENT_SETS_CHANGED` | Gear sets, Advisor, conditions (`hasShield`) |
| `BAG_UPDATE_DELAYED`, `BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED` | Inventory |
| `TRADE_SKILL_SHOW/LIST_UPDATE`, craft events, `SKILL_LINES_CHANGED` | Professions |
| `UPDATE_INVENTORY_DURABILITY` | Readiness |
| `GET_ITEM_INFO_RECEIVED` | Adapter async |
| `PLAYER_LOGOUT` | DB (stamps `meta.lastSeen`) |

---

## 12. Probe

### 12.1 M1 probe (done)

As v0.1 §9: static API existence checks, profession and item dumps, event recorder with type and secret flags, comms ping, encounter test script.

### 12.2 M3 probe extension (urgent — run before 21 October 2026)

Added to `WarriorWorkshopProbe` as a separate change; may be built in parallel with M2.

| Command | Purpose | Answers |
|---|---|---|
| `/wwprobe combat` | Toggle a 0.25s combat sampler recording **type and secret status only** of target health, rage, cooldowns, usability, auras (player, target, party1–4), casting info, range, `IsCurrentSpell`, stance; plus encounter state | V-11–V-15, V-17, V-18, V-23, V-32 |
| (recorder) | Adds CLEU, found unavailable (D-035) (first 300 events/session, field types, secret flags, miss types), `PLAYER_DEAD`, `UNIT_THREAT_LIST_UPDATE`, `NAME_PLATE_UNIT_ADDED`, `TRAINER_SHOW`, `UPDATE_SHAPESHIFT_FORM`, `EQUIPMENT_SETS_CHANGED` | V-16, V-19, V-24 |
| `/wwprobe spells` | Dump spellbook names and IDs | V-22 |
| `/wwprobe trainer` | Dump trainer services (window open) | V-24 |
| `/wwprobe chat` | From an event handler (via a 1s timer, not a key press), attempt PARTY, RAID, INSTANCE_CHAT, SAY, YELL with `[WWPROBE]`; record success/error per channel and context. Also bind `/wwprobe chatkey` to a key and repeat SAY from a key press | V-25, V-26 |
| `/wwprobe sets` | List equipment sets; apply set N out of combat; attempt in combat (record result) | V-27 |
| `/wwprobe swapbtn <item1> <item2>` | Create a secure button with `/equip` macrotext, bind to a key via `SetBindingClick`; Hugh presses it in combat | V-28 |
| `/wwprobe macro` | Create, edit and delete a test macro `WW Probe`; record macro counts and limits | V-29 |
| (Bindings.xml) | Declare a test binding; Hugh checks it appears in Key Bindings and persists after relog | V-30 |
| `/wwprobe tank` | Dump dodge, parry, block, defense, armour APIs | V-33 |
| — | Manual: Hugh notes what the Cooldown Manager shows for warrior abilities, whether a swing timer exists and its options, floating combat text options for parry/dodge/block, and the loss-of-control frame | V-31 |

**Test script (add to `docs/PROBE_RESULTS.md`)**

1. Open world: `/wwprobe combat` on; fight 5 mobs incl. one caster; Charge, interrupt, let dodges/parries/blocks happen; use Battle Shout and let it expire.
2. In a party with a second player: Taunt a mob until a resist (or log several taunts); use Challenging Shout and Shield Wall; `/wwprobe chat` in open world, then on dungeon trash, then on a boss.
3. Equipment sets: create two sets; `/wwprobe sets` out of and in combat; `/wwprobe swapbtn` and press the key mid-fight.
4. `/wwprobe macro`, `/wwprobe spells`, `/wwprobe tank`; trainer visit with `/wwprobe trainer`.
5. Check Key Bindings for the test binding; relog; check again.
6. Note the built-ins (V-31).

**Decision gate.** Record in `docs/DECISIONS.md` each Phase B–D feature as **Go**, **Degraded** (stated fallback) or **No-go** before building it.

---

## 13. Testing and quality

- **Lua 5.1** semantics; no `goto`, `//`, `utf8`, 5.3 operators.
- **luacheck** clean; WoW globals allowed only in Adapter, Secure, UI and probe.
- **busted** for all pure logic: conditions, rule engine, avoidance detector, announce routing and throttles, macro generation, gear queue, planner, advisor, tank sheet, readiness, migrations.
- **Replay harness** (`tests/helpers/replay.lua` + `mock_clock.lua`): feed normalised event streams from `tests/fixtures/streams/*.lua` into modules; assert on outputs. Convert M3 probe logs into fixtures.
- **Secret mode**: mock Adapter returning `nil` for every combat accessor; the whole HUD and announcer must run without error and show nothing.
- **Simulator** (`tools/sim/`, D-011): loads the add-on against a fake client offline; its tests run in CI.
- **CI**: luacheck + busted + simulator tests on every push/PR. **Release**: zip `WarriorWorkshop/` on tag `v*`.
- **Performance**: ≤ 0.5ms average per combat event handler; one shared ticker; no allocation in hot paths; Workshop scans ≤ 5ms typical.
- **In-game verification**: each milestone ends with `docs/verification/M<n>.md`; complete only when Hugh confirms.

---

## 14. Coding conventions

- File header `local addonName, ns = ...`. `PascalCase` module methods, `camelCase` locals/fields, `UPPER_SNAKE` constants.
- Doc comment on every public function: inputs, outputs, side effects.
- Money in integer copper; formatting only in UI. Player-facing strings in `Locale/enUS.lua`.
- Never compare, do arithmetic on, concatenate or index with a value that may be secret.
- Conventional commits; small, reviewable steps.

---

## 15. Build plan

Each milestone: implement → unit tests → luacheck → `docs/verification/M<n>.md` → update `docs/HANDOFF.md` → **stop** for Hugh's check where marked.

| # | Milestone | Deliverables | Acceptance | Human check |
|---|---|---|---|---|
| M0 | Scaffold | Done | — | Done |
| M1 | Probe | Done | — | Run in beta |
| **M2** | Core | Init, Events, DB (schema v2 defaults or v1→v2 migration), Migrations, Log, Util, Adapter skeleton; **Context and SpellMap stubs** | Unit tests for DB/migrations/Context; no globals leak | Yes |
| **M3** | Probe extension | §12.2 commands, recorder additions, test script in `PROBE_RESULTS.md` | Probe loads; each command writes results | **Yes — before 21 Oct** |
| **M4** | Inventory | §10.1 | Counts correct; bank cache persists | Yes |
| **M5** | Combat core + must-haves | Snapshot, Conditions, Rules, Avoidance, combat Adapter accessors, SpellMap, Context complete, HUD frames, rule pack with §7.2 rules, `/ww unlock|lock|hud|test`, replay harness, secret-mode tests | §7.7 | Yes |
| **M6** | Main window + should-haves | MainFrame, Alerts tab (rules, thresholds, alert style, unknown abilities), §7.3 rules | Config persists; should-have rules pass §7.7-style checks | Yes |
| **M7** | Announcer | §8: events A-01–A-04, A-07 first; then A-05, A-06, A-08; Announce tab; throttles; SAY fallback | §8.3 | Yes |
| **M8** | Gear control | §9: Bindings.xml, Secure.lua, set keybinds, queue, weapon swaps, macro generator, Sets tab | §9.5 | Yes |
| **M9** | Launch kit release | Hardening, performance pass, README usage, re-run probe on launch build, tag `v0.5.0` | No Lua errors across a play session incl. a dungeon | Yes |
| M10 | Professions | §10.2 | v0.1 §7.2/7.3 acceptance | Yes |
| M11 | Prices + planner logic | §10.3 | Fixture ranking tests | No |
| M12 | Planner tab | UI | Usable end-to-end | Yes |
| M13 | Gear advisor + tank sheet | §10.4, Upgrades tab | Sensible upgrades; tank sheet matches character pane | Yes |
| M14 | Readiness | §10.5, Ready tab | Traffic lights correct | Yes |
| M15 | Hardening + `v1.0.0` | Error pass, docs | Workshop acceptance test (v0.1 §11) | Yes |

**Sequencing notes**

- M3 is the critical path: if it isn't run before the beta closes, Phases B–D proceed against assumptions and are re-verified on launch day.
- M5 must not wait for M4 unless a must-have rule needs inventory (none do; X-02 in M6 does).
- Gear set keybinds (part of M8) are small; if time allows they can be pulled forward before launch.

## 16. Milestone mapping (v0.1 → v2)

| v0.1 | v2 |
|---|---|
| M0–M2 | M0–M2 (M2 gains Context/SpellMap stubs and schema v2) |
| M3 Inventory | M4 |
| M4 Professions | M10 |
| M5 Prices + Planner | M11 |
| M6 UI shell + Planner tab | M6 (main window shell) + M12 (Planner tab) |
| M7 Gear | M13 (+ tank stat sheet) |
| M8 Readiness | M14 |
| M9 Hardening | M9 (launch kit) and M15 (v1.0.0) |
| SPEC_LEVELLING L0 | M3 |
| L1 | M5 + M6 (swing timer removed) |
| L2 | Backlog (pull check, death recap, runner/add rated 3) |
| L3 | **Removed** |
| L4 | Trainer reminder → backlog item rated 2 (Q-03); others removed or backlog |

---

## 17. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Forever restricts open-world combat more than Midnight | Medium | **Critical** for B/C | M3 before beta close; decision gate; Phases D and E unaffected |
| Chat from add-ons more restricted than expected | Medium | High for C | V-25/26; `self` fallback; party-only defaults |
| Secure weapon swaps blocked | Low–Medium | Medium | V-28; macro-generator fallback |
| Built-in tools duplicate alerts or cooldown tracker | Medium | Medium | V-31; gate R-06; drop overlapping rules |
| Forever warrior kit differs from Classic | High | Medium | SpellMap by name; auto-disable unknowns; V-22 |
| Rule engine creep | Medium | Medium | Fixed condition vocabulary; spec change required |
| No in-game testing between beta close and launch | Certain | Medium | Replay harness + probe-derived fixtures; re-probe at launch |
| Announcer spam annoys groups | Medium | Low | Throttles, party-only defaults, A-01 off in raids |
| Tank sheet formulas wrong for Forever | High | Low | Labelled placeholders; config table with sources |

---

## 18. Decisions (`docs/DECISIONS.md`)

Carry forward D-001 to D-015 (D-004 as amended). The new decisions below were recorded in the log as **D-016 to D-028** (D-030 has the mapping), because D-006 to D-015 were already taken. Add:

| ID | Decision | Rationale |
|---|---|---|
| D-006 | SPEC v2 supersedes SPEC v0.1 and SPEC_LEVELLING v0.1; milestone order per §15 | Triage of 9 Oct 2026 |
| D-007 | **D-004 amended:** in-combat HUD and announcer are in scope in open world and instances outside restricted contexts; the main window still hides in combat | Restrictions apply only to encounters/M+ |
| D-008 | No rotation/"press next" engine | Policy risk; value is in reactive and upkeep signals |
| D-009 | Alerts and announcements are declarative tables with a fixed condition vocabulary; no user Lua | Safety, testability, scope |
| D-010 | Secret or unavailable value → unknown → hidden | Secret-safe by construction |
| D-011 | Combat and announce features suspend in restricted contexts | Blizzard rules |
| D-012 | Levelling analytics (XP dashboard, session review, mob intel, fight log) removed | Triage: Pass |
| D-013 | No swing timer | Triage: Pass; built-in [VERIFY V-31] |
| D-014 | Announcer: SAY/YELL outdoors fall back to local output; party/raid/instance defaults; throttled | Hardware-event rule; etiquette |
| D-015 | Gear: Equipment Manager sets are the source of truth; armour never swapped in combat (queued); weapon swaps only via secure buttons/macros | Protected actions |
| D-016 | `Core/Secure.lua` is the only place for secure frames, bindings and macro writes | Taint containment |
| D-017 | One avoidance detector feeds both local combat text and announcements | No duplicate CLEU logic |
| D-018 | R-06 cooldown tracker gated on V-31 | Avoid duplicating Blizzard's Cooldown Manager |

---

## 19. Out of scope and later (Phase F)

**Backlog (rated 3):** pull check (X-11), death recap (X-09), weapon upgrade watch (Q-04), Bloodrage prompt (R-08), big stance indicator (X-05), runner/add alerts (X-10), Demoralising Shout uptime (U-03), announce templates (A-11), weapon enchant missing (U-10), set integrity check (G-08), threat lead (T-02), marker helper (T-07), big cooldown-ready alerts (R-07), pull announce (A-10), loss-of-control hint (X-04). **Rated 2 but unscheduled:** trainer reminder (Q-03).

**Raid coordination (rated 3, outline only):** shout assignments, Sunder coordination, tank cooldown rotation, post-fight warrior report, co-tank taunt tracker; per-boss cooldown plan timelines and own-cast logging in encounters; Python analysis pipeline in `tools/analysis` joining SavedVariables to Warcraft Logs exports. Depends on V-06–V-09.

**Still out of scope from v0.1 §3.1:** alts, auction house scanning, minimap button, CurseForge publishing.

**Not doing:** rotation engine, swing timer, levelling analytics, quest guidance, PvP tooling, profession gear sets, event-driven auto-swaps, trinket cycling, and the other items marked Pass in `IDEAS_BACKLOG.md`.
