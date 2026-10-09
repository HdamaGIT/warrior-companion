> **Superseded by `docs/SPEC_V2.md` (9 Oct 2026); kept for reference.**

# Warrior Workshop — Specification and Build Plan

| | |
|---|---|
| **Document** | `docs/SPEC.md` |
| **Version** | 0.1 (draft for build) |
| **Date** | 8 October 2026 |
| **Owner** | Hugh |
| **Target client** | World of Warcraft: Forever (beta to 21 Oct 2026; launch early Nov 2026) |
| **Status** | Approved for Phase 0 and v1 build |

---

## 0. How to use this document

This is the single source of truth for the Warrior Workshop add-on. It is written to be read by Claude Code at the start of every build session.

- **Section 3** sets the roadmap. Only **Phase 0 and v1** are in build scope. v2 and v3 are outlined so that v1 does not paint us into a corner, but no v2/v3 code should be written yet.
- **Section 11** is the build plan: milestones, in order, each with acceptance criteria and a human verification checkpoint.
- Anything marked **[VERIFY]** depends on Forever API behaviour that has not been confirmed. Phase 0 exists to confirm these. Do not build hard dependencies on a [VERIFY] item until its result is recorded in `docs/DECISIONS.md`.
- Where this spec and the code disagree, the spec wins unless a later entry in `docs/DECISIONS.md` says otherwise.

---

## 1. Vision and principles

**Vision.** A warrior-centric class support add-on for WoW: Forever that uses the game's add-on capabilities to their fullest within Blizzard's rules: itemisation, professions, readiness, and (later) cooldown planning and warrior raid coordination.

**v1 question to answer.** *"What is the cheapest next step that makes me stronger and levels my professions?"*

**Design principles**

1. **Plan before, display during, review after.** Forever inherits Midnight's add-on restrictions: add-ons can display combat information but not act on it. We build value in planning and review, not live combat logic.
2. **Out of combat by default.** Every v1 feature runs out of combat. The UI hides on entering combat.
3. **Thin API adapter.** All Blizzard API calls go through `Core/Adapter.lua`. Beta-to-launch API drift should be a one-file fix, and the adapter is the seam for unit-test mocks.
4. **Observe, don't hardcode.** Forever has revamped classes, recipes and zones. Read live game data and record observations; never ship Classic-era recipe or stat tables as truth.
5. **User-editable judgement.** Stat weights, material prices and skill-up odds are configuration with sensible placeholders, not hidden constants.
6. **Explainable outputs.** Every recommendation shows why (e.g. "+14 score: +8 Str, +6 Sta"; "1.2s per skill point at 3 Copper Bar each").
7. **Zero external library dependencies in v1.** Fewer moving parts during an unstable beta. Revisit in v2 (see Decision D-003).

---

## 2. Platform constraints

### 2.1 Facts (publicly reported)

- Forever shares Mainline WoW's UI architecture, including most APIs available in patch 12.1.5 (Midnight).
- Midnight introduced **secret values**: combat state can be displayed by add-ons but not read or branched on.
- Restrictions apply **during boss encounters and Mythic+**; open-world combat is unaffected (per Blizzard's 2026 relaxation).
- `COMBAT_LOG_EVENT_UNFILTERED` is unavailable to add-ons in restricted contexts.
- Add-on communication (`SendAddonMessage`) is blocked in restricted contexts.
- The player's own spell casts remain detectable; the player's own cooldowns are secret.
- Blizzard ships a built-in Cooldown Manager and damage meter in Forever.
- Classic-era add-ons do not run; add-ons must target the Mainline API.

### 2.2 Inferences

- Profession and item APIs follow the Mainline `C_TradeSkillUI`, `C_Container`, `C_Item` namespaces rather than Classic globals such as `GetTradeSkillInfo`.
- Recipe difficulty colour is exposed via a relative-difficulty field on recipe info rather than numeric thresholds.
- Bank contents are readable only while the bank frame is open.

### 2.3 To verify in Phase 0 [VERIFY]

| ID | Question | Why it matters |
|---|---|---|
| V-01 | Interface number for the `.toc` (`select(4, GetBuildInfo())`) and client folder name (`_forever_beta_` vs `_classic_beta_`) | Add-on loads at all |
| V-02 | Which `C_TradeSkillUI` functions exist; what recipe info fields are returned (esp. difficulty, output item, reagents) | Planner feasibility |
| V-03 | Is there a reliable craft-completion event, and does a skill-up surface as an event or only a chat message? | Craft log and calibration |
| V-04 | `C_Item.GetItemStats` return keys for Forever stats | Gear scoring |
| V-05 | Does `C_EquipmentSet` exist and work? | Readiness gear check |
| V-06 | Do `ENCOUNTER_START` / `ENCOUNTER_END` fire for add-ons in a raid/dungeon boss? | v2 timelines |
| V-07 | Does `UNIT_SPELLCAST_SUCCEEDED` for `player` fire and return a readable spellID during an encounter? | v2 cast logging |
| V-08 | Does an add-on message sent to PARTY/RAID arrive during an encounter? | v3 raid sync |
| V-09 | Does a `CHAT_MSG_PARTY`/`RAID` message with a tag (e.g. `[WW:871]`) arrive and is it readable during an encounter? | v3 fallback sync |
| V-10 | Does `issecretvalue` (or equivalent) exist, and which of the above values are secret in which contexts? | Everything combat-related |

---

## 3. Roadmap

| Phase | Name | Scope | Status |
|---|---|---|---|
| **0** | Probe | Separate throwaway add-on that answers V-01 to V-10 | **Build now** |
| **v1** | Workshop & Itemisation | Inventory, profession cache, skill-up planner, crafted-gear advisor, readiness panel, prices | **Build now** |
| v2 | Personal cooldowns & analysis loop | Per-boss cooldown plan timelines; own-cast logging; export to SavedVariables; Python analysis pipeline in `tools/analysis` that derives timings and generates plan templates | Outline only |
| v3 | Warrior raid coordination | Pre-pull plan assignment and sync among raid warriors; in-fight shared timeline; chat-tag macro fallback for live cast sharing; post-fight adherence report | Outline only |

### 3.1 v1 out of scope (explicitly)

Alts and account-wide banks; auction house scanning; mining routes and node maps; any in-combat feature; engineering-specific tooling until trained; localisation beyond enUS/enGB; minimap button; CurseForge publishing.

---

## 4. Repository structure

```
warrior-workshop/
├── README.md
├── CLAUDE.md                     # Claude Code working rules (derived from this spec)
├── LICENSE                       # MIT
├── .gitignore
├── .editorconfig
├── .luacheckrc
├── .busted
├── .github/
│   └── workflows/
│       ├── ci.yml                # luacheck + busted on push/PR
│       └── release.yml           # zip WarriorWorkshop/ on tag v*
├── docs/
│   ├── SPEC.md                   # this document
│   ├── DECISIONS.md              # decision log (ADR-lite)
│   ├── HANDOFF.md                # session handoff notes
│   ├── PROBE_RESULTS.md          # Phase 0 findings (filled in by Hugh + Claude)
│   ├── DEV_SETUP.md              # Windows junction, reload loop, error display
│   └── verification/
│       └── M<n>.md               # in-game verification checklist per milestone
├── WarriorWorkshop/              # the add-on (junctioned into Interface/AddOns)
│   ├── WarriorWorkshop.toc
│   ├── Core/
│   │   ├── Init.lua              # namespace, module registry, bootstrap
│   │   ├── Events.lua            # event bus (single frame, dispatch to modules)
│   │   ├── Adapter.lua           # ALL Blizzard API calls live here
│   │   ├── DB.lua                # SavedVariables init, defaults, accessors
│   │   ├── Migrations.lua        # ordered schema migrations
│   │   ├── Log.lua               # debug logging (toggle via /ww debug)
│   │   └── Util.lua              # pure helpers (tables, money format, etc.)
│   ├── Modules/
│   │   ├── Inventory.lua
│   │   ├── Professions.lua       # recipe cache + craft log + colour observations
│   │   ├── Prices.lua
│   │   ├── Planner.lua
│   │   ├── Gear.lua              # itemisation & scoring
│   │   └── Readiness.lua
│   ├── UI/
│   │   ├── MainFrame.lua         # window shell, tabs, combat auto-hide
│   │   ├── PlannerTab.lua
│   │   ├── GearTab.lua
│   │   ├── ReadyTab.lua
│   │   └── Widgets.lua           # shared row/list/tooltip helpers
│   └── Locale/
│       └── enUS.lua
├── WarriorWorkshopProbe/         # Phase 0 throwaway add-on
│   ├── WarriorWorkshopProbe.toc
│   └── Probe.lua
├── tests/
│   ├── helpers/
│   │   └── mock_adapter.lua      # fake Adapter returning fixture tables
│   ├── fixtures/                 # recipe, item, inventory fixtures
│   ├── planner_spec.lua
│   ├── gear_spec.lua
│   ├── readiness_spec.lua
│   ├── migrations_spec.lua
│   └── util_spec.lua
└── tools/
    └── analysis/                 # v2: Python pipeline (placeholder README only in v1)
        └── README.md
```

**Rationale.** The add-on lives in a subfolder so the repo can also hold the probe, tests, docs and the v2 Python tooling. Developer loop: a Windows directory junction from `WarriorWorkshop/` into the client's `Interface\AddOns\` (see `docs/DEV_SETUP.md`).

---

## 5. Architecture

### 5.1 Layers

```
UI (frames, tabs)            reads view-models only; never calls Adapter
   ▲
Modules (domain logic)       pure Lua where possible; testable with mock Adapter
   ▲
Core (Events, DB, Adapter)   the only layer that touches WoW globals
```

Rules:

- **Only `Core/Adapter.lua` and `UI/*` may reference WoW globals.** UI may use frame APIs (`CreateFrame`, templates); it must get data from modules.
- Modules expose functions returning **plain Lua tables** (view-models). Planner and Gear scoring must be pure functions of their inputs so they can be unit-tested outside the game.
- Every file starts `local addonName, ns = ...` and attaches to `ns`. No new globals except the SavedVariables tables and the slash command.

### 5.2 Module contract

```lua
-- Each module registers itself:
local M = ns:NewModule("Planner")
function M:OnInitialize() end   -- after SavedVariables load (ADDON_LOADED)
function M:OnEnable() end       -- at PLAYER_LOGIN; register events here
-- Events are subscribed via the bus:
ns.Events:On("BAG_UPDATE_DELAYED", M, "OnBagsChanged")
-- Modules publish internal messages for decoupling:
ns.Events:Fire("WW_INVENTORY_CHANGED")
```

Internal messages are prefixed `WW_`. The UI subscribes to `WW_*` messages to refresh, never to raw game events.

### 5.3 Adapter surface (v1)

Each function returns plain tables and degrades gracefully (returns `nil` plus logs once) if the underlying API is missing. Signatures are the contract; implementations are [VERIFY] against Phase 0.

| Function | Returns |
|---|---|
| `Adapter.GetBuildInfo()` | `{ version, build, interface }` |
| `Adapter.InCombat()` | boolean (`InCombatLockdown()` / `UnitAffectingCombat("player")`) |
| `Adapter.GetBagContents()` | `{ [itemID] = count }` for backpack + bags |
| `Adapter.GetBankContents()` | `{ [itemID] = count }` or `nil` if bank closed |
| `Adapter.GetEquipped()` | `{ [slotID] = { itemID, link } }` |
| `Adapter.GetDurability()` | `{ [slotID] = { cur, max } }` |
| `Adapter.GetItemStats(link)` | `{ [statKey] = value }` normalised to internal keys (5.4) |
| `Adapter.GetItemBasics(itemID, cb)` | async: `{ name, link, quality, ilvl, reqLevel, equipLoc, classID, subClassID, sellPrice, icon }` |
| `Adapter.IsUsableByPlayer(itemID)` | boolean |
| `Adapter.GetOpenProfession()` | `{ skillLineID, name, rank, maxRank }` or `nil` |
| `Adapter.GetKnownRecipes()` | array of `{ recipeID, name, difficulty, outputItemID, outputMin, outputMax, reagents = { {itemID, qty} } }` |
| `Adapter.GetEquipmentSets()` | `{ [name] = { [slotID] = itemID } }` or `nil` |
| `Adapter.Print(msg)` | chat output with addon prefix |

### 5.4 Normalised stat keys

Internal keys are short, stable strings: `str, agi, sta, int, spi, armor, ap, crit, hit, haste, expertise, defense, dodge, parry, block, blockValue, weaponDps, weaponSpeed`. The adapter maps Blizzard's `ITEM_MOD_*` keys to these. Unknown keys are kept under `other[<rawKey>]` and logged once, so new Forever stats are visible rather than silently dropped.

---

## 6. Data model

Two SavedVariables tables, both versioned from day one.

```lua
-- Account-wide
WarriorWorkshopDB = {
  schemaVersion = 1,
  settings = {
    debug = false,
    batchSize = 5,                 -- default crafts per planner batch
    hideInCombat = true,
    window = { point, x, y, w, h, tab = "planner" },
  },
  prices = {                       -- copper per unit
    [itemID] = { value = 1500, source = "manual", updatedAt = 1728400000 },
  },
  calibration = {                  -- skill-up odds learned across characters
    byDifficulty = {
      optimal = { attempts = 0, gains = 0 },
      medium  = { attempts = 0, gains = 0 },
      easy    = { attempts = 0, gains = 0 },
      trivial = { attempts = 0, gains = 0 },
    },
  },
}

-- Per character
WarriorWorkshopCharDB = {
  schemaVersion = 1,
  meta = { name, realm, classFile, level, lastSeen },
  inventory = {
    bags = { [itemID] = count }, bagsScannedAt = ts,
    bank = { [itemID] = count }, bankScannedAt = ts,   -- cached snapshot
  },
  professions = {
    [skillLineID] = {
      name, rank, maxRank, scannedAt,
      recipes = { [recipeID] = { name, difficulty, outputItemID,
                                 outputMin, outputMax,
                                 reagents = { { itemID, qty } } } },
    },
  },
  targets = { [recipeKey] = { name, note } },          -- manual "learn next" list
  craftLog = {                                         -- ring buffer, cap 2000
    { t, recipeID, difficulty, rankBefore, rankAfter, gained },
  },
  colourObservations = {                               -- learn thresholds over time
    [recipeID] = { { rank = 75, difficulty = "medium" } },
  },
  gear = {
    activeProfile = "dps",
    profiles = {
      dps  = { label = "DPS",  weights = { ... } },
      tank = { label = "Tank", weights = { ... } },
    },
  },
  readiness = {
    consumables = { [itemID] = { min = 5, label = "Dense Sharpening Stone" } },
    durabilityAmber = 0.60, durabilityRed = 0.30,
    expectedSet = { dps = "DPS", tank = "Tank" },       -- equipment set names
  },
}
```

**Migrations.** `Core/Migrations.lua` holds an ordered array of `{ to = n, fn = function(db) ... end }`. On load, apply every migration where `to > db.schemaVersion`, then set `schemaVersion`. Each migration has a unit test. Corrupt or unknown future versions: back up to `WarriorWorkshopDB_backup` and reinitialise, printing a warning.

---

## 7. v1 functional specification

### 7.1 Inventory

- Scan bags on `PLAYER_LOGIN` and on `BAG_UPDATE_DELAYED` (debounced 0.5s).
- Scan bank on `BANKFRAME_OPENED` and `PLAYERBANKSLOTS_CHANGED` (and bank bag equivalents [VERIFY]); store snapshot and timestamp.
- `Inventory:Count(itemID)` returns `bags + cachedBank` and a staleness flag if the bank snapshot is older than 24h.
- Fires `WW_INVENTORY_CHANGED`.

**Acceptance:** counts match the game for bags; bank counts persist across `/reload` and logout; staleness shown in UI.

### 7.2 Professions (recipe cache)

- On profession window open/update, snapshot the open profession: rank, max rank, all known recipes with difficulty, output and reagents.
- Persist per `skillLineID`. Recipes not seen in a later scan are retained but marked `stale = true` (never silently deleted).
- On each scan, append a `colourObservations` entry when a recipe's difficulty differs from its last observation. Over time this reveals the rank at which each recipe changes colour, enabling forward simulation in v1.x.
- Fires `WW_PROFESSIONS_CHANGED`.

**Acceptance:** opening Blacksmithing populates the cache; cache survives `/reload`; Planner works with the window closed using cached data.

### 7.3 Craft log and skill-up calibration

- Detect craft completion [VERIFY V-03]. Preferred: a dedicated craft-result event; fallback: `UNIT_SPELLCAST_SUCCEEDED` for `player` matched to a known recipe spell, with rank read before and after (`SKILL_LINES_CHANGED` or `CHAT_MSG_SKILL`).
- Record `{ t, recipeID, difficulty (at cast time), rankBefore, rankAfter, gained }`.
- Update `calibration.byDifficulty[difficulty]` attempts/gains.
- Ring buffer capped at 2,000 entries.

**Acceptance:** crafting 10 items produces 10 log entries with correct difficulty and gain flags.

### 7.4 Prices

- Unit value precedence: **manual price > vendor sell price > unpriced**.
- Vendor sell price is an opportunity-cost floor for self-gathered materials; manual prices let Hugh reflect auction value.
- `/ww price <itemLink> <gold>g <silver>s` sets a manual price; `/ww price <itemLink> clear` removes it. Also editable from the Planner tab (right-click a reagent).
- Unpriced reagents are flagged in the UI and treated as zero cost with a warning icon.

### 7.5 Skill-up planner

**Inputs:** cached recipes for a profession; inventory counts; prices; skill-up odds.

**Expected skill points per craft**

```
p(difficulty) = calibrated rate if attempts >= 30
              else default: optimal 1.00, medium 0.75, easy 0.25, trivial 0.00
```

The 30-attempt threshold and defaults live in `settings` and are shown in the UI as "assumed" or "observed (n=…)".

**Cost per craft**

```
matCost(r)  = Σ reagent.qty × unitValue(reagent.itemID)
outValue(r) = avg(outputMin, outputMax) × vendorSellPrice(outputItemID)   -- credit for resale
netCost(r)  = max(matCost(r) − outValue(r), 0)
```

**Ranking**

```
score(r) = netCost(r) / p(r)          -- copper per expected skill point
exclude recipes with p(r) = 0
sort ascending by score; tie-break: craftableNow desc, then name
craftableNow(r) = min over reagents of floor(count(itemID) / qty)
```

**Outputs (view-model)**

1. **Ranked list** of top 10 recipes: name, difficulty colour, p (assumed/observed), net cost per skill point, craftable now, double-win badge (7.6).
2. **Next batch**: top recipe × `min(craftableNow, batchSize)`; if craftableNow = 0, the first recipe with craftableNow > 0 is offered as "best you can do now" alongside the cheapest overall.
3. **Shopping / mining list**: for the top 3 recipes × `batchSize`, the reagent shortfall `max(needed − have, 0)` aggregated by item, with estimated cost.
4. **Targets panel**: manual "learn next" recipes with free-text notes.

**Known limitation (by design).** v1 plans one batch ahead because the API exposes current colour, not thresholds. Recompute after every skill-up. Forward simulation to a target rank is a v1.x enhancement once `colourObservations` has data.

**Acceptance:** given fixture data, ranking matches hand-calculated expectations (unit tests); in game, the top recommendation changes after a recipe turns yellow.

### 7.6 Gear advisor (itemisation)

**Profiles.** Two default profiles, `dps` and `tank`, each a weight table over the normalised stat keys. **Default weights are placeholders for Forever's revamped class design** and must be labelled "placeholder — tune me" in the UI until Hugh edits them.

| Stat | DPS (placeholder) | Tank (placeholder) |
|---|---|---|
| str | 1.00 | 0.50 |
| agi | 0.70 | 0.60 |
| sta | 0.10 | 1.00 |
| ap | 0.50 | 0.20 |
| crit | 0.80 | 0.20 |
| hit | 1.00 | 0.40 |
| haste | 0.60 | 0.20 |
| expertise | 0.80 | 0.50 |
| armor | 0.00 | 0.05 |
| defense | 0.00 | 1.20 |
| dodge | 0.00 | 1.00 |
| parry | 0.00 | 0.90 |
| block | 0.00 | 0.60 |
| blockValue | 0.00 | 0.30 |
| weaponDps | 3.00 | 1.00 |

**Scoring**

```
score(item, profile) = Σ_s weight[s] × stat[s]       -- unknown stats contribute 0, flagged
delta(candidate)     = score(candidate) − score(currentInComparableSlot)
```

Comparable slot rules:

- Rings and trinkets: compare against the **weaker** of the two equipped.
- One-hand weapons: compare against main hand; also against off hand if dual-wield is possible.
- Two-hander vs main-hand + off-hand: compare against the sum of the pair's scores.
- Shields: off hand only; only meaningful under `tank`.
- Empty slot: current score = 0.

**Candidates**

1. Items in bags (and cached bank) that are equippable and usable.
2. **Crafted candidates**: output items of all cached Blacksmithing/Engineering recipes, including ones not yet craftable.
3. Manually pinned items (shift-click link into the Gear tab) for wishlist tracking.

Items whose data is not yet cached load asynchronously via `Adapter.GetItemBasics`; the UI shows a loading state and refreshes on completion.

**Outputs**

- Per slot: current item and score; best candidate per source; delta with **explanation** (top three stat contributions).
- **Double wins**: crafted outputs with positive delta in the active profile *and* p > 0 in the planner. Surfaced on both the Gear and Planner tabs.
- Profile switcher (DPS/Tank) and a weights editor (numeric inputs, reset to placeholder).

**Acceptance:** unit tests for scoring and slot-comparison rules; in game, equipping a better item removes it from upgrade suggestions.

### 7.7 Readiness panel

Runs only out of combat. Traffic-light rows:

| Check | Green | Amber | Red |
|---|---|---|---|
| Lowest durability | ≥ 60% | 30–59% | < 30% |
| Each tracked consumable | ≥ min | > 0 and < min | 0 |
| Expected gear set worn (if `C_EquipmentSet` available [VERIFY V-05]) | matches | — | mismatch (lists differing slots) |
| Bank snapshot freshness | < 24h | 24h–7d | > 7d or never |

Tracked consumables are configured in the Ready tab (shift-click an item link to add; set min). Sensible starter list is empty; Hugh adds sharpening stones, weightstones, potions and explosives as he obtains them.

`/ww ready` prints a one-line summary to chat (e.g. "Ready: 2 amber — durability 41%, Elixir of the Mongoose 1/3").

### 7.8 UI

- One movable, resizable window (`/ww` toggles), three tabs: **Planner**, **Gear**, **Ready**. Position and last tab persist.
- Built with Blizzard frame templates; plain styling for v1 (function before polish).
- **Auto-hide on `PLAYER_REGEN_DISABLED`**; do not reopen automatically. Never attempt protected actions.
- Tooltips on every number explaining its derivation.
- Planner tab: profession dropdown (from cache), ranked list, next batch, shopping list, targets.
- Gear tab: profile switcher, slot list with deltas, double-win section, weights editor (collapsible).
- Ready tab: traffic-light list, consumables configuration.

### 7.9 Slash commands

| Command | Action |
|---|---|
| `/ww` | Toggle window |
| `/ww planner` \| `gear` \| `ready` | Open on tab |
| `/ww ready` | Chat summary |
| `/ww price <link> <amount>` / `clear` | Manual price |
| `/ww profile dps` \| `tank` | Switch gear profile |
| `/ww debug` | Toggle debug logging |
| `/ww reset confirm` | Reset character data (requires `confirm`) |
| `/ww version` | Print add-on, schema and interface versions |

---

## 8. Event map

| Game event | Subscriber | Action |
|---|---|---|
| `ADDON_LOADED` (self) | Core/DB | Initialise SavedVariables, run migrations, `OnInitialize` modules |
| `PLAYER_LOGIN` | Core | `OnEnable` modules; initial bag scan; equipped scan |
| `PLAYER_LOGOUT` | Core/DB | Stamp `lastSeen` |
| `BAG_UPDATE_DELAYED` | Inventory | Debounced bag scan → `WW_INVENTORY_CHANGED` |
| `BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED` [VERIFY] | Inventory | Bank scan → `WW_INVENTORY_CHANGED` |
| `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE` [VERIFY] | Professions | Snapshot open profession → `WW_PROFESSIONS_CHANGED` |
| Craft-completion event [VERIFY V-03] / `UNIT_SPELLCAST_SUCCEEDED` (player) | Professions | Append craft log; update calibration |
| `SKILL_LINES_CHANGED` / `CHAT_MSG_SKILL` [VERIFY] | Professions | Update rank; resolve pending craft gain |
| `PLAYER_EQUIPMENT_CHANGED` | Gear | Rescore → `WW_GEAR_CHANGED` |
| `UPDATE_INVENTORY_DURABILITY` | Readiness | Recompute → `WW_READINESS_CHANGED` |
| `GET_ITEM_INFO_RECEIVED` / `Item:ContinueOnItemLoad` | Adapter | Resolve async item requests |
| `PLAYER_REGEN_DISABLED` | UI | Hide window |
| `PLAYER_LEVEL_UP` | Gear, Readiness | Refresh usability |

---

## 9. Phase 0 — Probe add-on

A separate add-on, `WarriorWorkshopProbe`, deliberately crude, to be run by Hugh in the beta **before 21 October 2026**.

**Behaviour**

- `/wwprobe` prints a summary and writes everything to `WarriorWorkshopProbeDB`.
- **Static checks (any time):** build info and interface number (V-01); existence of each function listed in the Adapter surface and in V-02 to V-05 (`type(x) == "function"`); existence of `issecretvalue` (V-10).
- **Profession dump (with Blacksmithing open):** `/wwprobe prof` dumps the first 10 recipes' full info tables recursively, so we can see real field names (V-02).
- **Item dump:** `/wwprobe item <link>` dumps `C_Item.GetItemStats` and item info (V-04).
- **Event recorder:** registers a fixed list of events (all in Section 8, plus `ENCOUNTER_START`, `ENCOUNTER_END`, `UNIT_SPELLCAST_SUCCEEDED`, `CHAT_MSG_ADDON`, `CHAT_MSG_PARTY`, `CHAT_MSG_RAID`, `CHAT_MSG_SKILL`) and logs timestamp, event name, and arguments. For each argument, log the type and whether `issecretvalue(arg)` is true (if available); never perform arithmetic or comparisons on arguments (which errors on secrets).
- **Comms test:** `/wwprobe ping` sends an add-on message (`C_ChatInfo.SendAddonMessage`, prefix `WWPROBE`) and a party/raid chat line `[WW:PING]`; receipt is logged on any client running the probe (V-08, V-09).
- **Encounter test script** (documented in `docs/PROBE_RESULTS.md`): enter a dungeon boss fight with a second player running the probe; cast a known ability; `/wwprobe ping` mid-fight; check logs afterwards for V-06 to V-09.

**Output.** Hugh pastes `WarriorWorkshopProbeDB` (from `WTF/Account/<acct>/SavedVariables/WarriorWorkshopProbe.lua`) into the repo; Claude Code summarises it into `docs/PROBE_RESULTS.md` and records decisions in `docs/DECISIONS.md`.

---

## 10. Testing and quality

- **Lua 5.1** semantics (WoW's runtime). No `goto`, no integer division operator, no `utf8` library.
- **luacheck** with a `.luacheckrc` that declares WoW globals used by Adapter/UI and forbids new globals elsewhere.
- **busted** unit tests for all pure logic: planner scoring and ranking, gear scoring and slot rules, readiness thresholds, migrations, utilities. Modules receive a mock Adapter from `tests/helpers/mock_adapter.lua`; fixtures live in `tests/fixtures/`.
- **CI (GitHub Actions):** luacheck and busted on every push and PR, Lua 5.1 via a standard setup action plus LuaRocks.
- **Release:** on tag `v*`, zip `WarriorWorkshop/` as `WarriorWorkshop-<version>.zip` and attach to the GitHub release.
- **In-game verification:** Claude Code cannot run the game. Each milestone ends with `docs/verification/M<n>.md`, a short checklist Hugh runs in the client. A milestone is complete only when Hugh confirms the checklist.
- **Error visibility:** `DEV_SETUP.md` explains enabling Lua errors (`/console scriptErrors 1`) and optionally an error-capture add-on if one is available for Forever.

---

## 11. Build plan (milestones)

Each milestone: implement → unit tests green → luacheck clean → update `docs/HANDOFF.md` → write `docs/verification/M<n>.md` → **stop for Hugh's in-game check** (where marked).

| # | Milestone | Deliverables | Acceptance | Human check |
|---|---|---|---|---|
| **M0** | Scaffold | Repo structure (Section 4), README, CLAUDE.md, LICENSE, .gitignore, .editorconfig, .luacheckrc, .busted, CI workflows, DECISIONS.md seeded with D-001 to D-004, DEV_SETUP.md, empty-but-loading add-on with `.toc` and `/ww version` | CI green; add-on loads in client and `/ww version` prints | Yes (load test) |
| **M1** | Probe | `WarriorWorkshopProbe` per Section 9; PROBE_RESULTS.md template with the encounter test script | Probe loads; `/wwprobe` writes SavedVariables | **Yes — run in beta before 21 Oct** |
| M2 | Core | Init, Events bus, DB + defaults, Migrations (+ tests), Log, Util, Adapter skeleton updated from probe findings | Unit tests for DB/migrations; no globals leak | Yes (reload persists settings) |
| M3 | Inventory | Inventory module + adapter functions | Bag/bank counts correct; bank cache persists | Yes |
| M4 | Professions | Recipe cache, colour observations, craft log, calibration | Cache persists; craft log entries correct | Yes |
| M5 | Prices + Planner | Prices module, `/ww price`, Planner logic (+ thorough tests) | Ranking matches fixture expectations | No (logic only) |
| M6 | UI shell + Planner tab | MainFrame, tabs, combat auto-hide, PlannerTab | Planner usable end-to-end in game | Yes |
| M7 | Gear | Stat normalisation, scoring, slot rules (+ tests), GearTab, weights editor, double wins | Upgrades sensible; explanations shown | Yes |
| M8 | Readiness | Readiness module, ReadyTab, `/ww ready` | Traffic lights correct | Yes |
| M9 | Hardening + 0.1.0 | Error handling pass, performance check (no scan > 5ms typical), README usage, tag `v0.1.0` | **v1 acceptance test passes** | Yes |

**v1 acceptance test.** After a mining session, Hugh opens `/ww` and within 10 seconds knows (a) what to craft next and how many, (b) what to mine or buy for the next batches, (c) whether anything he can make or holds is an upgrade for his active profile, and (d) whether he is ready to group.

**Timing note.** M0 and M1 must be complete in time for Hugh to run the probe before the beta closes on 21 October 2026. M2 onwards can proceed against mocks between beta close and launch, with in-game checks resuming at launch.

---

## 12. Coding conventions

- File header: `local addonName, ns = ...` then module locals.
- `PascalCase` for module methods, `camelCase` for locals and fields, `UPPER_SNAKE` for constants.
- Pure functions take explicit inputs; no hidden reads of SavedVariables inside scoring/ranking.
- Every public module function has a short doc comment stating inputs, outputs and side effects.
- Defensive API use: Adapter wraps calls that may be missing with existence checks; logs a single warning per missing API per session.
- Never perform comparisons or arithmetic on values that may be secret; v1 should not touch combat values at all.
- Conventional commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`); one milestone per PR or a small series of commits on `main` (solo project).
- Money is stored in copper (integers) and formatted only in UI.

---

## 13. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| API differs from Midnight assumptions | High | High | Phase 0 probe; Adapter seam; [VERIFY] discipline |
| Beta → launch API changes | Medium | Medium | Adapter; graceful degradation; re-run probe at launch |
| Placeholder stat weights mislead | High | Medium | Labelled "placeholder"; editable; explanations shown |
| Skill-up odds wrong | Medium | Low | Calibration from own crafts; show assumed vs observed |
| Scope creep into combat features | Medium | Medium | v1 out-of-scope list; v2/v3 outline only |
| Blizzard tightens add-on rules further (affects v2/v3) | Medium | High (v3) | v1 has no combat dependency; v3 design includes chat-tag fallback |
| No in-game testing between beta close and launch | Certain | Medium | Unit tests with mocks; verification batch at launch |
| SavedVariables growth | Low | Low | Ring buffer on craft log; prune stale recipes on request |

---

## 14. Decision log seed (`docs/DECISIONS.md`)

| ID | Decision | Rationale |
|---|---|---|
| D-001 | Add-on in subfolder of a mono-repo with probe, tests, docs, tools | Supports v2 Python tooling and Phase 0 without separate repos |
| D-002 | All WoW API access via `Core/Adapter.lua` | API drift containment; testability |
| D-003 | No external libraries (Ace3 etc.) in v1 | Fewer dependencies during unstable beta; revisit for v2 config UI and comms |
| D-004 | v1 entirely out of combat; UI hides on combat | Secret values / encounter restrictions; Blizzard policy risk |
| D-005 | *(to be added after Phase 0)* Interface number and folder name | From probe |

---

## 15. v2 and v3 outline (not for build)

**v2 — Personal cooldowns and analysis loop**

- Per-boss cooldown plan: list of `{ t = seconds from pull, spellID, note }`, displayed as a timeline driven by encounter elapsed time (requires V-06).
- Own-cast logging during encounters (requires V-07): `{ encounterID, t, spellID }` stored per kill/wipe.
- `tools/analysis/` Python package: parse SavedVariables (Lua table → JSON), join to Warcraft Logs exports where available, derive cooldown timing distributions by boss/phase, and emit plan templates as a Lua table the add-on imports.
- Possible integration with Blizzard's Cooldown Manager for display, rather than duplicating it.

**v3 — Warrior raid coordination**

- Class lead builds assignments (Shield Wall rotation, Challenging Shout, Demoralising Shout uptime, Battle Shout ownership) and syncs them to raid warriors **before the pull** via add-on messages.
- In-fight: every client shows the shared timeline; live cast sharing via a macro that casts the ability and posts a short chat tag (`[WW:<spellID>]`) if V-09 confirms tags are readable, otherwise manual click-to-mark.
- Post-fight: each warrior's client syncs its own cast log after `ENCOUNTER_END`; adherence report (planned vs actual) shown to the lead.
- Adoption dependency: requires guild warriors to install; design for graceful partial participation.
