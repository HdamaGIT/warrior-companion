# Probe results

**Status:** runs 1 (9 Oct) and 2 (10 Oct) done, solo, open world. Decision gate filled (provisional until run 3: group, dungeon, boss).
**Client build:** 1.60.1.70338 (9 Oct 2026; run 1 on 70291) **Interface:** 16001 **Client folder:** `_classic_beta_` **Date run:** 9 Oct 2026

Hugh runs the probe and pastes `WarriorWorkshopProbe.lua` from SavedVariables; Claude then fills in each section below. Every "Decision" either cites a `D-` entry in `docs/DECISIONS.md` or says "none needed". The step-by-step beta procedure is `docs/BETA_TESTING.md`.

Where to look in the dump: `static` = `/wwprobe`; `prof` = `/wwprobe prof`; `items` = `/wwprobe item`; `gear` = `/wwprobe gear`; `bags` = `/wwprobe bags`; `pings` = `/wwprobe ping`; `events` / `eventCounts` / `eventCountsByContext` / `registrations` = event recorder (unit-filtered events are keyed `EVENT@units`, e.g. `UNIT_SPELLCAST_SUCCEEDED@player`); `combat` = `/wwprobe combat` sampler (`byContext.<ctx>.fields.<key>` holds counts of readable / secret / isNil / unchecked / error / missing plus up to 5 example values; `transitions` holds usability changes); `cleu`; `unitCombat`; `nameplates`; `spells`; `trainer`; `tank`; `chat` (`attempts[*]` with `echoed` / `blocked`); `blocked`; `bindings`; `sets`; `swap`; `macro`; `handlerErrors` (probe bugs; should be empty). Contexts are `openWorld`, `instance` and `encounter`.

---

## Run 1 (9 October 2026, solo, open world only)

Collected with `python tools/wowdev.py collect` into `beta-results/2026-10-09_205020/` (git-ignored). Probe version 2, 6 sessions, characters Sphere (level 8) and Kagoroar (level 1), both warriors. No `handlerErrors`. Not yet captured: combat sampler (no samples; see below), chat, key binding, swap button, macro, tank, trainer, any group or instance context.

| Item | Result | Evidence |
|---|---|---|
| **V-01** | Interface **16001**, version 1.60.1, build 70291 (7 Oct 2026). Client folder `_classic_beta_` (product `wow_classic_beta`). | `static.buildInfo`; `/dump` by Hugh; D-005 |
| M0/M2 | Add-on loads, `/ww version` shows schema 2, debug setting persists across `/reload`, `meta` correct for both characters, no `_backup`. Context prints `openWorld, solo, restricted=false, combat=true` in combat. | collected `WarriorWorkshop.lua` files; Hugh |
| **V-10** | All secret APIs exist: `issecretvalue`, `issecrettable`, `canaccessvalue`, `canaccesstable`, `canaccessallvalues`, `hasanysecretvalues`, `scrubsecretvalues`. `C_Secrets` has 27 `Should*BeSecret` functions. | `static.secretApis`, `static.namespaces.C_Secrets` |
| **V-16** | **`CombatLogGetCurrentEventInfo` does not exist.** CLEU registered without error but never fired. CLEU is not usable by add-ons in this client. | `static.functions`, `eventCounts`, `cleu.seen = 0` |
| V-16 fallback | **`UNIT_COMBAT` works in open-world combat** for `player` and `target`: action (`WOUND`, `MISS`), flag text (`CRITICAL`, `GLANCING`), amount; all **non-secret**, including while the combat restriction is active. No DODGE/PARRY/BLOCK seen yet (only 2 fights). | `events` UNIT_COMBAT@player,target, `unitCombat` |
| **V-21** | `C_RestrictedActions` exists (`CheckAllowProtectedFunctions`, `GetAddOnRestrictionState`, `IsAddOnRestrictionActive`). `ADDON_RESTRICTION_STATE_CHANGED` fires with `(0, 1)` exactly at `PLAYER_REGEN_DISABLED` and `(0, 0)` at `PLAYER_REGEN_ENABLED`, **in the open world**. Restriction type 0 therefore tracks combat; what it restricts is not yet known (event arguments stayed readable). | `events`, `static.namespaces` |
| V-07 (open world) | Own `UNIT_SPELLCAST_SUCCEEDED` spellID readable during restricted combat (Charge 100, Rend 772). Encounters not tested. | `events` |
| **V-22** (partial) | Spell IDs are the Classic ones (Heroic Strike 78, Battle Stance 2457, Charge 100, Rend 772). `C_Spell.GetSpellInfo(name)` resolves only spells the character knows (level 1: Heroic Strike, Battle Stance) and not "Auto Attack". One stance at level 1. `LEARNED_SPELL_IN_TAB` is an **unknown event**; `LEARNED_SPELL_IN_SKILL_LINE` registers. | `spells`, `registrations` |
| **V-05 / V-27** (out of combat) | `C_EquipmentSet` complete (23 functions); `UseEquipmentSet` works out of combat (applied set "test2", which had 0 items saved, so 4 slots were emptied, which is correct). **Set IDs start at 0.** | `sets` |
| V-19 (out of combat) | Nameplate level, classification, reaction, canAttack readable; threat `nil` out of combat. | `nameplates` |
| V-31 (partial) | `C_CooldownViewer` (7 functions) and `C_DamageMeter` (8) exist: Blizzard's Cooldown Manager and damage meter are present. | `static.namespaces` |
| V-04 note | Global `GetItemStats` is missing; `C_Item.GetItemStats` exists. `GetNumSpellTabs`/`GetSpellTabInfo` and `UnitDefense` are missing. | `static.functions` |
| Extras | Weapon skills exist (`CHAT_MSG_SKILL`: "Your skill in Two-Handed Axes has increased to 2"). Classic-only container/tradeskill globals are absent (Mainline API confirmed). | `events`, `static.classicGlobals` |

**Problems found in the probe (fixed in probe version 3):**
- The "blocked from an action only available to the Blizzard UI" popup was not recorded: the probe ignored every event before `PLAYER_LOGIN`. Version 3 keeps them in `earlyEvents`. The likely cause is the probe registering `COMBAT_LOG_EVENT_UNFILTERED`; version 3 skips that registration when `CombatLogGetCurrentEventInfo` is missing. **Confirm:** the popup should no longer appear at login.
- The combat sampler took no samples although it was switched on. Either it was turned on after the two fights, or the ticker did not start (version 3 records whether `C_Timer.NewTicker` exists). Re-run Stage 4.
- Version 3 also samples `C_RestrictedActions` states 0–5 and ten `C_Secrets.Should*BeSecret` answers in combat, and dumps any `Enum.*Restriction*`/`*Secret*` enums.

## Run 2 (10 October 2026, solo, open world)

Collected into `beta-results/2026-10-10_154007/`. Probe version 3, character Sphere (level 8). Client updated to **build 70338** (9 Oct; Interface still 16001). No handler errors, no Lua errors, **no popup at login** (the CLEU fix worked; the only pre-login events were `UPDATE_INVENTORY_DURABILITY` and `SKILL_LINES_CHANGED`). 9 fights, **893 sampler samples** (464 in combat, 429 out of combat with a hostile target).

**Headline:** in Forever, open-world combat switches on restriction type 0 ("Combat"). While it is active, **auras, cooldown times, rage, player and target health and target casting are secret** (or the call errors). What stays readable in combat: spell usability, range, current spell (auto-attack), stance, target level/classification/reaction/attackable, threat situation, own `UNIT_SPELLCAST_*` events and `UNIT_COMBAT`. Rage and health were secret even **out of** combat whenever the sampler ran. Details per item below, gate at the end.

| Item | Result |
|---|---|
| V-21 | Restriction enums found: types Combat 0, Encounter 1, ChallengeMode 2, PvPMatch 3, Map 4, Chat 5; state 2 = Active during every fight. |
| V-15 | Auras: readable out of combat; `nil` by name and an **error** by index in combat. |
| V-11/V-12 | Target health and player rage: secret always. |
| V-13 | Cooldown times secret in combat; `isActive` readable. |
| V-14/V-18/V-23 | Usability, range and auto-attack (`IsCurrentSpell(6603)`) readable in combat. |
| V-16 | `UNIT_COMBAT` readable in combat; PARRY and MISS seen both ways. |
| V-25 | SAY by key press sends; SAY/YELL from a timer blocked outdoors. |
| V-27/V-28 | Sets refused in combat (blocked); secure weapon swap **works in combat**; key-down fires two clicks. |
| V-29/V-30 | Macros work; binding persists across relog. |

## V-01 Interface number and client folder
- **Result:** 16001; `_classic_beta_` (run 1).
- **Evidence:** `static.buildInfo.returns[4]`; folder name from Hugh.
- **Decision:** D-005. Update `## Interface:` in both `.toc` files.

## V-02 `C_TradeSkillUI` functions and recipe info fields
- **Result:**
- **Evidence:** `static.functions["C_TradeSkillUI.*"]`, `static.namespaces.C_TradeSkillUI`, `prof.recipes[1..n].info / schematic / outputItemData`, `prof.allRecipesCompact` (look for the difficulty field and its values, learned flags, output item and reagents).
- **Decision:**

## V-03 Craft completion and skill-up signals
- **Result:**
- **Evidence:** `registrations` for `TRADE_SKILL_ITEM_CRAFTED_RESULT` and the other candidates; event order in `events` around a craft (`UNIT_SPELLCAST_START` → `SUCCEEDED` → `BAG_UPDATE_DELAYED` → `SKILL_LINES_CHANGED` / `CHAT_MSG_SKILL`).
- **Decision:**

## V-04 `C_Item.GetItemStats` keys
- **Result:**
- **Evidence:** `items[*].statsCItem` / `statsGlobal`, `gear.slots[*].item.statsCItem`. List every `ITEM_MOD_*` key seen.
- **Decision:** mapping to the SPEC 5.4 internal keys.

## V-05 `C_EquipmentSet`
- **Result:**
- **Evidence:** `static.functions["C_EquipmentSet.*"]`, `gear.sets`.
- **Decision:**

## V-06 `ENCOUNTER_START` / `ENCOUNTER_END` for add-ons
- **Result:**
- **Evidence:** `registrations.ENCOUNTER_START`, entries in `events` with those names; arg types and secret flags.
- **Decision:**

## V-07 `UNIT_SPELLCAST_SUCCEEDED` (player) during an encounter
- **Result:**
- **Evidence:** `events` entries with `inEncounter = true`; arg 3 (spellID) `secret` flag and `value`. Event key is `UNIT_SPELLCAST_SUCCEEDED@player`.
- **Decision:**

## V-08 Add-on message delivery during an encounter
- **Result:**
- **Evidence:** `pings[*]` with `inEncounter = true` (send return values) on the sender; `CHAT_MSG_ADDON` entries on the **receiver's** dump with `inEncounter = true`.
- **Decision:**

## V-09 Tagged party/raid chat during an encounter
- **Result:**
- **Evidence:** `CHAT_MSG_PARTY*` / `RAID*` / `INSTANCE_CHAT*` entries with `inEncounter = true` on the receiver; arg 1 (text) `secret` flag and `value`.
- **Decision:**

## V-10 Secret-value API and which values are secret where
- **Result:** Run 2: during open-world combat the client marks many values secret; `C_Secrets.Should*BeSecret` answers match what the sampler saw, so it is a usable predictor (auras and cooldowns flip `false`→`true` at combat start; unit power, target health and target casting are `true` throughout). Event payloads were never secret.
- **Evidence:** `static.secretApis`; across `events`, the arg `secret` values (`true`/`false`/`nochecker`) split by `inEncounter`.
- **Decision:** Secret checks per field (D-036) plus a `C_Secrets` pre-check before aura calls (D-045).

## M3 additions (probe version 2)

V-20 (XP events) is retired with the analytics scope (D-022).

### V-11 Open world: target health readable
- **Result:** **Secret always** (893/893 samples: in and out of combat, with a hostile target). `targetHealth`, `Max` and `Percent` all secret. `C_Secrets.ShouldUnitHealthMaxBeSecret("target")` = `true`.
- **Evidence:** `combat.byContext.openWorld.fields` → `targetHealth`, `targetHealthMax`, `targetHealthPercent` (readable vs secret counts, examples); compare with `instance` and `encounter`.
- **Used by:** R-03 Execute
- **Decision:** No health-based conditions. R-03 Execute uses `IsSpellUsable` only (D-044).

### V-12 Open world: player rage readable
- **Result:** **Secret always** (893/893). `rageMax` readable (100). `ShouldUnitPowerBeSecret("player")` = `true`.
- **Evidence:** `combat.byContext.*.fields.rage`, `rageMax`.
- **Used by:** rage conditions
- **Decision:** No rage conditions; usability (`IsSpellUsable`) already includes rage (Heroic Strike flips usable).

### V-13 Open world: own spell cooldowns readable
- **Result:** Out of combat readable. **In combat `startTime`, `duration`, `modRate` are secret**; `isActive`, `isEnabled` stay readable. `gcd` returned `nil` throughout.
- **Evidence:** `combat.byContext.*.fields["cd:<ability>.startTime" / ".duration"]` and `gcd.*`.
- **Used by:** R-06, `cooldownReady`
- **Decision:** Cooldown timers: No-go in combat. "Ready / not ready" via `isActive` is readable (Degraded).

### V-14 `C_Spell.IsSpellUsable` reflects Overpower/Revenge/Execute windows
- **Result:** `IsSpellUsable` readable in combat (893/893) and changes with state (Heroic Strike `true`/`false`, Charge). Overpower, Revenge and Execute are **not yet known** by the level 8 test character, so their windows are untested.
- **Evidence:** `combat.transitions` (`usable:Overpower` etc.) lined up against dodges in `cleu.events` / `unitCombat` and target health; `fields["usable:*"]`.
- **Used by:** R-01, R-02, R-03
- **Decision:** Go on the evidence, re-check when a character knows Overpower (level 12) and Execute.

### V-15 Player and target auras readable with duration/expiry and source
- **Result:** Out of combat readable with all fields (Battle Shout: duration 180, expirationTime, sourceUnit `player`, spellId 6673). **In combat:** `GetAuraDataBySpellName` returns `nil` (indistinguishable from "aura missing"); `GetAuraDataByIndex` **raises an error**: "Auras cannot be accessed when secret while tainted". `ShouldAurasBeSecret()` = `true` in combat.
- **Evidence:** `fields["aura:player:Battle Shout.*"]`, `aura:target:<debuff>.*` (`expirationTime`, `duration`, `applications`, `sourceUnit`, `isFromPlayerOrPlayerPet`), `aura:*:index1.*`.
- **Used by:** U-01, U-05, U-06, U-07, U-04
- **Decision:** Aura reads in combat: No-go. Upkeep alerts use own casts plus durations learned out of combat (D-044).

### V-16 Open world: CLEU fires; fields readable; miss types present
- **Result:** CLEU unavailable (run 1). **`UNIT_COMBAT` works in combat**, payload never secret: `player` = attacks on you (`PARRY` 3, `MISS` 2, `WOUND` 46), `target` = your attacks (`PARRY` 1, `MISS` 1, `WOUND` 60). No DODGE/BLOCK/RESIST seen yet; no attacker identity on `player` events.
- **Evidence:** `registrations.COMBAT_LOG_EVENT_UNFILTERED`, `cleu.seen`, `cleu.noInfoFunction`, `cleu.subevents.<ctx>`, `cleu.missTypes.<ctx>` (DODGE, PARRY, BLOCK, RESIST, IMMUNE), `cleu.events[*].args`. Fallback: `unitCombat.<ctx>` (`player:DODGE`, `target:RESIST` …).
- **Used by:** Avoidance detector, X-06, A-01, A-02, A-05, A-07
- **Decision:** Avoidance detector built on `UNIT_COMBAT` (D-035); Degraded: no source name.

### V-17 Target casting info including not-interruptible flag
- **Result:** `UnitCastingInfo("target")` `nil` in all samples and `ShouldUnitSpellCastingBeSecret("target")` = `true` throughout. Target `UNIT_SPELLCAST_*` events are registered (all OK) but **none fired**: either no mob cast during the fights or the events are withheld.
- **Evidence:** `fields.targetCasting` and `targetCasting#1..#9` (#8 = notInterruptible, #9 = spellID); `UNIT_SPELLCAST_*@target` events.
- **Used by:** R-11 Interrupt
- **Decision:** R-11 Interrupt: No-go for launch unless run 3 (fight a caster on purpose) shows target cast events with readable payloads (D-044).

### V-18 `C_Spell.IsSpellInRange` for Charge/Intercept
- **Result:** `IsSpellInRange` readable in combat for Charge (`true`/`false`) and Heroic Strike; `nil` with no target. Intercept/Pummel/Taunt not known yet.
- **Evidence:** `fields["range:Charge"]`, `range:Intercept`, `range:Pummel`, `range:Heroic Strike`.
- **Used by:** X-01, S-04
- **Decision:** Go.

### V-19 Nameplate units expose level/classification/reaction/threat
- **Result:** Run 1: nameplate level/classification/reaction readable. Run 2: `targetLevel`, `targetClassification`, `targetReaction`, `targetCanAttack` readable in combat; `threatSituation` readable (0, 3).
- **Evidence:** `nameplates[*]`, `UNIT_THREAT_LIST_UPDATE@target` events, `fields.threatSituation`.
- **Used by:** T-02 (backlog)
- **Decision:** Go.

### V-21 A direct "restricted context" signal exists
- **Result:** **Yes.** `Enum.AddOnRestrictionType` = Combat 0, Encounter 1, ChallengeMode 2, PvPMatch 3, Map 4, Chat 5; `Enum.AddOnRestrictionState` = Inactive 0, Activating 1, Active 2. `GetAddOnRestrictionState(0)` = 2 and `IsAddOnRestrictionActive(0)` = `true` in every open-world fight; types 1–5 stayed 0. `C_Secrets.HasSecretRestrictions()` = `true`. Also `Enum.ScriptObjectAccessRestriction.DenyTaintedAccessWhenAurasAreSecret`.
- **Evidence:** `static.namespaces.C_RestrictedActions` / `C_Secrets`, `static.functions["C_RestrictedActions.*"]`, `registrations.ADDON_RESTRICTION_STATE_CHANGED` (all candidate names), `fields.encounterInProgress`, `fields.challengeModeActive`.
- **Used by:** Context (D-033)
- **Decision:** `restricted` = Encounter, ChallengeMode or PvPMatch active (plus the existing signals); Combat is normal (D-045).

### V-22 Forever warrior kit: names, IDs, stances
- **Result:** Classic kit with ranks (trainer: "Heroic Strike Rank 2", "Rend Rank 2"). Level 8 knows Battle Shout, Battle Stance, Charge, Heroic Strike, Rend, Thunder Clap (+ Hamstring learned 10 Oct, ID 1715). One stance (`GetShapeshiftFormID` = 17). `LEARNED_SPELL_IN_SKILL_LINE` fires on learning.
- **Evidence:** `spells.named[<name>]` (resolved or not), `spells.items`, `spells.stances.forms`, `LEARNED_SPELL_IN_TAB` vs `LEARNED_SPELL_IN_SKILL_LINE` registrations.
- **Used by:** Rule packs, announcer, macros
- **Decision:** Go; SpellMap by name.

### V-23 `C_Spell.IsCurrentSpell` readable (auto-attack)
- **Result:** `IsCurrentSpell(6603)` (Auto Attack by ID) readable in combat, `true`/`false`. By name "Auto Attack" stays `false` (name does not resolve). `PLAYER_ENTER/LEAVE_COMBAT` fire (12 each).
- **Evidence:** `fields["current:6603"]`, `current:Auto Attack`, `PLAYER_ENTER_COMBAT` / `PLAYER_LEAVE_COMBAT` events.
- **Used by:** S-04
- **Decision:** Go, using spell ID 6603 or the events.

### V-24 `TRAINER_SHOW` exposes services with level requirements
- **Result:** `TRAINER_SHOW` dump: 96 services with name, status, icon, level requirement, rank and cost.
- **Evidence:** `trainer[*].services[*]` (`info`, `levelReq`, `cost`).
- **Used by:** Q-03 (backlog)
- **Decision:** Go.

### V-25 Chat from an event handler (no key press)
- **Result:** Outdoors: SAY/YELL from a **timer** → `ADDON_ACTION_BLOCKED` (`UNKNOWN()`), no echo. SAY from a **key binding** → sent (echo in ~0.33s). PARTY/RAID/INSTANCE_CHAT not tested (solo).
- **Evidence:** `chat.attempts[*]` with `trigger = "timer"` per `channel` and `ctx`: `echoed` (sent) vs `blocked` (`ADDON_ACTION_BLOCKED:<func>`); `trigger = "key"` for SAY from the key binding; `blocked[*]`.
- **Used by:** Announcer routing (D-024)
- **Decision:** D-024 confirmed outdoors. Group channels: run 3.

### V-26 Chat sending during a boss encounter
- **Result:**
- **Evidence:** `chat.attempts[*]` with `ctx = "encounter"`; `chat.unreadableEchoes.encounter`; the second player's dump.
- **Used by:** Announcer suspend rules (D-021)
- **Decision:**

### V-27 `C_EquipmentSet.UseEquipmentSet` out of and in combat
- **Result:** Out of combat: works (set applied, slots match). **In combat: returns `false` and fires `ADDON_ACTION_BLOCKED`**; armour unchanged (Hugh).
- **Evidence:** `sets.attempts[*]` (`inCombat`, `result`, `matched` / `total`, `before` / `after`).
- **Used by:** G-01, G-02 (D-025)
- **Decision:** Go with the queue (D-025); never call it in combat (D-041).

### V-28 Secure `/equipslot` button bound with `SetBindingClick` swaps weapons in combat
- **Result:** **Works.** Secure button, `macrotext` `/equip item:12282`, bound to CTRL-SHIFT-F9 via `SetBindingClick`: in combat the main hand changed 5956 → 12282 (Hugh confirmed). `ActionButtonUseKeyDown` = 1; with `AnyDown`+`AnyUp` registered, **each key press fires two clicks** (down and up).
- **Evidence:** `swap.setup` (`create`, `bind`, `keyDownCVar`), `swap.clicks[*]` (`inCombat`, `before` / `after` weapons); `blocked`.
- **Used by:** G-03
- **Decision:** Go. Register only the edge that matches the CVar, or toggles would swap twice (D-046).

### V-29 `CreateMacro`/`EditMacro` work; slot limits
- **Result:** Create, edit and delete all work (macro slot 121, character macro). Account 1, character 0 before.
- **Evidence:** `macro` (`create`, `edit`, `delete`, `counts*`, `maxAccount`, `maxCharacter`).
- **Used by:** X-07
- **Decision:** Go.

### V-30 Bindings declared in `Bindings.xml` appear in Key Bindings and persist
- **Result:** The probe binding appears under AddOns in Key Bindings; CTRL-SHIFT-F10 stayed bound across a relog (`GetBindingKey` at login). The key press sent SAY.
- **Evidence:** Hugh: the binding is listed under AddOns → Warrior Workshop Probe. `bindings.checks[*]` (one per login and per `/wwprobe chatkey`) still shows the key after a relog; `bindings.pressed`.
- **Used by:** G-01 keybinds (D-040)
- **Decision:** Go (D-040).

### V-31 Built-ins: Cooldown Manager, swing timer, floating combat text, loss-of-control
- **Result:**
- **Evidence:** Manual notes from Hugh (script step 6); `static.namespaces.C_CooldownViewer` / `C_DamageMeter`.
- **Used by:** R-06 (D-028), X-06, X-04, D-023
- **Decision:**

### V-32 Party auras and `UnitInRange` readable
- **Result:** `UnitInRange("partyN")` returns secret values even with no party (893/893). Party auras `nil` (no party). Untested in a real group.
- **Evidence:** `fields["aura:party1:Battle Shout.*"]`, `inRange:party1..4`, `exists:party1..4`, split by context.
- **Used by:** U-02
- **Decision:** Run 3; plan U-02 as out-of-combat only.

### V-33 Tank stat APIs
- **Result:** All readable out of combat: dodge 4.36, parry 4.96, block 4.96, armour 342, crit 5.4, stats, attack power. `UnitDefense` missing; `CR_DEFENSE_SKILL` (index 2) exists via `GetCombatRating`. `ShouldUnitStatsBeSecret` flips `true` in combat.
- **Evidence:** `tank.calls.*` (`dodge`, `parry`, `block`, `shieldBlock`, `armor`, `defense`, …), `tank.ratings.CR_*`; compare with the character pane.
- **Used by:** Tank stat sheet (M13)
- **Decision:** Go (out of combat only).

## Extras (for later milestones)
- **Bank layout (M3):** `static.bagIndex`, `bags.containers` with the bank open; whether `PLAYERBANKSLOTS_CHANGED` / `BANKFRAME_OPENED` registered and fired.
- **Classic globals present?** `static.classicGlobals`.
- **Failed event registrations:** every non-`true` entry in `registrations`.

---

## Encounter test script (two players)

**You need:** Hugh plus a second player, both with **WarriorWorkshopProbe** enabled; a normal dungeon with an easy first boss; `/console scriptErrors 1` on both clients.

**Before the dungeon (both players)**
1. `/reload` to start a clean session, then `/wwprobe clear`, then `/wwprobe`. The summary prints, with `issecretvalue` reported as present or absent.
2. Form a party. Hugh types `/wwprobe ping`. **Expected:** both clients log the add-on message and the `[WW:PING:n]` party line (a baseline outside any encounter). The second player's chat shows the `[WW:PING:n]` line.

**Entering the dungeon**
3. If you queued through group finder, the channel becomes `INSTANCE_CHAT`; the probe picks it automatically. Note how you entered: ______.
4. Clear trash to the first boss. Don't pull yet.

**Boss fight**
5. Pull the boss. Within the first 10 seconds Hugh casts a known ability (for example **Heroic Strike** or **Battle Shout**) and notes the time.
6. Mid-fight, Hugh types `/wwprobe ping`. Then the **second player** types `/wwprobe ping`.
7. Hugh casts the same ability once more.
8. Kill the boss (or wipe; either is fine, just note which): ______.

**After the fight (both players)**
9. Each player types `/wwprobe ping` once more (a post-encounter baseline).
10. Both players `/reload`, which writes SavedVariables to disk.
11. Both players send their `WTF\Account\<ACCOUNT>\SavedVariables\WarriorWorkshopProbe.lua`. Hugh pastes his into the session; the second player's file goes to Hugh by any means (Discord, e-mail).

**Optional: raid**
12. If a raid group is available, repeat steps 5 to 10 there, because restrictions may differ between dungeon and raid bosses.

## Solo checks (any time, Hugh only)
- `/wwprobe` → static summary.
- Open **Blacksmithing**, then `/wwprobe prof`. Also open **Mining** and repeat (the second run overwrites; paste after each if you want both).
- `/wwprobe gear` while wearing your normal gear; if you have an equipment set, keep it saved.
- `/wwprobe item` + shift-click a crafted Blacksmithing item, and another with defensive stats if you have one.
- At the bank: `/wwprobe bags`.
- Craft three or more items at the anvil, ideally including one that gives a skill-up. The recorder captures the event sequence.
- Not in a group: `/wwprobe ping` whispers the add-on message to yourself (checks the plumbing only).

---

## Decision gate (SPEC_V2 §12.2)

Fill in after the run. Each Phase B–D feature is **Go**, **Degraded** (state the fallback) or **No-go**, and the outcome is recorded in `docs/DECISIONS.md` before it is built.

| Feature | Depends on | Gate | Fallback / note |
|---|---|---|---|
| U-01 Battle Shout | V-15 | **Degraded** | Aura unreadable in combat. Track own Battle Shout casts (`UNIT_SPELLCAST_SUCCEEDED`, readable) with the duration read out of combat; read the real aura whenever not secret. "Dropped" in combat only when the timer runs out (misses dispels and other warriors' shouts). |
| R-03 Execute | V-11, V-14 | **Degraded** | Target health secret; use `IsSpellUsable(Execute)` alone. Untested until a character knows Execute. |
| R-01 Overpower | V-14 | **Go** (provisional) | `IsSpellUsable` readable in combat; Overpower window untested (needs level 12). |
| R-11 Interrupt | V-17, V-13 | **No-go** for launch | Target casting secret. Revisit if run 3 shows target `UNIT_SPELLCAST_START` events (fight a caster on purpose). |
| S-04 Auto-attack | V-23, V-18 | **Go** | `IsCurrentSpell(6603)` and range readable in combat. |
| X-01 Charge range | V-18, V-13 | **Go** | Range, usability and cooldown `isActive` readable. |
| X-06 Combat text / avoidance detector | V-16 (or `UNIT_COMBAT`), V-31 | **Degraded** | Detector on `UNIT_COMBAT` (no attacker name). X-06 itself off the launch target (D-043); V-31 notes still needed. |
| R-06 Cooldown tracker | V-13, V-31 | **No-go** | Cooldown times secret in combat; Blizzard's Cooldown Manager exists (`C_CooldownViewer`). |
| U-02 BS party coverage | V-32 | **Degraded** (provisional) | Out-of-combat check only (pre-pull). Confirm in run 3. |
| Context `restricted` | V-06, V-21 | **Go** | Restriction types 1–3 (Encounter, ChallengeMode, PvPMatch) active → restricted; type 0 (Combat) is normal (D-045). |
| A-01..A-08 Announcer | V-16, V-25, V-26 | **Degraded** | A-01 via `UNIT_COMBAT` (no attacker name: "Parried!"); A-03, A-04, A-07 cast messages Go (own casts readable); A-04 expiry from cast time + known duration; A-02 taunt resist and A-05 need run 3; **A-08 low health No-go** (health secret). SAY/YELL outdoors fall back (confirmed); party channels: run 3. |
| G-01/G-02 Set keys and queue | V-27, V-30 | **Go** | Sets work out of combat; in combat refused and blocked, so queue (D-025). Bindings.xml bindings persist. |
| G-03 Weapon swap | V-28 | **Go** | Secure button swapped weapons in combat; one click edge only (D-046). |
| X-07 Macro generator | V-29, V-22 | **Go** | Create/edit/delete work; Classic stances (one at level 8). |
| Tank stat sheet | V-33 | **Go** | Out of combat; defence via `CR_DEFENSE_SKILL` (no `UnitDefense`). |

## Beta run script

Follow **`docs/BETA_TESTING.md`**: it covers the M0, M1, M2 and M3 checks in stages, each with a pass check, and ends with `python tools/wowdev.py collect` (no pasting needed). The SPEC_V2 test script it implements is kept below for reference.

**SPEC_V2 §12.2 test script (as specified)**
1. Open world: `/wwprobe combat` on; fight 5 mobs incl. one caster; Charge, interrupt, let dodges/parries/blocks happen; use Battle Shout and let it expire.
2. In a party with a second player: Taunt a mob until a resist (or log several taunts); use Challenging Shout and Shield Wall; `/wwprobe chat` in open world, then on dungeon trash, then on a boss.
3. Equipment sets: create two sets; `/wwprobe sets` out of and in combat; `/wwprobe swapbtn` and press the key mid-fight.
4. `/wwprobe macro`, `/wwprobe spells`, `/wwprobe tank`; trainer visit with `/wwprobe trainer`.
5. Check Key Bindings for the test binding; relog; check again.
6. Note the built-ins (V-31).
