# Handoff: 2026-10-10: M5 built (combat core, must-have alerts, HUD)

## Session goal
Build **M5** (SPEC_V2 2.1 §5, §7.1, §7.2, §7.4, §7.5, §7.7, §15) within the D-044 gate, then stop for Hugh's in-game check. Plan agreed with the orchestrator session (`review-spec-v2-build-plan`), which recorded **D-048** (M5 implementation decisions) and **D-049** (§5.2 erratum) and edited SPEC_V2 §4, §5.2, §5.4 and §7.1 (commit d20c578). Simulator changes coordinated with `warrior-companion-9c`.

## Outcome
**Built; pending human check.** CI is green. The in-game checklist is `docs/verification/M5.md`. M7 has not been started.

## What was done (commits d4c0960..42f326b on `main`)
- **Test harness:** `tests/helpers/mock_clock.lua`, `tests/helpers/replay.lua`, combat accessors on the mock adapter with secrecy modes (`run2`: what the beta saw; `all`: secret mode). Fixtures in `tests/fixtures/streams/`: four hand-transcribed run 2 fights (relative times, no raw files) plus `assumed_avoidance.lua` (DODGE/BLOCK/RESIST shapes, marked ASSUMED).
- **Adapter combat accessors** (`Core/Adapter.lua`). Each one checks `C_Secrets.Should*BeSecret` first, then `issecretvalue` on every value and field, inside `pcall`; secret or unavailable returns `nil`. Accessors: `GetRestrictionFlags`, `GetRage`, `GetHealthPct`, `IsSpellUsable`, `GetSpellCooldownRemaining` (falls back to `isActive` when the times are secret), `IsSpellInRange`, `IsAutoAttacking` (6603), `GetAura` (by name; `nil` when `ShouldAurasBeSecret`; never by index), `GetTargetState`, `GetStance`, `GetSpellName`, `GetSpellIcon`, `PlaySound`, `ReadUnitCombat`, `ReadSpellcast`, `SetSecretFallback`.
- **Context:** `restricted` comes from `C_RestrictedActions`: Encounter, ChallengeMode or PvPMatch Active (D-045). The Combat restriction (type 0) never suspends. Context also sets the Adapter's secret fallback (D-036). New `Context:Current()` gives a read without copying.
- **Combat/:**
  - `Conditions.lua`: full vocabulary, three-valued.
  - `AuraTracker.lua`: U-01 degraded tracking (D-048 (3)).
  - `Snapshot.lua`: reused tables.
  - `Rules.lua`: states, contexts, `delay`, `throttle`. It also reports when an aura timer will cross a threshold, so the companion wakes itself with no game event.
  - `Avoidance.lua`: one detector on `UNIT_COMBAT`; publishes `WW_AVOIDANCE` and `WW_PLAYER_SPELL_MISSED`; debug lines for the check.
  - `RulePacks/WarriorDefault.lua`: battleShout, execute, overpower, autoAttack, chargeRange, interceptRange.
  - `Companion.lua`: event wiring. One 0.2s ticker, built as an `Adapter.After` chain, runs only in combat, with a hostile target, or while an alert shows. Suspends on restricted. Publishes `WW_ALERTS_UPDATED`, `WW_COMBAT_SUSPENDED` and `WW_COMBAT_ENABLED`.
- **UI/HUD/:** `HUD.lua` (lifecycle, movers, saving positions, `/ww unlock|lock|hud on|off|test`), `AlertStrip.lua`, `BigAlert.lua` (flash and sound per `alertStyle`), `Badges.lua` (including "Suspended"). Plain unnamed frames anchored to `UIParent`, created at login. `ns.Core:RegisterCommand` was added to `Init.lua`.
- **Simulator** (agreed with `warrior-companion-9c`):
  - `api.lua`: run 2 restriction and secret-value fakes. Secrets are newproxy userdata; the three misuses the simulator cannot catch are documented in the file.
  - `set_combat`: follows the recorded event order.
  - `scenarios/combat.json`, and 10 `WarriorWorkshopCombatTests`, including a `/ww test` snapshot with zero layout warnings.
  - The sim session added an overlap warning (42f326b). It caught a real 18px badge/strip overlap at the default positions, fixed in d4a0c9a without any saved-data change.
- **Docs:** `docs/verification/M5.md`; `DEV_SETUP.md` simulator notes.

## Verification state (pasted, not recalled)
```
CI run 38063578174 on 42f326b: conclusion success
luacheck:  Total: 0 warnings / 0 errors in 77 files
busted:    ok=316 not_ok=0 3 pending   (TAP counts the 3 pending planner/advisor/readiness placeholders as ok)
simulator: Ran 60 tests in 0.164s OK
local:     busted shim (lupa Lua 5.1) TOTAL ok=313 fail=0 pending=3; luacheck 1.2.0 under lupa: 0 warnings / 0 errors in 77 files; tools/tests Ran 4 OK
```
Local tooling: the busted shim and a luacheck-under-lupa runner live in the session scratchpad (not committed). CI's real busted and luacheck are authoritative and agreed with them throughout.

## Assumptions (logged here, not asked)
- **Badges:** the badge position marks the first badge; further badges stack below it, so the container is one row tall. This avoids a schema change for the placeholder defaults.
- **Throttles** (placeholders): 0.1s for Battle Shout, Execute and Overpower; 0.2s for the badges. `expiring` is 10s (`args.expiring`, overridable).
- **Dropped state:** Battle Shout "dropped" counts anyone's shout as present (`fromPlayer = false`). "Expiring" shows even out of combat with no target. "Dropped" needs combat or a hostile target.
- **S-04 range:** melee range is read through Heroic Strike (every warrior knows it from level 1).
- **Cooldowns in combat:** `cooldownReady` uses `isActive` when the times are secret. A spell on cooldown (including possibly the GCD) is then unknown, so hidden. Overpower may therefore blink off during the GCD.
- **Avoidance pairing:** the window is 0.5s [VERIFY V-16], and paired abilities are Taunt, Mocking Blow, Disarm, Intimidating Shout, Pummel and Shield Bash. The next target event settles the cast, hit or not.
- **Fixture correction:** `BLOCK_REDUCED` on a target WOUND **was observed** in run 2 (fight 1, t = 12.14). D-048 calls it ASSUMED; that applies only to the player-side BLOCK_REDUCED in `assumed_avoidance.lua`. Worth correcting in D-048's wording.
- **Restriction event:** `ADDON_RESTRICTION_STATE_CHANGED`'s second argument is read as an active flag (run 2 saw only `(0,1)` and `(0,0)`, while the state getter returned 2). Context ignores the arguments and asks the getter.
- **Unverified APIs:** `C_Spell.GetSpellName`, `C_Spell.GetSpellTexture`, `PlaySound`/`SOUNDKIT` and the fallback icon 134400 are unverified (each is guarded). A drag-saved position assumes the client anchors to UIParent with matching points [VERIFY in game; a debug line logs it otherwise].

## Deferred (in scope later or backlog)
- R-11 Interrupt and R-06 cooldown tracker: No-go (D-044). X-06 combat text frame: off the launch target (D-043); the detector is ready for it.
- The R-01 stance hint (backlog: a `recentAvoidance` condition would need a spec change, D-048 (4)).
- `targetCasting`, `hasShield` and `partyMissingAura` stay unknown until M6–M8 (D-048 (1)).
- A rule's disabled reasons only go to the debug log; the Alerts tab (M6) shows them.

## Open questions for Hugh
1. V-31 notes on the built-ins (Cooldown Manager, floating combat text, swing timer, loss-of-control). Still not blocking.
2. After the M5 check: are the alert sizes, positions, flash and sound usable as defaults?

## Next step
**Hugh runs `docs/verification/M5.md` in game** and pastes the results (debug lines from steps 2, 10, 16). Steps 13–14 need a character that knows Overpower (12+) or Execute (24+); otherwise mark them not testable yet. After that check, and with Hugh's approval, the next milestone is **M7 (announcer)** per D-031. Do not start M7 before then. The group run (`docs/BETA_TESTING.md` Stage 5) before 21 Oct would also confirm suspension on a boss and the avoidance names. Next decision number: **D-050** (ask the orchestrator).

## Other open items
- Carried: the `leafo/gh-actions-*` Node 20 deprecation and the `ubuntu-latest` move to Ubuntu 26 on 19 Oct 2026 (CI annotations).
- `sim-save/` (untracked, from an earlier simulator run) was left alone.
