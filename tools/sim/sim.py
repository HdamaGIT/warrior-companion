"""Headless WoW client simulator for Warrior Workshop (D-011).

Runs the real add-on files, in .toc order, inside an embedded Lua 5.1 runtime (lupa) against a fake
client environment. It checks that the add-on loads, reacts to events, persists SavedVariables and
answers slash commands. It cannot confirm that a fake API matches the real Forever client: each
data API is tagged KNOWN or ASSUMED in lua/api.lua, and a run reports which ASSUMED ones were used.

Usage:
    python tools/sim/sim.py run [--scenario NAME] [--addon NAME] CMD...
    python tools/sim/sim.py repl [--scenario NAME] [--addon NAME]
    python tools/sim/sim.py scenarios

CMD is a slash command ("/ww version") or a directive:
    !fire EVENT [args]   !advance SECONDS   !combat on|off   !reload   !logout   !lua CODE
    !snapshot [NAME]     write an HTML picture of the add-on's frames to sim-out/NAME.html
                         (add --open to open each snapshot in the browser)
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import sys
import tempfile
import webbrowser
from pathlib import Path

from lupa import lua51

REPO = Path(__file__).resolve().parents[2]
LUA_DIR = Path(__file__).with_name("lua")
SCENARIO_DIR = Path(__file__).with_name("scenarios")
SNAPSHOT_DIR = REPO / "sim-out"

DEFAULT_WORLD = {
    "player": {
        "name": "Testwarrior",
        "realm": "Testrealm",
        "class": "WARRIOR",
        "classLocalised": "Warrior",
        "classID": 1,
        "level": 1,
    },
    # Placeholder build info. The interface number matches the .toc placeholder (V-01 unverified).
    "build": {"version": "0.0.0-sim", "build": "00000", "date": "Jan 1 2026", "interface": 120105},
    "money": 0,
    "inCombat": False,
    "inGroup": False,
    "inRaid": False,
    "bags": {},
    "items": {},
    "time": 1000,
}


class SimError(Exception):
    """Raised for set-up problems (missing .toc or file), not for errors inside the add-on."""


def deep_merge(base: dict, extra: dict) -> dict:
    out = copy.deepcopy(base)
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


def load_scenario(scenario) -> dict:
    """Accepts a scenario name, a path to a .json file, or a dict; merges it over DEFAULT_WORLD."""
    if isinstance(scenario, dict):
        extra = scenario
    else:
        path = Path(scenario)
        if not path.suffix:
            path = SCENARIO_DIR / f"{scenario}.json"
        if not path.exists():
            raise SimError(f"scenario not found: {scenario}")
        extra = json.loads(path.read_text(encoding="utf-8"))
    return deep_merge(DEFAULT_WORLD, extra)


def parse_toc(path: Path) -> dict:
    """Parses a .toc into meta, file list (forward slashes) and SavedVariables names."""
    meta: dict[str, str] = {}
    files: list[str] = []
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        match = re.match(r"##\s*([\w\-]+)\s*:\s*(.*)$", line)
        if match:
            meta[match.group(1)] = match.group(2).strip()
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))

    def names(key: str) -> list[str]:
        return [n.strip() for n in meta.get(key, "").split(",") if n.strip()]

    return {
        "meta": meta,
        "files": files,
        "savedVars": names("SavedVariables"),
        "savedVarsChar": names("SavedVariablesPerCharacter"),
    }


def to_lua(lua, obj):
    """Converts JSON-style Python data to Lua tables. Digit-only dict keys become integers."""
    if isinstance(obj, dict):
        table = lua.table()
        for key, value in obj.items():
            if isinstance(key, str) and re.fullmatch(r"-?\d+", key):
                key = int(key)
            table[key] = to_lua(lua, value)
        return table
    if isinstance(obj, (list, tuple)):
        table = lua.table()
        for index, value in enumerate(obj, 1):
            table[index] = to_lua(lua, value)
        return table
    return obj


def to_py(value):
    """Converts Lua tables to dicts, or lists when the keys are exactly 1..n."""
    if not lua51.lua_type(value) == "table":
        return value
    keys = list(value.keys())
    if keys and sorted(keys, key=lambda k: (isinstance(k, str), k)) == list(range(1, len(keys) + 1)):
        return [to_py(value[i]) for i in range(1, len(keys) + 1)]
    return {k: to_py(value[k]) for k in keys}


_COLOUR = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|T.*?\|t|\|H.*?\|h|\|h")


def strip_codes(text: str) -> str:
    """Removes WoW colour, hyperlink and texture escapes so tests can compare plain text."""
    return _COLOUR.sub("", text)


class Client:
    """One simulated WoW session for one character.

    Typical use:
        client = Client(scenario="fresh")
        client.login()
        client.slash("/ww version")
        assert client.chat == [...] and not client.errors
        client.reload()      # logout (writes SavedVariables) then a fresh Lua state and login
        client.close()
    """

    def __init__(self, scenario="fresh", addons=("WarriorWorkshop",), addons_root: Path | None = None,
                 sv_dir: Path | None = None):
        self.world = load_scenario(scenario)
        self.scenario_name = scenario if isinstance(scenario, str) else "custom"
        self.open_snapshots = False
        self.addons = list(addons)
        self.addons_root = Path(addons_root) if addons_root else REPO
        self._owns_sv_dir = sv_dir is None
        self.sv_dir = Path(sv_dir) if sv_dir else Path(tempfile.mkdtemp(prefix="wwsim-"))
        self.warnings: list[str] = []
        self.lua = None
        self._sim = None

    # ---- lifecycle -------------------------------------------------------------------------

    def login(self) -> None:
        self._boot(reloading=False)

    def reload(self) -> None:
        """Equivalent to /reload: write SavedVariables, discard the Lua state, load everything again."""
        self.logout()
        self._boot(reloading=True)

    def logout(self) -> None:
        """Fires PLAYER_LOGOUT and writes SavedVariables to disk. The Lua state stays inspectable."""
        self._require_running()
        self._sim.fire("PLAYER_LOGOUT")
        self._sim.saveSavedVars()

    def close(self) -> None:
        if self._owns_sv_dir:
            shutil.rmtree(self.sv_dir, ignore_errors=True)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def _boot(self, reloading: bool) -> None:
        player = self.world["player"]
        account_dir = self.sv_dir / "account"
        char_dir = self.sv_dir / f"{player['realm']}-{player['name']}"
        account_dir.mkdir(parents=True, exist_ok=True)
        char_dir.mkdir(parents=True, exist_ok=True)
        self.world["svAccountDir"] = account_dir.as_posix()
        self.world["svCharDir"] = char_dir.as_posix()

        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        load = self.lua.globals().loadstring
        env_factory = load((LUA_DIR / "wowenv.lua").read_text(encoding="utf-8"), "@wowenv.lua")()
        api_installer = load((LUA_DIR / "api.lua").read_text(encoding="utf-8"), "@api.lua")()
        self._sim = env_factory(to_lua(self.lua, self.world))
        api_installer(self._sim)

        self.warnings = []
        for name in self.addons:
            self._load_addon(name)
        self._sim.fire("PLAYER_LOGIN")
        self._sim.fire("PLAYER_ENTERING_WORLD", not reloading, reloading)

    def _load_addon(self, name: str) -> None:
        folder = self.addons_root / name
        toc_path = folder / f"{name}.toc"
        if not toc_path.exists():
            raise SimError(f"missing .toc: {toc_path}")
        toc = parse_toc(toc_path)
        for relative in toc["files"]:
            if not (folder / relative).exists():
                raise SimError(f"{name}.toc lists a file that does not exist: {relative}")
        interface = toc["meta"].get("Interface")
        # The client accepts a comma-separated list of Interface numbers; any match loads the add-on.
        accepted = {int(part) for part in interface.split(",") if part.strip()} if interface else set()
        if accepted and int(self.world["build"]["interface"]) not in accepted:
            self.warnings.append(
                f"{name} is out of date: .toc Interface {interface}, client {self.world['build']['interface']}"
            )
        info = to_lua(self.lua, {
            "name": name,
            "dir": folder.as_posix(),
            "files": toc["files"],
            "meta": toc["meta"],
            "savedVars": toc["savedVars"],
            "savedVarsChar": toc["savedVarsChar"],
        })
        self._sim.loadAddon(info)

    def _require_running(self) -> None:
        if self._sim is None:
            raise SimError("call login() first")

    # ---- driving the client ----------------------------------------------------------------

    def slash(self, line: str) -> bool:
        """Types a slash command. Returns False if no add-on registered it."""
        self._require_running()
        return bool(self._sim.slash(line))

    def fire(self, event: str, *args) -> None:
        self._require_running()
        self._sim.fire(event, *args)

    def advance(self, seconds: float) -> None:
        """Moves the simulated clock forward, running C_Timer callbacks that fall due."""
        self._require_running()
        self._sim.advance(seconds)

    def set_combat(self, in_combat: bool) -> None:
        """Enters or leaves combat in the order beta run 2 recorded: restriction type 0 (Combat) becomes Active
        before either event fires; PLAYER_REGEN_DISABLED then ADDON_RESTRICTION_STATE_CHANGED(0, 1) on entry,
        ADDON_RESTRICTION_STATE_CHANGED(0, 0) then PLAYER_REGEN_ENABLED on exit. PLAYER_ENTER_COMBAT (auto-attack)
        is separate: fire it yourself."""
        self.set("inCombat", in_combat)
        self.set("restrictions.0", 2 if in_combat else 0)
        if in_combat:
            self.fire("PLAYER_REGEN_DISABLED")
            self.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
        else:
            self.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
            self.fire("PLAYER_REGEN_ENABLED")

    def set(self, path: str, value) -> None:
        """Changes the fake world, e.g. set("money", 5000) or set("bags.0.slots", 20)."""
        self._require_running()
        keys = [int(p) if re.fullmatch(r"-?\d+", p) else p for p in path.split(".")]
        target, live = self.world, self._sim.world
        for key in keys[:-1]:
            target = target.setdefault(str(key) if not isinstance(key, str) else key, {})
            if live[key] is None:
                live[key] = self.lua.table()
            live = live[key]
        target[str(keys[-1])] = value
        live[keys[-1]] = to_lua(self.lua, value)

    def eval(self, code: str):
        """Runs a Lua expression or statement list in the add-on environment (tests, REPL)."""
        self._require_running()
        load = self.lua.globals().loadstring
        chunk = load(f"return {code}")
        if isinstance(chunk, tuple):  # not an expression: try it as statements
            chunk = load(code)
        if isinstance(chunk, tuple):
            raise SimError(f"Lua syntax error: {chunk[1]}")
        return to_py(chunk())

    def get(self, name: str):
        """Reads a global (dotted path allowed, e.g. "FakeDB.loads") as plain Python data."""
        self._require_running()
        value = self.lua.globals()
        for part in name.split("."):
            value = value[int(part) if part.isdigit() else part]
            if value is None:
                return None
        return to_py(value)

    # ---- observing -------------------------------------------------------------------------

    @property
    def chat(self) -> list[str]:
        """Chat lines so far with colour and hyperlink escapes removed."""
        self._require_running()
        return [strip_codes(self._sim.chat[i]) for i in range(1, len(self._sim.chat) + 1)]

    def clear_chat(self) -> None:
        self._require_running()
        self._sim.chat = self.lua.table()

    @property
    def errors(self) -> list[str]:
        """Lua errors raised inside the add-on (also recorded when a handler fails)."""
        self._require_running()
        return [self._sim.errors[i] for i in range(1, len(self._sim.errors) + 1)]

    def registered_events(self) -> set[str]:
        self._require_running()
        return set(self._sim.registered.keys())

    def api_used(self) -> dict[str, str]:
        """Data APIs the add-on called, with their KNOWN/ASSUMED status."""
        self._require_running()
        return {k: v for k, v in self._sim.apiUsed.items()}

    def assumed_apis_used(self) -> list[str]:
        return sorted(k for k, v in self.api_used().items() if v == "ASSUMED")

    def stubbed_methods(self) -> list[str]:
        """Frame methods that were called but are only no-op stubs in the simulator."""
        self._require_running()
        return sorted(self._sim.stubbed.keys())

    def frames(self) -> list[dict]:
        """Every frame's recorded layout (see sim.dumpFrames in lua/wowenv.lua)."""
        self._require_running()
        return to_py(self._sim.dumpFrames()) or []

    def templates_used(self) -> list[str]:
        """Blizzard templates the add-on asked for; the simulator draws them bare."""
        self._require_running()
        return sorted(self._sim.templates.keys())

    def snapshot(self, path: Path | str | None = None, title: str = "Warrior Workshop") -> tuple[Path, list[str]]:
        """Writes an HTML picture of the current frames. Returns (path, layout warnings)."""
        from preview import render  # local import keeps the headless path free of it

        path = Path(path) if path else SNAPSHOT_DIR / "snapshot.html"
        path.parent.mkdir(parents=True, exist_ok=True)
        screen = self.world.get("screen") or {}
        subtitle = f"scenario {self.scenario_name} · {'in combat' if self.world.get('inCombat') else 'out of combat'}"
        page, warnings = render(
            self.frames(),
            screen=(screen.get("width", 1920), screen.get("height", 1080)),
            title=title,
            subtitle=subtitle,
        )
        path.write_text(page, encoding="utf-8")
        return path, warnings


# ---- command line ------------------------------------------------------------------------


def _coerce(token: str):
    if token in ("true", "false"):
        return token == "true"
    for cast in (int, float):
        try:
            return cast(token)
        except ValueError:
            pass
    return token


def dispatch(client: Client, line: str) -> bool:
    """Runs one CLI/REPL line. Returns False to stop the session."""
    line = line.strip()
    if not line:
        return True
    if line.startswith("/"):
        if not client.slash(line):
            print(f"[sim] no add-on handled {line.split()[0]}")
        return True
    if not line.startswith("!"):
        print("[sim] commands start with / or !")
        return True
    name, _, rest = line[1:].partition(" ")
    if name == "fire":
        event, *args = rest.split()
        client.fire(event, *[_coerce(a) for a in args])
    elif name == "advance":
        client.advance(float(rest))
    elif name == "combat":
        client.set_combat(rest.strip() == "on")
    elif name == "reload":
        client.reload()
    elif name == "logout":
        client.logout()
    elif name == "lua":
        print(f"[sim] {client.eval(rest)!r}")
    elif name == "snapshot":
        target = SNAPSHOT_DIR / f"{rest.strip() or 'snapshot'}.html"
        path, warnings = client.snapshot(target)
        print(f"[sim] snapshot written: {path}")
        for warning in warnings:
            print(f"[sim]   layout: {warning}")
        if client.open_snapshots:
            webbrowser.open(path.resolve().as_uri())
    elif name in ("quit", "exit"):
        return False
    else:
        print(f"[sim] unknown directive !{name}")
    return True


def _flush_chat(client: Client, seen: int) -> int:
    lines = client.chat
    for line in lines[seen:]:
        print(line)
    return len(lines)


def _report(client: Client) -> int:
    code = 0
    for warning in client.warnings:
        print(f"[sim] warning: {warning}", file=sys.stderr)
    for error in client.errors:
        print(f"[sim] LUA ERROR: {error}", file=sys.stderr)
        code = 1
    assumed = client.assumed_apis_used()
    if assumed:
        print(f"[sim] used ASSUMED APIs (unverified in Forever): {', '.join(assumed)}", file=sys.stderr)
    return code


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["run", "repl", "scenarios"])
    parser.add_argument("commands", nargs="*")
    parser.add_argument("--scenario", default="fresh")
    parser.add_argument("--addon", action="append", help="add-on folder to load (default WarriorWorkshop)")
    parser.add_argument("--sv-dir", help="keep SavedVariables here between runs (default: temporary)")
    parser.add_argument("--open", action="store_true", help="open each !snapshot in the browser")
    parser.add_argument("--addons-root", help="folder holding the add-on folders (default: the repo root)")
    args = parser.parse_args(argv)

    if args.mode == "scenarios":
        for path in sorted(SCENARIO_DIR.glob("*.json")):
            print(path.stem)
        return 0

    client = Client(
        scenario=args.scenario,
        addons=args.addon or ["WarriorWorkshop"],
        sv_dir=Path(args.sv_dir) if args.sv_dir else None,
        addons_root=Path(args.addons_root) if args.addons_root else None,
    )
    client.open_snapshots = args.open
    try:
        client.login()
        seen = _flush_chat(client, 0)
        if args.mode == "run":
            for line in args.commands:
                if not dispatch(client, line):
                    break
                seen = _flush_chat(client, seen)
        else:
            print("Warrior Workshop simulator. /command or !directive; !quit to leave.")
            while True:
                try:
                    line = input("wow> ")
                except EOFError:
                    break
                if not dispatch(client, line):
                    break
                seen = _flush_chat(client, seen)
        code = _report(client)
        client.logout()
        return code
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
