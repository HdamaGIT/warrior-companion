# Developer setup (Windows)

## 1. Find the client's AddOns folder

Forever installs under your World of Warcraft directory, usually `C:\Program Files (x86)\World of Warcraft\`. Each client flavour has its own subfolder. **The folder name is unconfirmed (V-01):**

- during the beta it is likely `_forever_beta_` or `_classic_beta_`;
- at launch it will be something else (record it in `docs/DECISIONS.md` as D-005).

To find it, open the Battle.net launcher, select WoW: Forever, then go to **Options → Show in Explorer**. The AddOns folder is `<client folder>\Interface\AddOns\`. Create it if it does not exist.

Below, `%WOW%` stands for the full client folder, for example `C:\Program Files (x86)\World of Warcraft\_forever_beta_`, and `%REPO%` stands for this repository, for example `C:\Users\hughd\PycharmProjects\warrior-companion`.

## 2. Junction the add-ons into the client

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
