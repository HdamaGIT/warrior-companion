# Warrior Workshop — Ideas Backlog

| | |
|---|---|
| **Document** | `docs/IDEAS_BACKLOG.md` |
| **Date** | 9 October 2026 |
| **Purpose** | Long list of warrior features drawn from past and present add-ons and WeakAuras, for triage into the spec. Nothing here is in build scope until promoted into `SPEC.md` or `SPEC_LEVELLING.md` and logged in `DECISIONS.md`. |

## How to read this

**Feasibility tags**

| Tag | Meaning |
|---|---|
| `OOC` | Out of combat only — safe under any rules |
| `OW` | Needs readable open-world combat data — depends on L0 probe results |
| `ENC✗` | Blocked or degraded during boss encounters / Mythic+ (auto-suspend) |
| `PROT` | Uses a protected action — must be triggered by a keybind/click (secure button or macro), not automatically |
| `CHAT` | Sends chat — SAY/YELL outdoors needs a key press (hardware event); party/raid usually fine; blocked in encounters [VERIFY] |
| `BUILT-IN` | Blizzard ships something similar — check it in beta before building |
| `FOREVER?` | Depends on whether the ability/mechanic exists in Forever's warrior |

**Effort:** S (≤ 1 session) · M (2–3 sessions) · L (4+ sessions)

**Track:** L1–L4 (levelling spec) · **G** = new Gear-swap track · **A** = new Announcer track · **T** = future Dungeon/Tank track · **R** = v3 raid · **W** = Workshop (professions/gear, M4–M9) · **Later** / **Skip**

**Triage column:** fill in `Yes / Maybe / No` as we go through.

---

## A. Gear and weapon swapping (ItemRack, Outfitter, ClosetGnome, Equipment Manager)

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| G-01 | **Keybind per gear set** (e.g. Ctrl-1 DPS, Ctrl-2 Tank, Ctrl-3 Levelling) | ItemRack | `PROT` `OOC` for armour | M | G | 1 |
| G-02 | **Combat swap queue**: armour changes requested in combat are queued and applied the moment combat ends, with an on-screen "queued" badge | ItemRack | `OOC` | S | G | 2 |
| G-03 | **In-combat weapon-only swap**: 2H ↔ 1H+shield ↔ dual-wield via keybind (secure macro), the classic stance-dance tool | ItemRack, warrior macros | `PROT` (weapons allowed in combat [VERIFY]) | M | G | 2 |
| G-04 | **Stance-linked weapon sets**: Defensive Stance → shield set; Battle/Berserker → 2H, via a combined stance+weapon keybind macro | ItemRack events, stance macros | `PROT` `FOREVER?` | M | G | Pass |
| G-05 | **Event-driven sets**: auto-swap on mount/dismount, swimming, entering a city or rested area, entering an instance | ItemRack events, Outfitter | `OOC` | M | G | Pass |
| G-06 | **Profession set**: mining pick or gathering gear when targeting a node or opening a profession window | Outfitter | `OOC` `FOREVER?` | S | G | Pass |
| G-07 | **On-use trinket cycling**: when an equipped trinket goes on cooldown, swap in the next one out of combat | ItemRack trinket queue | `OOC` | M | G/Later | Pass |
| G-08 | **Set integrity check**: warns if a saved set references an item not in bags or bank | ItemRack | `OOC` | S | G | 3 |
| G-09 | **Quick-pick slot menu**: hover a character slot to choose from bag items for that slot | ItemRack | `OOC` `BUILT-IN` (Blizzard flyouts) | M | Skip | Skip |
| G-10 | **Resistance sets** (fire/nature/shadow) for specific raid bosses | Outfitter, ItemRack | `OOC` | S | R | 2 |
| G-11 | **Set-aware readiness**: Ready tab shows which set is worn and whether it matches the context (e.g. Tank set while in a dungeon group as tank) | Own | `OOC` | S | W | Pass |
| G-12 | **Weapon-swap rage-loss warning**: show rage that will be lost on a stance change (Tactical Mastery style) | Warrior WAs | `OW` `FOREVER?` | S | L1 | Pass |

---

## B. Announcements and chat (RSA / Raeli's Spell Announcer, tank announcer WAs)

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| A-01 | **Parry/dodge/block announce** — "Parried X's attack!" with per-channel choice (self, party, say), throttled | Classic tank announcer WAs | `OW` `CHAT` `ENC✗` | S | A | 1 |
| A-02 | **Taunt resisted announce** — "Taunt RESISTED on <mob>" to party/raid | Classic tank staple | `OW` `CHAT` `ENC✗` | S | A/T | 1 |
| A-03 | **Mocking Blow / Challenging Shout announce** with duration ("Challenging Shout — 6s, heal through!") | RSA | `OW` `CHAT` | S | A/T | 1 |
| A-04 | **Shield Wall / Last Stand used** + "ends in 3s" follow-up | RSA, tank WAs | `OW` `CHAT` | S | A/T | 1 |
| A-05 | **Interrupt announce** — success ("Pummel interrupted <spell>") and miss | RSA | `OW` `CHAT` `ENC✗` | S | A | 2 |
| A-06 | **Sunder counter** — "5 Sunders up on <boss>" for raid DPS | Classic raid WAs | `CHAT` `ENC✗` | S | R | 2 |
| A-07 | **Disarm / Intimidating Shout / fear announce** | RSA | `OW` `CHAT` | S | A | 1 |
| A-08 | **Low health call** — "Hugh at 20%!" to party (healer prompt), throttled | Tank WAs | `OW` `CHAT` | S | A/T | 2 |
| A-09 | **Death announce** with killing blow (fun, opt-in) | Fun WAs | `OW` `CHAT` | S | A | Pass |
| A-10 | **Pull announce** — "Pulling <mob> in 3" via keybind | DBM pull timer | `PROT` `CHAT` `BUILT-IN` (countdown) | S | T | 3 |
| A-11 | **Templates and variables** for all announcements (`%target`, `%spell`, `%time`), with channel per event and per context (solo/party/raid) | RSA | — | M | A | 3 |
| A-12 | **Local-only mode** — show announcements as big on-screen text instead of chat (no chat spam, no restrictions) | MSBT/SCT | `OW` | S | A | Pass |

---

## C. Buff and debuff upkeep — big signposting

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| U-01 | **Battle Shout — big alert**: large icon and countdown when ≤ 10s left; **flashing full-size icon + sound when dropped**; separate "never applied" state | Warrior WA packs | `OW` (aura readable) | S | L1 | 1 |
| U-02 | **Battle Shout party coverage**: count party members in range missing it | Raid-buff WAs | `OW` | M | T | 1 |
| U-03 | Demoralising Shout uptime on target / any engaged mob | Tank WAs | `OW` | S | L1 | 3 |
| U-04 | Thunder Clap uptime on engaged mobs | Tank WAs | `OW` `FOREVER?` | S | L1/T | 2 |
| U-05 | Sunder Armor stacks and refresh timer | Tank/raid WAs | `OW` | S | L1 | 2 |
| U-06 | Rend timer on target (only when target health > X%) | Arms WAs | `OW` | S | L1 | 2 |
| U-07 | Hamstring uptime (runners, PvP) | PvP WAs | `OW` | S | L1 | 2 |
| U-08 | Commanding Shout / other shouts if Forever adds them | Retail WAs | `OW` `FOREVER?` | S | L1 | Pass |
| U-09 | Enrage / Flurry uptime (Fury talents) | Fury WAs | `OW` `FOREVER?` | S | Later | Pass |
| U-10 | **Weapon enchant missing** (sharpening stone / weightstone / oils) | Consumable WAs | `OOC` | S | L4 | 3 |
| U-11 | Food buff / elixir missing before a pull or dungeon | Consumable WAs | `OOC` | S | L2 | Pass |
| U-12 | Group buffs missing (Fortitude, Mark of the Wild, Kings equivalents) | Raid-buff WAs | `OOC` | S | T | Pass |
| U-13 | **Defensive Stance without a shield** warning | Classic tank WA | `OOC`/`OW` | S | L1 | Pass |
| U-14 | **Wrong stance for role** (e.g. Battle Stance while tanking in a group) | Tank WAs | `OW` | S | T | Pass |
| U-15 | Configurable **"big alert" style**: icon size, screen-edge flash, sound per severity (expiring vs dropped) | WA packs | — | S | L1 | 1 (part of U-01) |

---

## D. Reactive abilities and cooldowns

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| R-01 | Overpower window (after dodge), with stance hint if not in Battle Stance | Warrior WAs | `OW` | S | L1 | 1 |
| R-02 | Revenge window | Tank WAs | `OW` | S | L1 | 2 |
| R-03 | Execute phase (target < 20%) with big glow | All warrior WAs | `OW` | S | L1 | 1 |
| R-04 | Victory Rush (if it exists) | Retail/TBC WAs | `OW` `FOREVER?` | S | L1 | Pass |
| R-05 | **Stance-dance helper**: shows which stance an available ability needs and the rage you'd lose | Classic WAs | `OW` `FOREVER?` | M | L1 | Pass |
| R-06 | Core cooldown tracker: Mortal Strike / Bloodthirst / Shield Slam / Whirlwind | WA packs | `OW` `BUILT-IN` (Cooldown Manager) | S | Check | 1 |
| R-07 | Big cooldown ready alerts: Recklessness, Death Wish, Shield Wall, Last Stand, Bloodrage | WA packs | `OW` `BUILT-IN` | S | Check | 3 |
| R-08 | **Bloodrage pre-pull prompt**: out of combat, target hostile, rage 0 → "Bloodrage then Charge" | Levelling WAs | `OOC` | S | L1 | 3 |
| R-09 | Heroic Strike queued indicator and **rage-dump** prompt | Swing WAs | `OW` | S | L1 | Pass |
| R-10 | **Rage starvation** warning: rage < cheapest key ability for > N seconds | Own | `OW` | S | L1 | Pass |
| R-11 | Interrupt available + target casting (with "worth interrupting" list: heals, fears) | Interrupt WAs | `OW` | S | L1 | 1 |
| R-12 | Spell Reflect prompt on hostile caster targeting you (if it exists) | PvP/tank WAs | `OW` `FOREVER?` | S | Later | Pass |
| R-13 | Shield Block uptime / crushing-blow window | Classic tank WAs | `OW` `FOREVER?` | S | T | Pass |

---

## E. Swing and auto-attack

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| S-01 | Main-hand / off-hand swing bars | WeaponSwingTimer, SP_SwingTimer, Quartz | `OW` (CLEU) | M | L1 | Pass |
| S-02 | **Slam window** marker on the swing bar (Arms/Fury Slam spec) | Classic slam WAs | `OW` `FOREVER?` | S | L1 | Pass (swing timer built in) |
| S-03 | Parry-haste indicator (your swing sped up by a parry) | Swing timers | `OW` | S | Later | Pass |
| S-04 | **Auto-attack not running** warning (e.g. after a Charge that didn't start attacking) | Levelling WAs | `OW` | S | L1 | 1 |
| S-05 | Next-swing ability label (HS/Cleave queued) on the bar | Swing timers | `OW` | S | L1 | Pass (swing timer built in) |

---

## F. Tanking (dungeons; open world groups)

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| T-01 | **Loose mob alert**: a mob in combat with your group not targeting you | Threat Plates, tank WAs | `OW` `ENC✗` | M | T | Pass |
| T-02 | Threat lead % on current target | Omen, KTM, ThreatClassic2 | `OW` `ENC✗` `BUILT-IN?` | M | T | 3 |
| T-03 | Nameplate threat colouring | TidyPlates ThreatPlates | `OW` `BUILT-IN` (nameplate threat colours) | M | Skip/Check | Skip |
| T-04 | **Healer-under-attack** alert | Tank WAs | `OW` `ENC✗` | S | T | Pass |
| T-05 | Tank stat sheet: avoidance, crushing-blow cap, effective health | TankPoints, "uncrushable" calculators | `OOC` `FOREVER?` | M | W | 1 |
| T-06 | Incoming damage per second (last 5s) bar | Tank WAs | `OW` | S | T | Pass |
| T-07 | Kill-order **raid marker helper** (auto-mark pull by priority) | MagicMarker | `OOC` (marking allowed) [VERIFY] | M | T | 3 |
| T-08 | Co-tank taunt cooldown tracker | Raid WAs | `ENC✗` | M | R | 3 |

---

## G. Survival, control and utility

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| X-01 | Charge / Intercept / Intervene range indicator | Range WAs | `OW` | S | L1 | 1 |
| X-02 | Healing potion / healthstone count and cooldown | Consumable WAs | `OW` | S | L2 | 2 |
| X-03 | Bandage readiness ("recently bandaged" timer) | Levelling WAs | `OW` | S | L2 | Pass |
| X-04 | Loss-of-control alert with Berserker Rage / trinket hint | WA packs | `OW` `BUILT-IN` (loss-of-control frame) | S | Check | 3 |
| X-05 | **Big stance indicator** (centre-screen, colour-coded) | Warrior WAs | `OW` | S | L1 | 3 |
| X-06 | Local combat text for parry/dodge/block/crit (no chat) | MSBT, SCT | `OW` `BUILT-IN` (floating combat text) | M | A-12 | 1 |
| X-07 | **Warrior macro generator**: stance-dance, Charge+attack, mouseover interrupt, weapon swaps — creates macros out of combat | Macro guides | `OOC` | S | G | 1 |
| X-08 | Action bar profile per stance helper | Bartender stance paging | `OOC` `BUILT-IN` (stance paging) | M | Skip | Skip |
| X-09 | Death recap | Details! | `OW` | M | L2 | 3 |
| X-10 | Runner / add alerts | Levelling WAs | `OW` | S | L2 | 3 |
| X-11 | Pull check | Own | `OOC` | M | L2 | 3 |

---

## H. Levelling quality of life

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| Q-01 | XP dashboard, kills to level, rested XP | XToLevel, Experiencer | `OOC` | M | L3 | Pass |
| Q-02 | Session review and grind-spot comparison | Own | `OOC` | M | L3 | Pass |
| Q-03 | Trainer reminder | Classic trainer add-ons | `OOC` | S | L4 | 2 |
| Q-04 | Weapon upgrade watch on quest rewards and loot | Pawn | `OOC` | M | L4 | 3 |
| Q-05 | Weapon skill tracker | Classic WAs | `OOC` `FOREVER?` | S | L4 | Pass |
| Q-06 | Auto-sell greys / auto-repair | Leatrix Plus | `OOC` | S | L4 | Pass |
| Q-07 | Quest guide / waypoints | Questie, RestedXP | — | L | Skip (use existing) | Skip |
| Q-08 | Rare/elite scanner alert | RareScanner, NPCScan | `OOC` | M | Later | Pass |
| Q-09 | Mob intel tooltip (your TTK, health lost, deaths) | MobInfo | `OOC` | S | L3 | Pass |

---

## I. Open-world PvP (warrior)

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| P-01 | Enemy player nearby alert | Spy | `OW` | M | Later | Pass |
| P-02 | Enemy cast bars on target | ClassicCastbars | `OW` `BUILT-IN` | S | Skip | Skip |
| P-03 | Enemy defensive/trinket cooldown tracker | OmniBar | `OW` | M | Later | Pass |
| P-04 | Hamstring/Piercing Howl uptime on enemy player | PvP WAs | `OW` | S | Later | Pass |

---

## J. Raid and team (v3)

| ID | Idea | Inspired by | Feasibility | Effort | Track | Triage |
|---|---|---|---|---|---|---|
| RA-01 | Shout assignments (who owns Battle/Demo Shout) | Pally Power-style | `OOC` sync | M | R | 3 |
| RA-02 | Sunder coordination per boss | Raid WAs | `ENC✗` | M | R | 3 |
| RA-03 | Shield Wall / Last Stand rotation for tanks | Angry Assignments | `OOC` plan, `ENC✗` live | L | R | 3 |
| RA-04 | Post-fight warrior report (sunders, shout uptime, cooldown use) | WarcraftLogs | `OOC` | M | R | 3 |

---

## Notes for triage

- **Chat restrictions matter for track A.** Since Retail 8.2.5, add-ons can't send SAY/YELL outdoors without a key press; party, raid and instance chat are fine outside encounters. Midnight additionally restricts add-on chat in encounters. Default every announcement to **local big text or party chat**, with SAY only when triggered from a keybind macro.
- **Gear swapping in combat:** armour cannot be changed in combat (Classic and Retail rules); weapons can, but only through a protected path (keybind/macro/secure button). The value of track G is keybinds, event automation and the combat queue, not bypassing that.
- **Check Blizzard's built-ins first** for anything tagged `BUILT-IN`: Cooldown Manager, loss-of-control frame, nameplate threat colours, floating combat text, equipment flyouts and pull countdown.
- **Etiquette:** parry/dodge announcements in SAY were notoriously spammy. Throttle (e.g. max one per 5s), and default to self or party.

---

## Triage results (9 October 2026)

Rated by Hugh: **1** must have · **2** should have · **3** nice to have · **Pass** dropped.

| Rating | Items |
|---|---|
| **1 (17)** | U-01 Battle Shout big alert · R-03 Execute · R-01 Overpower · R-11 Interrupt prompt · S-04 Auto-attack not running · X-01 Charge range · R-06 Core cooldown tracker · X-06 Local combat text · A-01 Parry/dodge/block announce · A-02 Taunt resisted · A-03 Challenging Shout/Mocking Blow announce · A-04 Shield Wall/Last Stand announce · A-07 Disarm/Intimidating Shout announce · G-01 Gear set keybinds · X-07 Macro generator · U-02 Battle Shout party coverage · T-05 Tank stat sheet |
| **2 (13)** | R-02 Revenge · U-05 Sunder · U-06 Rend · U-07 Hamstring · U-04 Thunder Clap · X-02 Potions/healthstone · A-05 Interrupt announce · A-08 Low health call · A-06 Sunder counter · G-03 In-combat weapon swap · G-02 Combat swap queue · G-10 Resistance sets · Q-03 Trainer reminder |
| **3** | X-11 Pull check · X-09 Death recap · Q-04 Weapon upgrade watch · R-08 Bloodrage prompt · X-05 Big stance indicator · X-10 Runner/add alerts · U-03 Demo Shout · A-11 Announce templates · U-10 Weapon enchant missing · G-08 Set integrity · T-02 Threat lead · T-07 Marker helper · R-07 Big cooldown-ready alerts · A-10 Pull announce · X-04 Loss of control · Raid set (RA-01 to RA-04, T-08) |
| **Pass** | Swing timer and related (S-01 to S-05, built in) · R-09 HS queued · all analytics (Q-01, Q-02, Q-09) · Q-05, Q-06, Q-08 · R-04, R-05, R-10, R-12, R-13 · U-08, U-09, U-11, U-12, U-13, U-14 · G-04 to G-07, G-11, G-12 · X-03 · T-01, T-04, T-06 · A-09, A-12 · all PvP |
