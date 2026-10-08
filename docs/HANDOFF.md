# Handoff: 2026-10-08: M0 scaffold and M1 probe

## Session goal
Build M0 (Scaffold) and M1 (Probe) from SPEC §11, get CI green, then stop for Hugh's in-game checks.

## Outcome
**Achieved, pending human checks.** Both milestones are built and CI is green. M0 needs the in-game load test (`docs/verification/M0.md`). M1 needs the probe run in the beta **before 21 Oct 2026** (`docs/verification/M1.md`, `docs/PROBE_RESULTS.md`). M2 has not been started and needs explicit approval.

## What was read
`CLAUDE.md`, `docs/SPEC.md` (in full), and the PyCharm sample `main.py` (removed).

## What was changed
- `docs/SPEC.md`: moved from the repo root, where the spec expects it. Content unchanged.
- `main.py`: deleted (PyCharm sample). `.idea/` is ignored.
- `LICENSE`, `.gitignore`, `.editorconfig`, `.gitattributes` (LF in the repo, because `core.autocrlf=true` locally).
- `.luacheckrc`: Lua 5.1 std. WoW globals (`stds.wow`) are allowed only for `Core/Adapter.lua`, `Core/Init.lua`, `UI/*.lua` and the probe. The only global writes allowed are the SavedVariables and slash globals.
- `.busted`: runs `tests/*_spec.lua`.
- `.github/workflows/ci.yml`: Lua 5.1.5 with LuaRocks, then luacheck and busted. Failures and totals are emitted as **annotations**, because job logs aren't readable without auth but annotations are public via the API.
- `.github/workflows/release.yml`: on tag `v*`, stamps `## Version:` from the tag, zips `WarriorWorkshop/` and attaches the zip to a GitHub release.
- `WarriorWorkshop/WarriorWorkshop.toc`: Interface 120105 (`TODO [VERIFY V-01]`), both SavedVariables; loads `Locale/enUS.lua`, `Core/Adapter.lua`, `Core/Init.lua`.
- `WarriorWorkshop/Core/Adapter.lua`: minimal `Print`, `GetBuildInfo`, `GetAddOnVersion` (D-006).
- `WarriorWorkshop/Core/Init.lua`: `/ww version`; any other `/ww …` prints "not available yet".
- `WarriorWorkshop/Locale/enUS.lua`: strings.
- Placeholders (comment-only, not in the `.toc`, D-010): `Core/{Events,DB,Migrations,Log,Util}.lua`, `Modules/*.lua`, `UI/*.lua`, `tests/{planner,gear,readiness,migrations,util}_spec.lua` (pending), `tests/helpers/mock_adapter.lua`, `tests/fixtures/.gitkeep`, `tools/analysis/README.md`.
- `tests/toc_spec.lua`: checks the Lua 5.1 runtime, and for both `.toc` files checks the Interface line, the SavedVariables, and that every listed file exists.
- `WarriorWorkshopProbe/`: the probe per SPEC §9, plus `gear`, `bags`, `rec` and `clear` subcommands and a compact all-recipes view. The secret-safety design is in D-007, D-008 and D-009.
- `docs/DECISIONS.md` (D-001..D-010), `docs/DEV_SETUP.md`, `docs/PROBE_RESULTS.md` (template and encounter script), `docs/verification/M0.md`, `docs/verification/M1.md`, `README.md`.

## Verification state (pasted, not recalled)
No Lua toolchain is installed locally (no Lua, LuaRocks, WSL or Docker), so **CI is the verifier**. CI run 37848304667 on commit `1adb690`, annotations fetched via the GitHub API:
```
conclusion: success
luacheck: Total: 0 warnings / 0 errors in 27 files
busted:   ok=12 not_ok=0 5 pending      (7 real tests + 5 pending placeholders)
```
The first CI run (`93ed564`) failed luacheck: three placeholder comment lines were over 120 characters. This was fixed in `5ba2774`.

## Git state
Branch `main`, pushed to `origin/main`. Everything is committed apart from this handoff commit. Next session: work on `main` (solo project, per SPEC §12).

## Decisions made
D-006 to D-010 in `docs/DECISIONS.md`: minimal Adapter in M0; probe stores values only when confirmed non-secret; `pcall` around event registration and player-only unit events; addon prefix registration and the extra chat channels; placeholders kept out of the `.toc`. D-005 (interface and folder) waits for Hugh's numbers.

**Assumptions:**
- The probe initialises on `PLAYER_LOGIN`, not `ADDON_LOADED`, so it never compares an event argument. Events before `PLAYER_LOGIN` aren't recorded.
- The secret-API names beyond `issecretvalue` are guesses; the probe only checks whether they exist.
- The licence holder is "Hugh".

## Open items / known issues
**Flagged spec issues for later milestones (not decided yet):**
- **M2:** SPEC §6 backs up corrupt data to `WarriorWorkshopDB_backup`. That is a new global, and it would not persist because it isn't declared in the `.toc`. Proposal: store the backup inside `WarriorWorkshopDB`.
- **M2:** `Core/Events.lua` needs `CreateFrame`, but luacheck only whitelists Adapter, Init and UI. Proposal: the Adapter provides the event frame.
- **M6/M8:** SPEC §7.9 uses `/ww ready` for both "open the Ready tab" and "chat summary". Needs one meaning.
- **M5:** SPEC §7.5 says the odds threshold and defaults "live in settings", but they are missing from the §6 schema.
- **M3:** Midnight bank tabs may have replaced bank bags and `PLAYERBANKSLOTS_CHANGED`. `/wwprobe bags` at the bank and the `registrations` results will settle this.

**Other notes:**
- The `leafo/gh-actions-*` actions target Node 20; GitHub warns but still runs them. `ubuntu-latest` moves to Ubuntu 26 from 19 Oct 2026. Watch CI around then.
- The `.toc` `## Version:` is hard-coded at 0.0.1; the release workflow overwrites it from the tag.
- The probe is untested in a real client. Expect a fix-up round if the first `/wwprobe` errors. Paste the error text.

## Progress doc position
No PROGRESS or STATUS doc exists; the status table in `README.md` is the progress view (M0 and M1 built, awaiting checks).

## Suggested next prompt
> Read CLAUDE.md, docs/HANDOFF.md, docs/DECISIONS.md and docs/PROBE_RESULTS.md. Here are my M0 checklist results and my WarriorWorkshopProbe.lua SavedVariables: <paste>. Fill in docs/PROBE_RESULTS.md (V-01..V-10), record D-005 and any new decisions, fix the `## Interface:` lines if needed, and update the handoff. Don't start M2 until I approve it.
