"""Install the add-ons into the WoW client and collect their saved files back (Windows dev helper).

Usage (from the repo root):
    python tools/wowdev.py status            # where the client is, what is installed, what saved files exist
    python tools/wowdev.py install           # junction WarriorWorkshop and WarriorWorkshopProbe into Interface\\AddOns
    python tools/wowdev.py install --copy    # copy instead of junction (a snapshot; re-run after every change)
    python tools/wowdev.py collect           # copy our SavedVariables files into beta-results/<timestamp>/
    python tools/wowdev.py uninstall         # remove the junctions/copies (never touches the repo)

Options: --wow-root PATH (default: auto-detected, or the WW_WOW_ROOT environment variable),
         --client NAME (default: _classic_beta_, the Forever beta client folder found on 9 Oct 2026).

A junction means the game loads the add-ons straight from the repo: edit, then /reload in game.
New files or .toc changes still need a full client restart. SavedVariables are only written on /reload,
logout or exit, so run `collect` after one of those.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ADDONS = ("WarriorWorkshop", "WarriorWorkshopProbe")
SAVED_FILES = ("WarriorWorkshop.lua", "WarriorWorkshopProbe.lua")
DEFAULT_CLIENT = "_classic_beta_"
CANDIDATE_ROOTS = (
    r"C:\Program Files (x86)\World of Warcraft",
    r"C:\Program Files\World of Warcraft",
    r"D:\World of Warcraft",
    r"D:\Games\World of Warcraft",
    r"C:\Games\World of Warcraft",
)
RESULTS_DIR = REPO / "beta-results"


def find_wow_root(explicit: str | None) -> Path:
    """Returns the World of Warcraft root folder, or exits with a clear message."""
    for candidate in (explicit, os.environ.get("WW_WOW_ROOT"), *CANDIDATE_ROOTS):
        if candidate and Path(candidate).is_dir():
            return Path(candidate)
    sys.exit("Could not find World of Warcraft. Pass --wow-root \"<folder>\" or set WW_WOW_ROOT.")


def client_dir(root: Path, client: str) -> Path:
    path = root / client
    if not path.is_dir():
        found = sorted(p.name for p in root.iterdir() if p.is_dir() and p.name.startswith("_"))
        sys.exit(f"No client folder {client!r} in {root}. Found: {', '.join(found)}. Use --client NAME.")
    return path


def read_version(root: Path, client: Path) -> str | None:
    """Reads the client's version from .build.info, matched by the product in <client>/.flavor.info."""
    try:
        product = (client / ".flavor.info").read_text(encoding="utf-8").splitlines()[-1].strip()
        lines = (root / ".build.info").read_text(encoding="utf-8").splitlines()
    except (OSError, IndexError):
        return None
    header = [column.split("!")[0] for column in lines[0].split("|")]
    for line in lines[1:]:
        row = dict(zip(header, line.split("|")))
        if row.get("Product") == product:
            return f"{product} {row.get('Version')}"
    return None


def is_link(path: Path) -> bool:
    """True for a junction or symlink (deleting one removes only the link)."""
    return path.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(path))


def describe(path: Path) -> str:
    if is_link(path):
        try:
            target = Path(os.readlink(path))
        except OSError:
            target = None
        return f"junction -> {target}" if target else "junction"
    if path.is_dir():
        return "copied folder (a snapshot: re-run install --copy after changes)"
    return "not installed"


def make_junction(link: Path, target: Path) -> None:
    result = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True, text=True)
    if result.returncode != 0:
        raise OSError(result.stderr.strip() or result.stdout.strip())


def remove_install(path: Path) -> None:
    """Removes a junction (link only) or a copied folder. Never follows a junction into the repo."""
    if is_link(path):
        os.rmdir(path)  # removes the link, not the target
    elif path.is_dir():
        if (REPO / path.name).resolve() == path.resolve():
            raise OSError(f"{path} resolves into the repo; refusing to delete")
        shutil.rmtree(path)


def saved_files(client: Path) -> list[Path]:
    """Our SavedVariables files under <client>/WTF (account-wide and per character)."""
    wtf = client / "WTF" / "Account"
    if not wtf.is_dir():
        return []
    return sorted(p for p in wtf.rglob("*.lua") if p.name in SAVED_FILES and p.parent.name == "SavedVariables")


def cmd_status(root: Path, client: Path) -> None:
    print(f"WoW root:   {root}")
    print(f"Client:     {client.name} ({read_version(root, client) or 'version unknown'})")
    addons = client / "Interface" / "AddOns"
    for name in ADDONS:
        print(f"{name + ':':<22}{describe(addons / name)}")
    files = saved_files(client)
    print("Saved files:" + ("" if files else " none yet (they appear after /reload or logout)"))
    for path in files:
        stamp = dt.datetime.fromtimestamp(path.stat().st_mtime).strftime("%d %b %H:%M")
        print(f"  {path.relative_to(client)}  ({path.stat().st_size:,} bytes, {stamp})")


def cmd_install(client: Path, copy: bool) -> None:
    addons = client / "Interface" / "AddOns"
    addons.mkdir(parents=True, exist_ok=True)
    for name in ADDONS:
        link, target = addons / name, REPO / name
        if is_link(link) or link.exists():
            remove_install(link)
        if copy:
            shutil.copytree(target, link)
            print(f"Copied    {name}")
        else:
            make_junction(link, target)
            print(f"Junction  {name} -> {target}")
    print("Done. Restart the game client (a /reload is not enough for new add-ons).")


def cmd_uninstall(client: Path) -> None:
    for name in ADDONS:
        path = client / "Interface" / "AddOns" / name
        if is_link(path) or path.exists():
            remove_install(path)
            print(f"Removed   {name}")
    print("Saved files under WTF were left alone.")


def cmd_collect(client: Path) -> Path | None:
    files = saved_files(client)
    if not files:
        print("No saved files yet. In game: /reload (or log out), then run collect again.")
        return None
    out = RESULTS_DIR / dt.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    for path in files:
        dest = out / path.relative_to(client / "WTF" / "Account")
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        print(f"Collected {dest.relative_to(REPO)}")
    print(f"Saved in {out.relative_to(REPO)} (git-ignored). Tell Claude the beta run is collected.")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("status", "install", "uninstall", "collect"))
    parser.add_argument("--wow-root")
    parser.add_argument("--client", default=DEFAULT_CLIENT)
    parser.add_argument("--copy", action="store_true", help="install by copying instead of a junction")
    args = parser.parse_args(argv)
    root = find_wow_root(args.wow_root)
    client = client_dir(root, args.client)
    if args.command == "status":
        cmd_status(root, client)
    elif args.command == "install":
        cmd_install(client, args.copy)
        cmd_status(root, client)
    elif args.command == "uninstall":
        cmd_uninstall(client)
    else:
        cmd_collect(client)
    return 0


if __name__ == "__main__":
    sys.exit(main())
