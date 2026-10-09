# CLAUDE.md — Warrior Workshop

Working rules for Claude Code in this repo. Read this at the start of every session. Detail lives in `docs/SPEC_V2.md`; if the two conflict, the spec wins unless `docs/DECISIONS.md` says otherwise. `docs/SPEC.md` (v0.1) is superseded and kept for reference only.

## Project in one paragraph

Warrior Workshop is a World of Warcraft: Forever add-on for a warrior main. It leads with a **combat companion** (reactive, upkeep and failure alerts in the open world and dungeon trash), a **tank announcer** and **gear-set keybinds**, delivered for launch on 4 Nov 2026. The professions and itemisation "Workshop" (inventory, skill-up planner, gear advisor with tank stat sheet, readiness) follows as Phase E. Current scope is Phases A–E in `docs/SPEC_V2.md` §3 and §15; Phase F (raid coordination, cooldown plans, Python analysis, backlog items rated 3) is outline only.

## Session start

1. Read `docs/HANDOFF.md` (latest state, next step, open questions).
2. Read the relevant sections of `docs/SPEC_V2.md` for the current milestone (build plan in §15).
3. Check `docs/DECISIONS.md` and `docs/PROBE_RESULTS.md` for anything that overrides the spec. SPEC_V2's own decision numbers were remapped (D-030): its D-006..D-018 are D-016..D-028 in the log.
4. Confirm the milestone you are working on before writing code.

## Session end

- Update `docs/HANDOFF.md`: what was done, what's next, open questions, any assumptions made.
- Record any decision that changes or clarifies the spec in `docs/DECISIONS.md` (next D-number, decision, rationale).
- Ensure luacheck and busted pass before declaring anything done.

## Milestone workflow

- Work one milestone at a time, in the order in `docs/SPEC_V2.md` §15 as adjusted by `docs/DECISIONS.md` (D-031). Do not start the next milestone without explicit approval.
- Each milestone: implement → unit tests → luacheck clean → write `docs/verification/M<n>.md` → update handoff → **stop**.
- You cannot run the game. A milestone marked "Human check" is complete only when Hugh confirms the in-game checklist. Write checklists as short, concrete steps with the expected result for each.
- Do not ask clarifying questions when a reasonable assumption lets you proceed: state the assumption in the handoff or decisions log and continue. Do ask before anything irreversible or anything that expands scope.
- Challenge the spec when you think it is wrong. Raise it, propose the alternative, and record the outcome.

## Architecture rules (non-negotiable)

```
UI (HUD frames, main window tabs)  → reads view-models; subscribes to WW_* messages only
Feature modules (Combat, Announce, Gear, Workshop Modules)
                                   → pure Lua over snapshots, normalised events and config; no WoW globals
Core (Events/DB/Context/SpellMap, Adapter, Secure)
                                   → Adapter is the only data-API boundary; Secure the only protected-UI boundary
```

- **Only `Core/Adapter.lua` calls Blizzard data APIs.** UI files may use frame APIs (`CreateFrame`, templates, tooltips) for non-secure display frames, but get data from modules.
- **Only `Core/Secure.lua` creates secure frames, sets bindings or writes macros** (D-026). Nothing else touches `SecureActionButtonTemplate`, `SetBinding*`, `CreateMacro` or `EditMacro`.
- Feature logic is **pure over explicit inputs** (snapshots, normalised events, configuration). Condition evaluators, rule engines, scorers and rankers never read SavedVariables directly.
- Every file starts `local addonName, ns = ...` and attaches to `ns`. **No new globals** except `WarriorWorkshopDB`, `WarriorWorkshopCharDB`, the probe's `WarriorWorkshopProbeDB`, `BINDING_*` strings and binding handler functions required by `Bindings.xml`, and slash command registrations.
- Modules register via `ns:NewModule(name)` with `OnInitialize` / `OnEnable`. Subscribe to game events via `ns.Events:On(...)`; publish internal messages prefixed `WW_` via `ns.Events:Fire(...)`. UI subscribes to `WW_*` messages only, never raw game events.
- New `.lua` files must be added to the `.toc` in load order: **Locale → Core → Combat → Announce → Gear → Modules → UI**. Core files that call `ns:NewModule` (e.g. `Context.lua`, `SpellMap.lua`) load after `Core/Init.lua`.
- Alerts and announcements are **declarative tables** with a fixed condition vocabulary (D-019). New conditions need a spec change. No `loadstring`, no user Lua.

## Forever API constraints

- Forever uses the **Mainline (Midnight 12.x) API**, not Classic. Do not use Classic-only globals (e.g. `GetTradeSkillInfo`, `GetContainerItemInfo`); use `C_TradeSkillUI`, `C_Container`, `C_Item`, `C_Spell`, `C_UnitAuras` and friends via the Adapter.
- **Combat scope (D-017, amends D-004):** the combat HUD and announcer run in combat in the open world and in instances **outside restricted contexts** (boss encounters, Mythic+, anything Forever restricts). In restricted contexts they suspend cleanly (D-021): no errors, no stale displays, a "suspended" badge. **The main window still hides on `PLAYER_REGEN_DISABLED`.**
- **Secret values:** never do arithmetic, comparisons, concatenation or table-key use on any value that could be secret. Every combat value goes through an Adapter accessor that checks secrecy first; a secret or unavailable value returns `nil`, `nil` means unknown, and unknown means **not shown** (D-020).
- **Protected actions:** anything Blizzard protects goes through keybinds, secure buttons or out-of-combat paths only, with no workarounds.
  - Armour is never equipped in combat; set requests in combat are queued until `PLAYER_REGEN_ENABLED` (D-025).
  - Weapon swaps in combat only via secure action buttons or macros triggered by a key press.
  - SAY/YELL outdoors need a hardware event; announcer messages fall back to local output there (D-024).
  - No binding changes, macro writes, or secure frame creation/modification in combat; check `InCombatLockdown()` and return `false, "combat"`.
- No rotation or "press this next" engine (D-018). Display reactive windows, upkeep and failures only.
- **[VERIFY] discipline:** anything tagged [VERIFY] in the spec is unconfirmed. Wrap it in an existence check in the Adapter, degrade gracefully (return `nil`, log once), and do not build hard dependencies on it until `docs/PROBE_RESULTS.md` records the result and the decision gate (SPEC_V2 §12.2) marks the feature Go / Degraded / No-go.
- **Observe, don't hardcode:** abilities are resolved by name through `Core/SpellMap.lua` and auto-disabled if unknown. No Classic recipe tables, skill thresholds, spell IDs or stat assumptions shipped as truth. Defaults (stat weights, thresholds, messages, skill-up odds) are labelled placeholders and user-editable.
- **Check the built-ins** (Cooldown Manager, swing timer, floating combat text, loss-of-control frame) before building a duplicate (V-31).

## Lua and code conventions

- **Lua 5.1** (WoW runtime): no `goto`, no `//`, no `utf8` library, no integer/bitwise operators from 5.3.
- `PascalCase` module methods, `camelCase` locals/fields, `UPPER_SNAKE` constants.
- Short doc comment on every public module function: inputs, outputs, side effects.
- Money stored as integer copper; format only in UI.
- Debounce bursty events (e.g. `BAG_UPDATE_DELAYED`, 0.5s). Never poll with `OnUpdate` when an event exists; combat uses one shared ticker (0.2s).
- Performance: ≤ 0.5ms average per combat event handler, no allocation in hot paths; Workshop scans ≤ 5ms typical.
- SavedVariables changes require a migration in `Core/Migrations.lua` plus a unit test. Never silently drop user data; mark stale instead.
- Player-facing strings go through `Locale/enUS.lua`. UK English in docs and comments; in-game text uses the game's spellings for game terms.

## Testing and tooling

- `luacheck .` must be clean. `.luacheckrc` whitelists WoW globals only for `Core/Adapter.lua`, `Core/Secure.lua`, `Core/Init.lua`, `UI/` and the probe.
- `busted` for all pure logic: conditions, rule engine, avoidance detector, announce routing and throttles, macro generation, gear queue, planner, advisor and tank sheet, readiness, migrations, utilities. Use `tests/helpers/mock_adapter.lua`, the replay harness (`tests/helpers/replay.lua`, `mock_clock.lua`) and fixtures in `tests/fixtures/`; don't stub WoW globals inside module tests.
- **Secret mode:** a mock Adapter returning `nil` from every combat accessor must run the whole HUD and announcer without error and show nothing.
- Add a test for every bug fixed.
- `tools/sim/` is the offline client simulator (D-011); its tests run in CI.
- CI (`.github/workflows/ci.yml`) runs luacheck, busted on Lua 5.1 and the simulator tests; keep it green.

## Git

- Conventional commits: `feat:`, `fix:`, `test:`, `docs:`, `chore:`, `refactor:`.
- Commit after each logical step; small and reviewable.
- Releases: tag `vX.Y.Z` on `main`; the release workflow zips `WarriorWorkshop/`. Launch kit is `v0.5.0` (M9), Workshop is `v1.0.0` (M15).

## Things not to do

- No rotation / "press next" engine (D-018).
- No swing timer (D-023).
- No levelling analytics: XP dashboard, session review, mob intel, fight log (D-022).
- No Phase F work: raid coordination, cooldown plan timelines, own-cast logging in encounters, raid sync, Python analysis pipeline, or backlog items rated 3 or Pass in `docs/IDEAS_BACKLOG.md`.
- Don't add external libraries (Ace3, LibStub, etc.) (D-003).
- Don't add features outside the current milestone, even if small. Note them in the handoff as ideas.
- Don't fabricate API behaviour. If unsure whether a Forever API exists or what it returns, say so, guard it, and add it to the probe or a verification checklist.
- Don't edit `docs/SPEC_V2.md` silently. Propose spec changes; record agreed ones in `docs/DECISIONS.md` and update the spec in a `docs:` commit.

## Key files

| File | Purpose |
|---|---|
| `docs/SPEC_V2.md` | Specification and build plan (source of truth) |
| `docs/IDEAS_BACKLOG.md` | Triaged idea list behind SPEC_V2 |
| `docs/SPEC.md` | **Superseded** v0.1 spec, kept for reference (Workshop acceptance criteria still cited) |
| `docs/HANDOFF.md` | Session-to-session state |
| `docs/DECISIONS.md` | Decision log (overrides spec) |
| `docs/PROBE_RESULTS.md` | Probe findings (V-01..V-33) and the beta test script |
| `docs/DEV_SETUP.md` | Windows junction, reload loop, local tooling, simulator |
| `docs/verification/M<n>.md` | In-game checklists per milestone |
| `WarriorWorkshop/Core/Adapter.lua` | The only Blizzard data-API boundary |
| `WarriorWorkshop/Core/Secure.lua` | The only secure-frame, binding and macro-write boundary (M8) |
