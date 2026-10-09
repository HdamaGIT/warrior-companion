# Probe results

**Status:** template, not yet run. Probe version 2 (M1 + M3).
**Client build:** ______ **Interface:** ______ **Client folder:** ______ **Date run:** ______

Hugh runs the probe and pastes `WarriorWorkshopProbe.lua` from SavedVariables; Claude then fills in each section below. Every "Decision" either cites a `D-` entry in `docs/DECISIONS.md` or says "none needed". The beta run script is at the end of this file.

Where to look in the dump: `static` = `/wwprobe`; `prof` = `/wwprobe prof`; `items` = `/wwprobe item`; `gear` = `/wwprobe gear`; `bags` = `/wwprobe bags`; `pings` = `/wwprobe ping`; `events` / `eventCounts` / `eventCountsByContext` / `registrations` = event recorder (unit-filtered events are keyed `EVENT@units`, e.g. `UNIT_SPELLCAST_SUCCEEDED@player`); `combat` = `/wwprobe combat` sampler (`byContext.<ctx>.fields.<key>` holds counts of readable / secret / isNil / unchecked / error / missing plus up to 5 example values; `transitions` holds usability changes); `cleu`; `unitCombat`; `nameplates`; `spells`; `trainer`; `tank`; `chat` (`attempts[*]` with `echoed` / `blocked`); `blocked`; `bindings`; `sets`; `swap`; `macro`; `handlerErrors` (probe bugs; should be empty). Contexts are `openWorld`, `instance` and `encounter`.

---

## V-01 Interface number and client folder
- **Result:**
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
- **Result:**
- **Evidence:** `static.secretApis`; across `events`, the arg `secret` values (`true`/`false`/`nochecker`) split by `inEncounter`.
- **Decision:**

## M3 additions (probe version 2)

V-20 (XP events) is retired with the analytics scope (D-022).

### V-11 Open world: target health readable
- **Result:**
- **Evidence:** `combat.byContext.openWorld.fields` → `targetHealth`, `targetHealthMax`, `targetHealthPercent` (readable vs secret counts, examples); compare with `instance` and `encounter`.
- **Used by:** R-03 Execute
- **Decision:**

### V-12 Open world: player rage readable
- **Result:**
- **Evidence:** `combat.byContext.*.fields.rage`, `rageMax`.
- **Used by:** rage conditions
- **Decision:**

### V-13 Open world: own spell cooldowns readable
- **Result:**
- **Evidence:** `combat.byContext.*.fields["cd:<ability>.startTime" / ".duration"]` and `gcd.*`.
- **Used by:** R-06, `cooldownReady`
- **Decision:**

### V-14 `C_Spell.IsSpellUsable` reflects Overpower/Revenge/Execute windows
- **Result:**
- **Evidence:** `combat.transitions` (`usable:Overpower` etc.) lined up against dodges in `cleu.events` / `unitCombat` and target health; `fields["usable:*"]`.
- **Used by:** R-01, R-02, R-03
- **Decision:**

### V-15 Player and target auras readable with duration/expiry and source
- **Result:**
- **Evidence:** `fields["aura:player:Battle Shout.*"]`, `aura:target:<debuff>.*` (`expirationTime`, `duration`, `applications`, `sourceUnit`, `isFromPlayerOrPlayerPet`), `aura:*:index1.*`.
- **Used by:** U-01, U-05, U-06, U-07, U-04
- **Decision:**

### V-16 Open world: CLEU fires; fields readable; miss types present
- **Result:**
- **Evidence:** `registrations.COMBAT_LOG_EVENT_UNFILTERED`, `cleu.seen`, `cleu.noInfoFunction`, `cleu.subevents.<ctx>`, `cleu.missTypes.<ctx>` (DODGE, PARRY, BLOCK, RESIST, IMMUNE), `cleu.events[*].args`. Fallback: `unitCombat.<ctx>` (`player:DODGE`, `target:RESIST` …).
- **Used by:** Avoidance detector, X-06, A-01, A-02, A-05, A-07
- **Decision:**

### V-17 Target casting info including not-interruptible flag
- **Result:**
- **Evidence:** `fields.targetCasting` and `targetCasting#1..#9` (#8 = notInterruptible, #9 = spellID); `UNIT_SPELLCAST_*@target` events.
- **Used by:** R-11 Interrupt
- **Decision:**

### V-18 `C_Spell.IsSpellInRange` for Charge/Intercept
- **Result:**
- **Evidence:** `fields["range:Charge"]`, `range:Intercept`, `range:Pummel`, `range:Heroic Strike`.
- **Used by:** X-01, S-04
- **Decision:**

### V-19 Nameplate units expose level/classification/reaction/threat
- **Result:**
- **Evidence:** `nameplates[*]`, `UNIT_THREAT_LIST_UPDATE@target` events, `fields.threatSituation`.
- **Used by:** T-02 (backlog)
- **Decision:**

### V-21 A direct "restricted context" signal exists
- **Result:**
- **Evidence:** `static.namespaces.C_RestrictedActions` / `C_Secrets`, `static.functions["C_RestrictedActions.*"]`, `registrations.ADDON_RESTRICTION_STATE_CHANGED` (all candidate names), `fields.encounterInProgress`, `fields.challengeModeActive`.
- **Used by:** Context (D-033)
- **Decision:**

### V-22 Forever warrior kit: names, IDs, stances
- **Result:**
- **Evidence:** `spells.named[<name>]` (resolved or not), `spells.items`, `spells.stances.forms`, `LEARNED_SPELL_IN_TAB` vs `LEARNED_SPELL_IN_SKILL_LINE` registrations.
- **Used by:** Rule packs, announcer, macros
- **Decision:**

### V-23 `C_Spell.IsCurrentSpell` readable (auto-attack)
- **Result:**
- **Evidence:** `fields["current:6603"]`, `current:Auto Attack`, `PLAYER_ENTER_COMBAT` / `PLAYER_LEAVE_COMBAT` events.
- **Used by:** S-04
- **Decision:**

### V-24 `TRAINER_SHOW` exposes services with level requirements
- **Result:**
- **Evidence:** `trainer[*].services[*]` (`info`, `levelReq`, `cost`).
- **Used by:** Q-03 (backlog)
- **Decision:**

### V-25 Chat from an event handler (no key press)
- **Result:**
- **Evidence:** `chat.attempts[*]` with `trigger = "timer"` per `channel` and `ctx`: `echoed` (sent) vs `blocked` (`ADDON_ACTION_BLOCKED:<func>`); `trigger = "key"` for SAY from the key binding; `blocked[*]`.
- **Used by:** Announcer routing (D-024)
- **Decision:**

### V-26 Chat sending during a boss encounter
- **Result:**
- **Evidence:** `chat.attempts[*]` with `ctx = "encounter"`; `chat.unreadableEchoes.encounter`; the second player's dump.
- **Used by:** Announcer suspend rules (D-021)
- **Decision:**

### V-27 `C_EquipmentSet.UseEquipmentSet` out of and in combat
- **Result:**
- **Evidence:** `sets.attempts[*]` (`inCombat`, `result`, `matched` / `total`, `before` / `after`).
- **Used by:** G-01, G-02 (D-025)
- **Decision:**

### V-28 Secure `/equipslot` button bound with `SetBindingClick` swaps weapons in combat
- **Result:**
- **Evidence:** `swap.setup` (`create`, `bind`, `keyDownCVar`), `swap.clicks[*]` (`inCombat`, `before` / `after` weapons); `blocked`.
- **Used by:** G-03
- **Decision:**

### V-29 `CreateMacro`/`EditMacro` work; slot limits
- **Result:**
- **Evidence:** `macro` (`create`, `edit`, `delete`, `counts*`, `maxAccount`, `maxCharacter`).
- **Used by:** X-07
- **Decision:**

### V-30 Bindings declared in `Bindings.xml` appear in Key Bindings and persist
- **Result:**
- **Evidence:** Hugh: the binding is listed under AddOns → Warrior Workshop Probe. `bindings.checks[*]` (one per login and per `/wwprobe chatkey`) still shows the key after a relog; `bindings.pressed`.
- **Used by:** G-01 keybinds (P-5)
- **Decision:**

### V-31 Built-ins: Cooldown Manager, swing timer, floating combat text, loss-of-control
- **Result:**
- **Evidence:** Manual notes from Hugh (script step 6); `static.namespaces.C_CooldownViewer` / `C_DamageMeter`.
- **Used by:** R-06 (D-028), X-06, X-04, D-023
- **Decision:**

### V-32 Party auras and `UnitInRange` readable
- **Result:**
- **Evidence:** `fields["aura:party1:Battle Shout.*"]`, `inRange:party1..4`, `exists:party1..4`, split by context.
- **Used by:** U-02
- **Decision:**

### V-33 Tank stat APIs
- **Result:**
- **Evidence:** `tank.calls.*` (`dodge`, `parry`, `block`, `shieldBlock`, `armor`, `defense`, …), `tank.ratings.CR_*`; compare with the character pane.
- **Used by:** Tank stat sheet (M13)
- **Decision:**

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
| U-01 Battle Shout | V-15 | | |
| R-03 Execute | V-11, V-14 | | |
| R-01 Overpower | V-14 | | |
| R-11 Interrupt | V-17, V-13 | | |
| S-04 Auto-attack | V-23, V-18 | | |
| X-01 Charge range | V-18, V-13 | | |
| X-06 Combat text / avoidance detector | V-16 (or `UNIT_COMBAT`), V-31 | | |
| R-06 Cooldown tracker | V-13, V-31 | | |
| U-02 BS party coverage | V-32 | | |
| Context `restricted` | V-06, V-21 | | |
| A-01..A-08 Announcer | V-16, V-25, V-26 | | |
| G-01/G-02 Set keys and queue | V-27, V-30 | | |
| G-03 Weapon swap | V-28 | | |
| X-07 Macro generator | V-29, V-22 | | |
| Tank stat sheet | V-33 | | |

## Beta run script (M0, M1, M2 and M3 together; run before 21 October 2026)

SPEC_V2 §12.2 lists the M3 tests (reproduced at the end). Because nothing has run in Forever yet, this script also covers the M0, M1 and M2 checks, ordered so the most valuable results come first. **Parts A–C are the minimum viable run (about 45 minutes, solo).** If time runs out after Part C, do the "Finish" steps anyway.

**Before you start**
- Both add-ons installed (junctions per `docs/DEV_SETUP.md`): `WarriorWorkshop` and `WarriorWorkshopProbe`.
- `/console scriptErrors 1`, then `/reload`.
- In the character pane, create **two equipment sets** (e.g. "DPS" with a two-hander, "Tank" with one-hander + shield).
- Have both weapon setups in your bags (one equipped, the other in bags).
- Optional but useful: a second player with the probe installed, for Part D.

**Part A: load checks (5 min)**
1. Run `docs/verification/M0.md` and `docs/verification/M2.md`. Note any `API unavailable: ...` lines.
2. `/wwprobe clear`, then `/wwprobe`. Expected: version/interface line, API counts, `issecretvalue: function` or `nil`.

**Part B: solo, out of combat (10 min)**
3. `/wwprobe spells` (lists abilities that did not resolve by name), `/wwprobe tank` (then glance at the character pane: dodge, parry, block, armour), `/wwprobe macro` (expected: `create ok, edit ok, deleted`).
4. `/wwprobe sets`, then `/wwprobe sets 1`. Expected: "n of n slots now match the set".
5. Key binding (V-30, V-25): `/wwprobe chatkey`, then open Key Bindings → AddOns → Warrior Workshop Probe, bind **"Probe: SAY test line (key press)"** to a spare key, close, and press it **outdoors**. Expected: a `[WWPROBE test] … SAY key` line in /say.
6. `/wwprobe chat` **outdoors, solo**. Expected: SAY and YELL attempts reported, probably `no echo` + `ADDON_ACTION_BLOCKED` (that is the finding). Dismiss any "interface action failed" message.
7. Swap button (V-28): `/wwprobe swapbtn ` then shift-click the **bag** weapon(s) you want to swap *to* (main hand first, off hand second), Enter. Expected: "Swap button ready on CTRL-SHIFT-F9".
8. Visit a warrior trainer and open the window (the dump is automatic). Expected: "Trainer dump saved (auto)".

**Part C: solo, open-world combat (25 min)**
9. `/wwprobe combat on`.
10. Fight at least 5 mobs, including one caster: Charge in, let mobs dodge/parry/block you, use **Overpower** when it lights up, interrupt the caster (Pummel or Shield Bash), take one mob below 20% and use **Execute**, use **Battle Shout** and let it **expire** once, use Rend / Sunder Armor / Hamstring / Thunder Clap if you have them.
11. Mid-fight: press **Ctrl-Shift-F9** once (do the weapons change?), and type `/wwprobe sets 2` (does armour change in combat?).
12. After combat: `/wwprobe swapbtn restore`, then `/wwprobe status`. Expected: openWorld samples > 0, CLEU seen > 0 (or 0 = finding), handler errors 0.

**Part D: with a second player (45–60 min)**
13. Party in the open world: warn your partner, then `/wwprobe chat` (PARTY, SAY, YELL). Taunt mobs repeatedly (hoping for a resist); use Challenging Shout and Shield Wall.
14. Dungeon trash (sampler still on): `/wwprobe chat party` (or `instance_chat` if queued through group finder) and `/wwprobe ping`.
15. First boss: follow the **Encounter test script** above (steps 5–9), and also type `/wwprobe chat party` (or `instance_chat`) mid-fight. Note if any "interface action failed" message appears.

**Part E: relog and built-ins (10 min)**
16. Log out to character select and back in. `/wwprobe chatkey`. Expected: the key is still bound (V-30 persistence).
17. Note the built-ins (V-31) in a few words each: what the **Cooldown Manager** can show for warrior abilities (Edit Mode / settings); whether a **swing timer** exists and its options; **floating combat text** options for parry/dodge/block; whether a **loss-of-control** frame appears when stunned/feared.

**Part F: Workshop extras, if time (M1 solo checks)**
18. The "Solo checks" list above: `/wwprobe prof` with Blacksmithing and Mining open, `/wwprobe gear`, `/wwprobe item <link>`, `/wwprobe bags` at the bank, and three crafts.

**Finish**
19. `/wwprobe status`, then `/reload` (writes the file).
20. Send back:
    - `World of Warcraft\<client folder>\WTF\Account\<ACCOUNT>\SavedVariables\WarriorWorkshopProbe.lua` (and the second player's copy if Part D was done);
    - `...\WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\WarriorWorkshop.lua` (M2 check);
    - the client folder name, any Lua error text, any `API unavailable` lines, and your V-31 notes.

**SPEC_V2 §12.2 test script (as specified)**
1. Open world: `/wwprobe combat` on; fight 5 mobs incl. one caster; Charge, interrupt, let dodges/parries/blocks happen; use Battle Shout and let it expire.
2. In a party with a second player: Taunt a mob until a resist (or log several taunts); use Challenging Shout and Shield Wall; `/wwprobe chat` in open world, then on dungeon trash, then on a boss.
3. Equipment sets: create two sets; `/wwprobe sets` out of and in combat; `/wwprobe swapbtn` and press the key mid-fight.
4. `/wwprobe macro`, `/wwprobe spells`, `/wwprobe tank`; trainer visit with `/wwprobe trainer`.
5. Check Key Bindings for the test binding; relog; check again.
6. Note the built-ins (V-31).
