# Testing in the Forever beta

The one page to follow when testing in game. It is built in stages: each stage has a **check**, and you only go on when it passes. If a check fails, stop and tell Claude what you saw (exact error text if there is one); there is no point running later stages on a broken base.

**Deadline:** the beta closes on **21 October 2026**. Stages 1–4 are the minimum (about an hour, solo). Stage 5 needs a second player.

---

## Stage 0: one-time setup (done by Claude on 9 Oct)

| What | Where | State |
|---|---|---|
| Beta client | `C:\Program Files (x86)\World of Warcraft\_classic_beta_` (product `wow_classic_beta`, version 1.60.1.70291) | found |
| Add-ons | `_classic_beta_\Interface\AddOns\WarriorWorkshop` and `...\WarriorWorkshopProbe` | **installed as junctions** pointing at this repo |
| Your saved files | `_classic_beta_\WTF\Account\110732759#1\...` | created by the game after the first `/reload` |

Because they are junctions, the game reads the add-ons straight from the repo: nothing needs copying after code changes. Check the state any time from the repo folder (PyCharm terminal):

```
python tools/wowdev.py status
```

Other commands: `install` (re-create the junctions), `uninstall` (remove them; the repo is never touched), `collect` (copy the saved files into `beta-results/` for Claude to read). If the beta client moves, add `--wow-root "<folder>"` or `--client <name>`.

---

## Stage 1: does it load? (5 min)

1. **Fully restart** the beta client (new add-ons are only picked up at start-up).
2. At character select, click **AddOns** (bottom left). You should see **Warrior Workshop** and **Warrior Workshop Probe**, both ticked.
   - If they are marked *out of date*, tick **Load out of date AddOns** at the top. (The Interface number is a guess until V-01 is confirmed; this is expected, not a failure.)
3. Log in with your warrior.
4. In the chat box, type: `/console scriptErrors 1` then `/reload`.
5. Type `/dump select(4, GetBuildInfo())` and note the number: ______ (this is the real Interface number, V-01).

**Check:** no Lua error popup at login or after `/reload`. Note any chat lines that start `Warrior Workshop: API unavailable` or `Could not register` (they are findings, not failures).
**If it fails:** a popup means a load error. Copy the first few lines of the error text and stop.

---

## Stage 2: the add-on's core (M0 + M2, 10 min)

| # | Do | Expect |
|---|---|---|
| 1 | `/ww version` | `Warrior Workshop 0.0.1 - schema 2 - interface <N> (build <B>)` |
| 2 | `/ww debug` | `Debug logging is on.` |
| 3 | `/reload`, then `/ww debug` | `Debug logging is off.` (proves settings survive a reload) |
| 4 | `/ww debug` (on again), attack any mob, finish the fight | two lines: `[debug] context: openWorld, solo, restricted=false, combat=true, ...` then the same with `combat=false` |
| 5 | `/ww foo` | `'/ww foo' is not available yet. Try /ww version.` |

**Check:** all five as expected, no Lua errors. Leave debug on; it is harmless.
**If it fails:** note the step number and what appeared instead. You can still continue to Stage 3 (the probe is a separate add-on), but tell Claude.

---

## Stage 3: probe, out of combat (15 min)

Before starting: in the character pane, open the **Equipment Manager** and save **two sets** (for example "DPS" with a two-hander and "Tank" with one-hander + shield). Keep the weapon(s) you are *not* wearing in your bags.

| # | Do | Expect |
|---|---|---|
| 1 | `/wwprobe clear`, then `/wwprobe` | a version line, API counts and `issecretvalue: function` (or `nil`; either is a finding) |
| 2 | `/wwprobe spells` | `Spells dump saved: ...`; a "Not resolved by name" list is a finding, not a failure |
| 3 | `/wwprobe tank` | `Tank stats saved.` |
| 4 | `/wwprobe macro` | `Macro test: create ok, edit ok, deleted. ...` and no `WW Probe` macro left behind |
| 5 | `/wwprobe sets`, then `/wwprobe sets 1` | your sets are listed; after ~2s `Set 1: n of n slots now match the set` |
| 6 | Game menu → **Key Bindings** → find **Warrior Workshop Probe** (under AddOns) → bind **"Probe: SAY test line (key press)"** to a spare key → close. Go **outdoors** and press it | the binding exists; a `[WWPROBE test] ... SAY key` line appears in /say |
| 7 | Outdoors: `/wwprobe chat` | after ~8s one line per channel (SAY, YELL, plus PARTY if grouped). SAY/YELL showing `no echo` and `ADDON_ACTION_BLOCKED` is the **expected finding**. An "Interface action failed because of an AddOn" message may appear; dismiss it |
| 8 | `/wwprobe swapbtn ` then shift-click the **bag** weapon(s) to swap *to* (main hand first, then off hand), Enter | `Swap button ready on CTRL-SHIFT-F9` |
| 9 | Talk to a warrior trainer | `Trainer dump saved (auto): n service(s).` |

**Check:** every step printed its line and there were no Lua errors.

---

## Stage 4: probe in open-world combat (25 min)

1. `/wwprobe combat on`
2. Fight at least **5 mobs, including one caster**. During the fights, as many of these as you can:
   - Charge in; let mobs dodge, parry and block you;
   - use **Overpower** when it lights up;
   - interrupt the caster (Pummel or Shield Bash);
   - take a mob below 20% and use **Execute**;
   - cast **Battle Shout**, then let it **expire** once;
   - use Rend, Sunder Armor, Hamstring and Thunder Clap if you have them.
3. In one fight: press **Ctrl-Shift-F9** (did your weapons change? yes / no) and type `/wwprobe sets 2` (did your armour change? yes / no).
4. After combat: `/wwprobe swapbtn restore`, then `/wwprobe status`.

**Check:** `/wwprobe status` shows `openWorld` samples above 0 and **`handler errors 0`**. A non-zero handler error count is a probe bug: still collect (Stage 7), and say so.

**This is the minimum useful run.** If you are short of time, skip to Stage 7 now.

---

## Stage 5: with a second player (45–60 min, optional but valuable)

The second player needs the probe too: zip `WarriorWorkshopProbe` from the repo, and they unzip it into their `_classic_beta_\Interface\AddOns\`.

1. Form a party in the open world. **Warn them first**, then `/wwprobe chat` (sends test lines to PARTY, SAY, YELL).
2. Taunt mobs repeatedly (hoping for a resist); use Challenging Shout and Shield Wall.
3. Dungeon trash: `/wwprobe chat party` (or `/wwprobe chat instance_chat` if you queued through group finder), and `/wwprobe ping`.
4. First boss: follow the **Encounter test script** in `docs/PROBE_RESULTS.md` (pull, cast a known ability, `/wwprobe ping` mid-fight from both players). Also type `/wwprobe chat party` (or `instance_chat`) mid-fight.
5. Both players `/reload` afterwards. The second player sends you `WTF\Account\<their account>\SavedVariables\WarriorWorkshopProbe.lua`. Save it anywhere in the repo's `beta-results/` folder.

---

## Stage 6: relog and built-in tools (10 min)

1. Log out to character select, log back in, type `/wwprobe chatkey`. **Expect:** the key from Stage 3 step 6 is still bound.
2. Write a few words on each built-in (V-31):
   - **Cooldown Manager:** what can it show for warrior abilities (Edit Mode or Options)?
   - **Swing timer:** is there one built in, and what options does it have?
   - **Floating combat text:** are there options to show parry, dodge and block?
   - **Loss-of-control:** does a frame appear when you are stunned or feared?

---

## Stage 7: hand back the results (2 min)

1. In game: `/wwprobe status`, then **`/reload`** (this writes the files to disk).
2. Tell Claude: **"beta run done"**, plus:
   - the Interface number from Stage 1 step 5;
   - any Lua error text, `API unavailable` or `Could not register` lines;
   - the yes/no answers from Stage 4 step 3;
   - your built-in notes from Stage 6;
   - anything that did not match the "Expect" column.
3. Claude runs `python tools/wowdev.py collect`, which copies your saved files into `beta-results/<date>/` (git-ignored), and reads them directly, so there is no need to paste the files. (You can run that command yourself too.)

---

## Before we move on to M5

These must be true; Claude records the outcome in `docs/DECISIONS.md` and `docs/PROBE_RESULTS.md`:

| Gate | Evidence |
|---|---|
| Add-on and probe load without Lua errors | Stages 1–2 |
| Saved variables persist and migrate (schema 2) | Stage 2, collected files |
| Interface number and client folder known (D-005) | Stage 1 step 5 |
| Combat values: readable in the open world or not (V-11–V-15) | Stage 4, collected probe file |
| Combat log or `UNIT_COMBAT` usable for parry/dodge/block (V-16) | Stage 4 |
| Chat sending rules known (V-25, V-26) | Stages 3, 5 |
| Each Phase B–D feature marked Go / Degraded / No-go | decision gate table in `docs/PROBE_RESULTS.md` |
