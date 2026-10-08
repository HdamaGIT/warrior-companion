# Warrior Workshop

A World of Warcraft: Forever add-on for a warrior main (mining and blacksmithing, with engineering to come). It answers one question:

> *What is the cheapest next step that makes me stronger and levels my professions?*

v1 will provide an inventory cache, a profession recipe cache, a skill-up planner, a crafted-gear advisor and a readiness panel. All of it runs out of combat. The full specification is in [`docs/SPEC.md`](docs/SPEC.md).

## Status

| Milestone | State |
|---|---|
| M0 Scaffold | Built. Awaiting in-game load test ([checklist](docs/verification/M0.md)) |
| M1 Probe | Built. Awaiting a beta run before 21 Oct 2026 ([checklist](docs/verification/M1.md)) |
| M2+ | Not started |

At the moment the add-on only loads and responds to `/ww version`.

## Repository layout

| Path | Contents |
|---|---|
| `WarriorWorkshop/` | The add-on, junctioned into `Interface\AddOns\` |
| `WarriorWorkshopProbe/` | Phase 0 throwaway add-on that probes the Forever API |
| `tests/` | busted unit tests (Lua 5.1) |
| `docs/` | Spec, decisions, handoff, probe results, verification checklists |
| `tools/analysis/` | Placeholder for the v2 Python pipeline |

## Development

See [`docs/DEV_SETUP.md`](docs/DEV_SETUP.md) for the Windows junction setup, the `/reload` loop and optional local tooling. CI runs `luacheck .` and `busted` on Lua 5.1 for every push.

Working rules for Claude Code live in [`CLAUDE.md`](CLAUDE.md). Session state is kept in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## Licence

MIT. See [`LICENSE`](LICENSE).
