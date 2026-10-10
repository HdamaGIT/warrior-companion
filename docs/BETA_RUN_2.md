# Beta run 2: step by step

Solo, about 40 minutes, any time before **21 October 2026**. It re-tests what run 1 (9 Oct) couldn't capture, using probe version 3. Nothing needs installing: the add-ons are junctions, so the game already has the latest code.

Tick each box as you go. If a **Check** fails, note what you saw (the exact error text, if any) and carry on unless it says stop.

Full background for each stage is in `docs/BETA_TESTING.md`.

---

## 1. Start up (3 min)

- [ ] **Fully restart** the beta client. The probe changed, so a `/reload` isn't enough.
- [ ] Log in with your warrior (Sphere is best: level 8 has more abilities than level 1).
- [ ] Type `/console scriptErrors 1`.
- [ ] Type `/wwprobe clear`, then `/wwprobe`. (Run 1's data is already saved in `beta-results/`.)
- [ ] Type `/dump WarriorWorkshopProbeDB.probeVersion`. It should print **3**.

**Check:** there's **no** "Warrior Workshop Probe has been blocked from an action only available to the Blizzard UI" popup this time.
Popup still appears → note it and continue. The probe now records it either way.

---

## 2. Fix the test set (3 min)

In run 1, "test2" was saved with no gear in it, which is why applying it took your gear off.

- [ ] Open the character pane, then the **Equipment Manager**.
- [ ] Wear your normal gear. Select **test2**, then click **Save** to overwrite it with what you're wearing.
- [ ] Make a second set that differs by **one armour piece** (for example, take your chest or boots off), and save it as **test1**.
- [ ] Type `/wwprobe sets`.

**Check:** both sets are listed, and each shows more than 0 items. Note which number belongs to which set: ______

---

## 3. Out-of-combat probe commands (10 min)

| # | Type | Expect |
|---|---|---|
| 1 | `/wwprobe spells` | `Spells dump saved: ...`. A "Not resolved by name" list is fine. |
| 2 | `/wwprobe tank` | `Tank stats saved.`. Glance at your character pane's dodge, parry and block numbers: ______ |
| 3 | `/wwprobe macro` | `Macro test: create ok, edit ok, deleted.`, and no `WW Probe` macro is left in `/macro` |
| 4 | `/wwprobe sets 1` (or whichever number is the set you're *not* wearing) | after about 2s: `Set 1: n of n slots now match the set` |
| 5 | Talk to a **warrior trainer** | `Trainer dump saved (auto): n service(s).` |

### Swap button (needs links)

- [ ] Put a different weapon in your bags. A spare two-hander, or a one-hander plus a shield, is ideal; any other weapon will do.
- [ ] Type `/wwprobe swapbtn ` (with a trailing space). **Don't press Enter yet.**
- [ ] **Shift-click the bag weapon** so its link appears in the chat box. If you have an off-hand too, shift-click that second.
- [ ] Press Enter.

**Check:** `Swap button ready on CTRL-SHIFT-F9`.
A `Usage: ...` line means the links didn't arrive. Make sure the chat box shows the [item names] in colour before you press Enter.

- [ ] Out of combat, press **Ctrl-Shift-F9**. Did your weapon change? **yes / no**

### Key binding

- [ ] Open the game menu → **Options** → **Keybindings** → find **Warrior Workshop Probe** (in the AddOns section).
- [ ] Bind **"Probe: SAY test line (key press)"** to a spare key, such as Ctrl-Shift-F10.
- [ ] Go **outdoors**, out of combat, and press it.

**Check:** a `[WWPROBE test] ... SAY key` line appears in /say.

### Chat from an add-on (expected to be blocked)

- [ ] Outdoors, type `/wwprobe chat` and wait about 8 seconds.

**Check:** one result line each for SAY and YELL. "no echo" or `ADDON_ACTION_BLOCKED` is the **expected finding**, not a failure. If an "Interface action failed because of an AddOn" message appears, dismiss it.

---

## 4. Combat (15 min): the main reason for this run

- [ ] Type **`/wwprobe combat on` before your first pull.** In run 1 the sampler recorded nothing, so this is the key test.
- [ ] Fight **one** mob, then type `/wwprobe status`.

**Check:** the line `combat sampler on: openWorld N, ...` shows **N above 0**.
Still 0 → stop combat testing and go to step 6, collect, and tell me. The sampler itself needs fixing.

- [ ] Fight at least **5 more mobs, including one caster**. Try to:
  - Charge in, and let mobs dodge, parry and block you (lower-level mobs in front of you are fine);
  - use **Overpower** when it lights up;
  - interrupt the caster (Pummel or Shield Bash, if you have one);
  - take a mob below 20% and use **Execute** (if known);
  - cast **Battle Shout**, then let it **expire** once;
  - use Rend, Sunder Armor, Hamstring and Thunder Clap if you have them.
- [ ] **In one fight**, press **Ctrl-Shift-F9**. Did your weapon change in combat? **yes / no**
- [ ] **In one fight**, type `/wwprobe sets 1` (the set you're not wearing). Did your armour change? **yes / no** (expected: no. It should be refused or queued in combat.)
- [ ] After combat, type `/wwprobe swapbtn restore`.
- [ ] Type `/wwprobe status`.

**Check:** samples are above 0 and **`handler errors 0`**.

---

## 5. Relog (3 min)

- [ ] Log out to character select, then log back in.
- [ ] Type `/wwprobe chatkey`.

**Check:** your key binding from step 3 is still listed.

While you're here, note anything you've noticed about Blizzard's built-in tools (optional):
- **Cooldown Manager:** can it show warrior abilities? ______
- **Floating combat text:** does it show parry, dodge and block? ______
- **Swing timer:** is there one built in? ______
- **Loss-of-control frame:** does one appear when you're stunned or feared? ______

---

## 6. Hand back (2 min)

- [ ] Type `/wwprobe status`, then **`/reload`**. This writes the files to disk.
- [ ] Quit the game.
- [ ] Tell Claude **"collect"**, plus:
  - popup at login: yes / no;
  - the swap-button result out of combat and in combat: yes / no, yes / no;
  - the set change in combat: yes / no;
  - any Lua error text;
  - your built-in notes, if any.

Claude then runs `python tools/wowdev.py collect`, analyses the files, fills in `docs/PROBE_RESULTS.md` and marks each feature **Go / Degraded / No-go**.

---

**After this:** a group run (Stage 5 in `docs/BETA_TESTING.md`) with a second player, before 21 Oct, to test party chat, taunt resists and a dungeon boss.
