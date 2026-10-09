# Handoff: 2026-10-09: M2 Core

## Session goal
Build M2 (Core) from SPEC §11 ahead of the M1 probe run, at Hugh's explicit request: Init, event bus, DB with defaults, migrations, Log, Util, and the Adapter skeleton.

## Outcome
**Achieved, pending human check.** M2 is built, luacheck is clean and busted is green on CI. The in-game check is `docs/verification/M2.md` ("reload persists settings"). **M0 and M1 in-game checks are still outstanding**, and the Adapter beyond M0's three functions is an **unverified skeleton** (D-015) until `docs/PROBE_RESULTS.md` is filled in. M3 has not been started and needs explicit approval.

## What was read
`CLAUDE.md`, SPEC §5, §6, §7.5 to §7.9, §8, `docs/DECISIONS.md`, the previous handoff, `.luacheckrc`, `.busted`, `.github/workflows/ci.yml`, `tests/toc_spec.lua` and every file under `WarriorWorkshop/`.

## What was changed
- `WarriorWorkshop/Core/Util.lua`: `DeepCopy`, `MergeDefaults`, `RingPush`, `Trim`, `Split`, `FormatMoney` (pure).
- `WarriorWorkshop/Core/Log.lua`: `Debug`, `WarnOnce`, `IsDebug`, `SetDebug`, `ToggleDebug`. Output via `ns.Adapter.Print`; flag in `settings.debug`.
- `WarriorWorkshop/Core/Adapter.lua`: full SPEC §5.3 surface plus `Time`, `Now`, `After`, `CreateEventFrame`, `GetPlayerMeta`, and the pure `NormaliseStats` with the `STAT_KEYS` table. Every API is existence-checked, wrapped in `pcall`, returns `nil` and warns once on failure, and is tagged `[VERIFY V-0x]`. The header says there are no probe findings.
- `WarriorWorkshop/Core/Events.lua`: `On`, `Off`, `Fire`, `Dispatch`, `Debounce`. Lazy raw-event registration, `pcall` isolation, snapshot dispatch.
- `WarriorWorkshop/Core/Migrations.lua`: `ACCOUNT` and `CHARACTER` lists (both empty at v1) and pure `Apply(db, migrations, target)`.
- `WarriorWorkshop/Core/DB.lua`: `GetAccountDefaults`, `GetCharacterDefaults`, pure `Prepare`, `Init`, accessors, `UpdateMeta`, `StampLastSeen`. No globals touched.
- `WarriorWorkshop/Core/Init.lua`: `ns:NewModule`, `ns:GetModule`, ADDON_LOADED / PLAYER_LOGIN / PLAYER_LOGOUT lifecycle, `/ww version` (real schema) and `/ww debug`.
- `WarriorWorkshop/Locale/enUS.lua`: new strings. `WarriorWorkshop.toc`: Locale, Util, Log, Adapter, Events, Migrations, DB, Init.
- `.luacheckrc`: extra read-only WoW names for the Adapter (`C_Timer`, unit and inventory APIs); Init may also write the two SavedVariables.
- Tests: `util`, `migrations`, `db`, `events`, `log`, `adapter`, `init` (incl. the no-globals-leak test) specs; real `tests/helpers/mock_adapter.lua` (fake frame, manual timer) and `tests/helpers/load_addon.lua`; fixtures `item_stats.lua`, `saved_account.lua`; `toc_spec.lua` also checks the Core load order.
- Docs: D-012 to D-015, `docs/verification/M2.md`, README status. `docs/verification/M0.md` step 4 wording updated (schema is now `1`).
- `.github/workflows/ci.yml`: fixed a raw newline in the simulator notice step that made the whole workflow invalid (GitHub ran zero jobs). That step came from the simulator commit, not from M2.

## Verification state (pasted, not recalled)
No local Lua toolchain, so **CI is the verifier**. CI run **37879401020** on commit `1563571`, annotations fetched via the GitHub API:
```
conclusion: success
luacheck:  Total: 0 warnings / 0 errors in 41 files
busted:    ok=119 not_ok=0 3 pending   (3 pending = planner, gear, readiness placeholders)
simulator: Ran 26 tests in 0.036s OK
```
The first M2 run (`afc5d15`) was also green (busted 119 ok, luacheck 0/0 in 35 files). Run 37879357085 failed only because of the invalid `ci.yml` described above.

## Git state
Branch `main`, pushed to `origin/main`. `docs/SPEC_LEVELING.md` is staged in the index (`AM`) by something outside this session and was deliberately left out of every commit. `tools/sim/` was committed by the simulator work (b55ce19, b344f2a), also not by this session.

## Decisions
D-012 backup inside the SavedVariables table; D-013 event frame and timer come from the Adapter; D-014 planner odds settings in schema v1; D-015 M2 built before the probe, Adapter is unverified. (The plan named these D-011 to D-014; D-011 was taken by the simulator decision, so they were shifted by one.)

**Assumptions:**
- `settings.window` defaults to `CENTER`, 0, 0, 640x480, tab `planner` (SPEC lists only the field names).
- An empty saved table is treated as first run; a non-empty table without a numeric `schemaVersion` is corrupt and is backed up.
- Migrations are split into `ACCOUNT` and `CHARACTER` lists, because the two tables version independently.
- `Events:Debounce` is trailing-edge from the first call (no restart on later calls), and later calls replace the stored function.
- Bag IDs `0..5`, bank IDs `-1, 6..12`, equipment slots `1..19` are guesses. The bank is treated as closed when its containers report zero slots.
- `ITEM_MOD_*` table lists both `_SHORT` and bare spellings; armour is read from `RESISTANCE0_NAME`; `weaponSpeed` has no mapping yet.
- `Adapter.IsUsableByPlayer` uses `C_Item.IsUsableItem`, which may mean "has a use effect" rather than "equippable". Revisit with V-06.

## Open items / known issues
- M0 and M1 in-game checks, and filling `docs/PROBE_RESULTS.md`, are outstanding. Once the results arrive, revise the Adapter (all `[VERIFY]` tags) and record D-005.
- Warnings like `API unavailable: ...` in chat at the first M2 login are expected findings, not bugs. Paste them back.
- Carried from before: `/ww ready` has two meanings in SPEC §7.9 (M6/M8); the Midnight bank layout may differ (M3); the `leafo/gh-actions-*` Node 20 deprecation and the `ubuntu-latest` move on 19 Oct 2026.
- Idea (not built): flag gear profiles as `placeholder = true` so the UI can label them until edited.

## Progress doc position
No PROGRESS or STATUS doc exists; the `README.md` status table is the progress view (M0 and M1 built, M2 built, all awaiting in-game checks).

## Suggested next prompt
> Read CLAUDE.md, docs/HANDOFF.md, docs/DECISIONS.md and docs/PROBE_RESULTS.md. Here are my M2 checklist results (and any M0/M1 results and probe SavedVariables): <paste>. Fix anything M2 turned up, fill in docs/PROBE_RESULTS.md, and revise the Adapter `[VERIFY]` functions against it, recording decisions. Don't start M3 until I approve it.
