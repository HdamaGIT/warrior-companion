# Handoff: 2026-10-10: beta run 2 analysed (after the 9 Oct SPEC_V2 adoption, M3 and M2)

## Session goal
Adopt `docs/SPEC_V2.md` (review, conflicts, challenges, plan approved by Hugh), then build **M3** (probe extension, urgent: must run in the beta before **21 Oct 2026**) and finish **M2** to the SPEC_V2 definition. Stop after both for Hugh's in-game run.

## Outcome
**Achieved, pending human check.** M3 and M2 are built and CI is green (see verification below). Nothing has run in Forever yet: the M0, M1, M2 and M3 in-game checks are all outstanding, and **one combined beta session** covers them (script at the end of `docs/PROBE_RESULTS.md`). M4 and later have not been started.

**`CLAUDE.md`** for SPEC_V2 approved and committed (9 Oct). **SPEC_V2 errata (D-029)** approved and applied (spec version 2.0.1).

## What was done
- **Docs:** `SPEC.md` has the superseded banner (`SPEC_LEVELLING.md`/`SPEC_LEVELING.md` is not in the repo; nothing to banner). `SPEC_V2.md` and `IDEAS_BACKLOG.md` are committed. `DECISIONS.md`: SPEC_V2's D-006..D-018 recorded as **D-016..D-028** (mapping in D-030), D-004 marked amended by D-017, plus D-029 (SPEC_V2 errata), D-031 (build order), D-032 (probe design), D-033 (restricted detection), and proposals P-1..P-8, which Hugh accepted on 10 Oct as **D-036..D-043** (applied to SPEC_V2 2.0.2). README points at SPEC_V2. `PROBE_RESULTS.md` has V-11..V-33 (V-20 retired), the decision gate table, and the combined beta run script. New `docs/verification/M3.md`; `M2.md` rewritten for schema 2; `M0.md` schema number updated.
- **M3 probe (version 2):** `Probe.lua` refactored (`ns.Listen` with record/count modes, per-session caps and unit-filtered frames; `ns.AddCommand`; context flag; `CallIsTrue`/`SafeFirst`/`After` helpers; all handlers and timers in `pcall`, errors to `handlerErrors`). New `Dumps.lua` (spells, trainer incl. auto on `TRAINER_SHOW`, tank), `Combat.lua` (0.25s sampler aggregated per field and context, usability transitions, CLEU capped 300/session + 150 misses, `UNIT_COMBAT` fallback, nameplates, trigger-event counts), `Actions.lua` (chat via timer judged by echoes and `ADDON_ACTION_BLOCKED`, `chatkey` via `Bindings.xml`, sets, swapbtn on `CTRL-SHIFT-F9` without `SaveBindings`, macro, status), `Bindings.xml`. `tests/probe_spec.lua` plus `tests/helpers/probe_client.lua` (fake client in full, missing, secret and no-checker modes).
- **M2 to SPEC_V2:** schema v2 defaults and v1→v2 migrations (`hideInCombat`→`hideMainInCombat`; v1 `gear` weights → `advisor`); `Core/Context.lua` and `Core/SpellMap.lua` stubs with new guarded Adapter reads (`GetZoneKind`, `GetGroupKind`, `IsPlayerDead`, `IsEncounterInProgress`, `IsChallengeModeActive`, `GetSpellIDByName`, `IsPlayerSpell`); `[VERIFY]` tags corrected; `GetEquipmentSets` returns `id`/`icon`; Workshop placeholders moved to the SPEC_V2 layout. Simulator fakes for the new APIs (ASSUMED where unconfirmed) plus two end-to-end sim tests.

## Verification state (pasted, not recalled)
CI is the verifier for luacheck (no local luacheck). Local checks used lupa's Lua 5.1 with a busted-compatible shim in the session scratchpad (not committed); CI's real busted is authoritative.
```
CI run 37974376379 on 0f554e5: conclusion success
luacheck:  Total: 0 warnings / 0 errors in 51 files
busted:    ok=191 not_ok=0 3 pending   (3 pending = planner, advisor, readiness placeholders)
simulator: Ran 28 tests in 0.070s OK
local shim (lupa Lua 5.1): TOTAL ok=188 fail=0 pending=3
```
CI was red between `1218551` and `52ecc92` (three placeholder comment lines over 120 characters), fixed in `0f554e5`.

## Assumptions (logged here, not asked)
- M3 was built before finishing M2 (D-031); both landed this session.
- Probe: swap key `CTRL-SHIFT-F9`; chat text `[WWPROBE test]`; caps per D-032; ability names use the game's US spellings ("Demoralizing Shout", "Sunder Armor").
- HUD default positions in schema v2 (`alertStrip` y = -150, `bigAlert` y = 120, `combatText` y = 40, `badges` y = -200, all `CENTER`) are placeholders until `/ww unlock` exists (M5).
- `announce.events`, `combat.ruleOverrides` and `combat.spellOverrides` default to empty tables. SPEC_V2 §6 is compatible with sparse overrides (sparse overrides are now D-039).
- `gear.sets[].key` / `weaponSwaps[].key` are not in the defaults: both start as empty tables, which matches D-040 (keys live in Key Bindings).
- SpellMap listens to `SPELLS_CHANGED` only (debounced 0.5s), not `LEARNED_SPELL_IN_TAB`, whose name may have changed in 11.x; the probe records both registrations.
- Context `group` is `solo`/`party`/`raid` only; the LFG-group distinction for `INSTANCE_CHAT` routing is D-038 and is built in M7.
- A migrated v1 account keeps `window.tab = "planner"`; the M6 UI must fall back when a saved tab does not exist.

## Beta run 2 (10 Oct)
Collected into `beta-results/2026-10-10_154007/`. Probe v3 worked: no popup at login, 893 combat samples, no handler or Lua errors. Client is now build 70338 (Interface still 16001).
- **Headline:** open-world combat activates restriction type 0 ("Combat"). In combat, auras (by name: `nil`; by index: **error**), cooldown times, rage, health and target casting are secret. Usability, range, auto-attack, stance, target level/classification/reaction, threat, own `UNIT_SPELLCAST_*` and `UNIT_COMBAT` stay readable.
- Results in `docs/PROBE_RESULTS.md` (Run 2 section, V-10..V-33 filled), gate filled. Decisions **D-044** (gate, provisional until the group run), **D-045** (restriction detection via `Enum.AddOnRestrictionType`; `C_Secrets` pre-check before aura reads), **D-046** (secure buttons: one click edge, idempotent swaps).
- **Spec impact (agreed and applied, SPEC_V2 2.1, commits 669ff9d and 6b2eee5):** SPEC_V2 §5.5/§7.4 (avoidance on `UNIT_COMBAT`), §7.1 conditions (drop rage/health conditions; Battle Shout from own casts), §7.2/§7.3/§8.1 (R-06, R-11, A-08 No-go; U-01/R-03/A-01/A-04 Degraded).
- Not answered yet: V-31 built-ins (Hugh gave no notes), DODGE/BLOCK/RESIST in `UNIT_COMBAT`, target cast events (no caster fought), Overpower/Execute windows (not known at level 8), all group/instance/encounter items.

## Open questions for Hugh
1. V-31 notes on the built-ins (Cooldown Manager, floating combat text, swing timer, loss-of-control). Not blocking M5.

## Notes for M5 (from the simulator session, 9 Oct)
- Hugh approved a **visual preview** of UI frames, rendered from the simulator into HTML, starting with the first UI milestone (M5 HUD under D-031). Build frames from plain `CreateFrame` + `SetPoint`/`SetSize`/FontStrings/textures, with minimal Blizzard templates; keep HUD layout in data; drive the 0.2s ticker through the Adapter/C_Timer (no `OnUpdate`), so the simulator clock can run it. **The preview is already built** (D-047, `docs/DEV_SETUP.md` §7): `python tools/sim/sim.py run --open "<command that shows the HUD>" "!snapshot hud"` writes `sim-out/hud.html`; in tests, `Client.snapshot(path)` returns (path, layout warnings). Anchor HUD frames to `UIParent` explicitly: a `CreateFrame` with no parent is parentless in the simulator, as in the client.
- Consider building the M5 replay harness on `tools/sim` (replaying a recorded stream through `Client.fire`/`advance`) and adding a secret-value fake to `tools/sim/lua/api.lua`; record the choice as a decision. `tests/helpers/probe_client.lua` already has a secret proxy that can be reused.
- As Adapter functions go live, add an ASSUMED fake in `tools/sim/lua/api.lua` and an end-to-end test in `WarriorWorkshopTests`; scenario IDs are fake (9xxxxx).

## Other open items
- After the beta run: fill in `PROBE_RESULTS.md` V-01..V-33 and the decision gate, record D-005 (interface, folder), revise the Adapter `[VERIFY]` functions, and turn probe logs into replay fixtures.
- Carried: the `leafo/gh-actions-*` Node 20 deprecation and the `ubuntu-latest` move to Ubuntu 26 on 19 Oct 2026 (CI annotations).
- `sim-save/` (untracked, from a simulator run outside this session) was left alone.

## Next step
**M5 (combat core + must-have alerts + HUD), approved by Hugh on 10 Oct, in a fresh session.** Build to SPEC_V2 2.1 §5, §7.1, §7.2, §7.4, §7.5, §7.7 and §15 with the gate in D-044 (Go: S-04, X-01, R-01; Degraded: U-01 from own casts, R-03 usability only, avoidance detector on `UNIT_COMBAT`; No-go: R-06, R-11; X-06 off the launch target, D-043). Context `restricted` per D-045. Use the run 2 data (`beta-results/2026-10-10_154007/`, git-ignored, local only) for replay fixtures. The HTML visual preview for the HUD is built (D-047). The run 2 restriction and secret-value fakes are **not** in `tools/sim/lua/api.lua` yet; the simulator session (`warrior-companion-9c`) can add them on Hugh's go-ahead, so coordinate with it before changing `tools/sim/`.

**Simulator preview is ready (D-047, commits 798ff93, 36b35f8):** `python tools/sim/sim.py run --open "/ww hud" "!snapshot hud"` writes `sim-out/hud.html`; in tests `Client.snapshot(path)` returns `(path, warnings)` and `Client.frames()` the raw layout (assert no layout warnings). `CreateFrame` with no parent is now parentless, so anchor HUD frames to `UIParent` explicitly; templates are drawn bare, so use plain frames. Example: `tools/sim/tests/fixtures/UiAddon/hud.lua`. Next decision number is **D-048**.

The group run (Stage 5 of `docs/BETA_TESTING.md`) is still worth doing before 21 Oct; it mainly affects M7.
