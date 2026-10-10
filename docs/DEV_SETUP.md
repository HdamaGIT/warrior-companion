# Developer setup (Windows)

## 1. Find the client's AddOns folder

Forever installs under your World of Warcraft directory, usually `C:\Program Files (x86)\World of Warcraft\`. Each client flavour has its own subfolder. **The folder name is unconfirmed (V-01):**

- during the beta it is likely `_forever_beta_` or `_classic_beta_`;
- at launch it will be something else (record it in `docs/DECISIONS.md` as D-005).

To find it, open the Battle.net launcher, select WoW: Forever, then go to **Options → Show in Explorer**. The AddOns folder is `<client folder>\Interface\AddOns\`. Create it if it does not exist.

Below, `%WOW%` stands for the full client folder, for example `C:\Program Files (x86)\World of Warcraft\_forever_beta_`, and `%REPO%` stands for this repository, for example `C:\Users\hughd\PycharmProjects\warrior-companion`.

## 2. Junction the add-ons into the client

**Quickest:** from the repo root run `python tools/wowdev.py install` (and `status`, `uninstall`, `collect`). It finds the client (default `_classic_beta_`, the Forever beta client on this machine), creates both junctions and can copy the saved files back into `beta-results/`. The manual commands below do the same thing.

A directory junction lets the game load the add-ons straight from the repo, so you don't need to copy anything. Junctions don't need admin rights or Developer Mode. Close the game first.

**Command Prompt (`cmd.exe`):**

```bat
mklink /J "%WOW%\Interface\AddOns\WarriorWorkshop"      "%REPO%\WarriorWorkshop"
mklink /J "%WOW%\Interface\AddOns\WarriorWorkshopProbe" "%REPO%\WarriorWorkshopProbe"
```

**PowerShell** (where `mklink` isn't available directly):

```powershell
$wow  = 'C:\Program Files (x86)\World of Warcraft\_forever_beta_'
$repo = 'C:\Users\hughd\PycharmProjects\warrior-companion'
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\WarriorWorkshop"      -Target "$repo\WarriorWorkshop"
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\WarriorWorkshopProbe" -Target "$repo\WarriorWorkshopProbe"
```

If `Program Files` refuses the write, run the shell as Administrator for this one step.

To remove a junction, delete the link and nothing else: `rmdir "%WOW%\Interface\AddOns\WarriorWorkshop"`. Don't use `del /s`, because that follows the link into the repo.

The probe is a throwaway add-on. Disable it in the AddOns list, or remove its junction, once Phase 0 is done.

## 3. The edit → reload loop

1. Edit Lua in the repo.
2. In game, type `/reload`. Lua changes take effect immediately.
3. **New files and `.toc` edits need a full client restart.** `/reload` does not re-read the file list.
4. SavedVariables are written to disk **only on `/reload`, logout or exit**. A crash loses everything since the last reload.

## 4. Seeing Lua errors

- Enable error popups with `/console scriptErrors 1`. This persists across sessions. Turn it off with `/console scriptErrors 0`.
- If an error-capture add-on (such as BugSack or BugGrabber) is available for Forever, it gives better stack traces. It is optional and not a dependency.
- If the add-on shows as **out of date** in the AddOns list, the `## Interface:` number is wrong. Tick **Load out of date AddOns** to keep going, then run `/dump select(4, GetBuildInfo())` and record the number (V-01).

## 5. Where SavedVariables live

```
%WOW%\WTF\Account\<ACCOUNT_NAME>\SavedVariables\WarriorWorkshop.lua           (account-wide)
%WOW%\WTF\Account\<ACCOUNT_NAME>\SavedVariables\WarriorWorkshopProbe.lua      (probe output)
%WOW%\WTF\Account\<ACCOUNT_NAME>\<Realm>\<Character>\SavedVariables\WarriorWorkshop.lua   (per character)
```

`<ACCOUNT_NAME>` is a folder such as `12345678#1`, not your e-mail address.

## 6. Local tooling (optional, because CI covers it)

CI (`.github/workflows/ci.yml`) runs `luacheck .` and `busted` on Lua 5.1 for every push. Running them locally is quicker but optional.

The simplest way on Windows is to use **WSL (Ubuntu)**:

```bash
sudo apt install -y build-essential unzip libreadline-dev curl
# Lua 5.1 (matches WoW's runtime)
curl -R -O https://www.lua.org/ftp/lua-5.1.5.tar.gz && tar xzf lua-5.1.5.tar.gz
cd lua-5.1.5 && make linux && sudo make install && cd ..
# LuaRocks
curl -R -O https://luarocks.github.io/luarocks/releases/luarocks-3.11.1.tar.gz && tar xzf luarocks-3.11.1.tar.gz
cd luarocks-3.11.1 && ./configure --lua-version=5.1 && make && sudo make install && cd ..
sudo luarocks install luacheck
sudo luarocks install busted
```

Then, from the repo root:

```bash
luacheck .
busted
```

A native Windows install also works (for example LuaRocks with a MinGW toolchain), but it is more fiddly, and `busted` needs a C compiler for its dependencies.

## 7. Offline simulator (no game needed)

`tools/sim/` runs the real add-on files in an embedded Lua 5.1 (via the `lupa` Python package) against a fake WoW client (D-011). It checks load order, events, timers, slash commands and the SavedVariables write/reload cycle. It also gives you a local Lua 5.1 without WSL.

```powershell
pip install -r tools/sim/requirements.txt
python tools/sim/sim.py run "/ww version" "!reload" "/ww version"   # one-shot
python tools/sim/sim.py repl --scenario miner                       # interactive
python tools/sim/sim.py scenarios                                   # list worlds
python -m unittest discover -s tools/sim/tests                      # simulator and add-on tests
```

Directives: `!fire EVENT args`, `!advance SECONDS`, `!combat on|off`, `!reload`, `!logout`, `!lua EXPR`. Use `--sv-dir DIR` to keep SavedVariables between runs, and `--addon NAME` to load other add-ons (for example `WarriorWorkshopProbe`).

In Git Bash, set `MSYS_NO_PATHCONV=1` first, otherwise `"/ww"` is rewritten into a Windows path. PowerShell needs nothing.

**What a pass means:** the code works against the simulator's fake client. It does **not** mean the Forever API behaves that way. Each fake in `tools/sim/lua/api.lua` is `KNOWN` (long-standing signature) or `ASSUMED` (unconfirmed); every run prints the `ASSUMED` ones the add-on used. When `docs/PROBE_RESULTS.md` confirms or contradicts a shape, update the fake and its tag in the same commit.

**Extending it:** add a data API with `def("C_Foo.Bar", "ASSUMED", fn)` in `api.lua` when the Adapter starts using it, add world data to a scenario in `tools/sim/scenarios/`, and add an end-to-end test to `WarriorWorkshopTests` in `tools/sim/tests/test_sim.py`. Unknown PascalCase frame methods are silent no-ops (listed by `Client.stubbed_methods()`); unknown lowercase fields are `nil`, as on real frames.

### Visual preview (snapshots)

`!snapshot NAME` writes `sim-out/NAME.html` (git-ignored): a close-up of the add-on's visible frames, the full 1920×1080 screen, a list of layout warnings and a list of every frame. Add `--open` to open each snapshot in your browser as it is written.

```powershell
# the demo HUD fixture, out of combat and in combat
python tools/sim/sim.py run --open --addons-root tools/sim/tests/fixtures --addon UiAddon "!snapshot hud-idle" "!combat on" "!snapshot hud-combat"
# the real add-on, once it has UI (M5 onwards)
python tools/sim/sim.py run --open "/ww hud" "!snapshot hud"
```

The preview resolves `SetPoint`/`SetAllPoints` anchors and sizes the way the client does, and draws colour textures, status bars, backdrop colours, text (including `|cff…|r` colour codes) and shown or hidden state. Tick **show hidden frames** to see frames that exist but are hidden.

Layout warnings flag frames that are visible but have no anchor (the client would not draw them), frames entirely off-screen, zero-size frames, anchor loops, and frames built from a Blizzard template. Templates, art (`SetTexture` file paths, drawn hatched), fonts and scaling are **not** reproduced, so the preview checks placement and behaviour, not the final look. Sign-off is still the in-game checklist.

Not simulated: combat secret values, taint, protected-function rules, real skill-up randomness, the auction house, Blizzard art, fonts and templates.
