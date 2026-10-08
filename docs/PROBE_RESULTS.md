# Phase 0 probe results

**Status:** template, not yet run.
**Client build:** ______ **Interface:** ______ **Client folder:** ______ **Date run:** ______

Hugh runs the probe and pastes `WarriorWorkshopProbe.lua` from SavedVariables; Claude then fills in each section below. Every "Decision" either cites a `D-` entry in `docs/DECISIONS.md` or says "none needed".

Where to look in the dump: `static` = `/wwprobe`; `prof` = `/wwprobe prof`; `items` = `/wwprobe item`; `gear` = `/wwprobe gear`; `bags` = `/wwprobe bags`; `pings` = `/wwprobe ping`; `events` / `eventCounts` / `registrations` = event recorder.

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
- **Evidence:** `events` entries with `inEncounter = true`; arg 3 (spellID) `secret` flag and `value`.
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
