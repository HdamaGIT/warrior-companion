# CLAUDE.md — Warrior Workshop

Working rules for Claude Code in this repo. Read this at the start of every session. Detail lives in `docs/SPEC.md`; if the two conflict, the spec wins unless `docs/DECISIONS.md` says otherwise.

## Project in one paragraph

Warrior Workshop is a World of Warcraft: Forever add-on for a warrior main (mining, blacksmithing, later engineering). v1 answers: *"What is the cheapest next step that makes me stronger and levels my professions?"* via an inventory cache, profession recipe cache, skill-up planner, crafted-gear advisor and readiness panel. v2 (cooldown plans + Python analysis loop) and v3 (warrior raid coordination) are outlined in the spec but **not in build scope**.

## Session start

1. Read `docs/HANDOFF.md` (latest state, next step, open questions).
2. Read the relevant sections of `docs/SPEC.md` for the current milestone (Section 11).
3. Check `docs/DECISIONS.md` and `docs/PROBE_RESULTS.md` for anything that overrides the spec.
4. Confirm the milestone you are working on before writing code.

## Session end

- Update `docs/HANDOFF.md`: what was done, what's next, open questions, any assumptions made.
- Record any decision that changes or clarifies the spec in `docs/DECISIONS.md` (next D-number, decision, rationale).
- Ensure luacheck and busted pass before declaring anything done.

## Milestone workflow

- Work one milestone at a time, in the order in `docs/SPEC.md` Section 11. Do not start the next milestone without explicit approval.
- Each milestone: implement → unit tests → luacheck clean → write `docs/verification/M<n>.md` → update handoff → **stop**.
- You cannot run the game. A milestone marked "Human check" is complete only when Hugh confirms the in-game checklist. Write checklists as short, concrete steps with the expected result for each.
- Do not ask clarifying questions when a reasonable assumption lets you proceed: state the assumption in the handoff or decisions log and continue. Do ask before anything irreversible or anything that expands scope.
- Challenge the spec when you think it is wrong. Raise it, propose the alternative, and record the outcome.

## Architecture rules (non-negotiable)

```
UI (frames/tabs)     → reads module view-models only
Modules (logic)      → pure Lua; no WoW globals; testable with mock Adapter
Core (Events/DB/Adapter) → the only layer touching WoW APIs
```

- **Only `Core/Adapter.lua` calls Blizzard data APIs.** UI files may use frame APIs (`CreateFrame`, templates, tooltips) but get data from modules.
- Modules return **plain Lua tables**. Planner and Gear scoring are **pure functions of explicit inputs**; never read SavedVariables inside scoring/ranking.
- Every file starts `local addonName, ns = ...` and attaches to `ns`. **No new globals** except `WarriorWorkshopDB`, `WarriorWorkshopCharDB`, the probe's `WarriorWorkshopProbeDB`, and slash command registrations.
- Modules register via `ns:NewModule(name)` with `OnInitialize` / `OnEnable`. Subscribe to game events via `ns.Events:On(...)`; publish internal messages prefixed `WW_` via `ns.Events:Fire(...)`. UI subscribes to `WW_*` messages only, never raw game events.
- New `.lua` files must be added to the `.toc` in load order (Locale → Core → Modules → UI).

## Forever API constraints

- Forever uses the **Mainline (Midnight 12.x) API**, not Classic. Do not use Classic-only globals (e.g. `GetTradeSkillInfo`, `GetContainerItemInfo`); use `C_TradeSkillUI`, `C_Container`, `C_Item` and friends via the Adapter.
- **Secret values:** combat state may be opaque to add-ons, especially during boss encounters and Mythic+. Never do arithmetic, comparisons, concatenation or table-key use on any value that could be secret. v1 must not depend on combat values at all.
- v1 runs **out of combat only**. The UI hides on `PLAYER_REGEN_DISABLED`. Never call protected functions or attempt actions that taint in combat.
- **[VERIFY] discipline:** anything tagged [VERIFY] in the spec is unconfirmed. Wrap it in an existence check in the Adapter, degrade gracefully (return `nil`, log once), and do not build hard dependencies on it until `docs/PROBE_RESULTS.md` records the result.
- **Observe, don't hardcode:** no Classic recipe tables, skill thresholds or stat assumptions shipped as truth. Defaults (stat weights, skill-up odds) are labelled placeholders and user-editable.

## Lua and code conventions

- **Lua 5.1** (WoW runtime): no `goto`, no `//`, no `utf8` library, no integer/bitwise operators from 5.3.
- `PascalCase` module methods, `camelCase` locals/fields, `UPPER_SNAKE` constants.
- Short doc comment on every public module function: inputs, outputs, side effects.
- Money stored as integer copper; format only in UI.
- Debounce bursty events (e.g. `BAG_UPDATE_DELAYED`, 0.5s). Keep typical scans under ~5ms; never poll with `OnUpdate` when an event exists.
- SavedVariables changes require a migration in `Core/Migrations.lua` plus a unit test. Never silently drop user data; mark stale instead.
- Player-facing strings go through `Locale/enUS.lua`. UK English in docs and comments; in-game text uses the game's spellings for game terms.

## Testing and tooling

- `luacheck .` must be clean. `.luacheckrc` whitelists WoW globals only for `Core/Adapter.lua`, `UI/`, `Core/Init.lua` and the probe.
- `busted` for all pure logic: planner, gear scoring and slot rules, readiness thresholds, migrations, utilities. Use `tests/helpers/mock_adapter.lua` and fixtures in `tests/fixtures/`; don't stub WoW globals inside module tests.
- Add a test for every bug fixed.
- CI (`.github/workflows/ci.yml`) runs luacheck and busted on Lua 5.1; keep it green.

## Git

- Conventional commits: `feat:`, `fix:`, `test:`, `docs:`, `chore:`, `refactor:`.
- Commit after each logical step; small and reviewable.
- Releases: tag `vX.Y.Z` on `main`; the release workflow zips `WarriorWorkshop/`.

## Things not to do

- Don't write v2/v3 code (cooldown timelines, cast logging, raid sync, Python analysis) until v1 ships.
- Don't add external libraries (Ace3, LibStub, etc.) in v1 (Decision D-003).
- Don't add features outside the current milestone, even if small. Note them in the handoff as ideas.
- Don't fabricate API behaviour. If unsure whether a Forever API exists or what it returns, say so, guard it, and add it to the probe or a verification checklist.
- Don't edit `docs/SPEC.md` silently. Propose spec changes; record agreed ones in `docs/DECISIONS.md` and update the spec in a `docs:` commit.

## Key files

| File | Purpose |
|---|---|
| `docs/SPEC.md` | Full specification and build plan |
| `docs/HANDOFF.md` | Session-to-session state |
| `docs/DECISIONS.md` | Decision log (overrides spec) |
| `docs/PROBE_RESULTS.md` | Phase 0 API findings |
| `docs/DEV_SETUP.md` | Windows junction, reload loop, local tooling |
| `docs/verification/M<n>.md` | In-game checklists per milestone |
| `WarriorWorkshop/Core/Adapter.lua` | The only Blizzard API boundary |
