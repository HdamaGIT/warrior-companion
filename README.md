# Warrior Workshop

A World of Warcraft: Forever add-on for a warrior main. It leads with a **combat companion** (reactive, upkeep and failure alerts while levelling and on dungeon trash), a **tank announcer** and **gear-set keybinds**, aimed at launch on 4 November 2026. A professions and itemisation "Workshop" (skill-up planner, gear advisor with tank stat sheet, readiness) follows.

Combat features run in the open world and on dungeon trash and suspend in restricted contexts (boss encounters, Mythic+). The full specification is in [`docs/SPEC_V2.md`](docs/SPEC_V2.md); the triaged idea list is [`docs/IDEAS_BACKLOG.md`](docs/IDEAS_BACKLOG.md). [`docs/SPEC.md`](docs/SPEC.md) is the superseded v0.1 spec.

## Status

| Milestone | State |
|---|---|
| M0 Scaffold | Built. Awaiting in-game load test ([checklist](docs/verification/M0.md)) |
| M1 Probe | Built. Awaiting a beta run before 21 Oct 2026 ([checklist](docs/verification/M1.md)) |
| M2 Core | Being extended to SPEC_V2 (schema v2, Context, SpellMap). Awaiting in-game check ([checklist](docs/verification/M2.md)) |
| M3 Probe extension | In progress; must run in the beta before 21 Oct 2026 |
| M4-M9 | Not started (order per D-031: M5, M7, M4, M6, M8, M9) |

At the moment the add-on loads, creates its saved variables and responds to `/ww version` and `/ww debug`.

## Repository layout

| Path | Contents |
|---|---|
| `WarriorWorkshop/` | The add-on, junctioned into `Interface\AddOns\` |
| `WarriorWorkshopProbe/` | Throwaway add-on that probes the Forever API (M1 + M3) |
| `tests/` | busted unit tests (Lua 5.1) |
| `docs/` | Spec, decisions, handoff, probe results, verification checklists |
| `tools/sim/` | Offline client simulator: runs the add-on without the game ([setup](docs/DEV_SETUP.md#7-offline-simulator-no-game-needed)) |
| `tools/analysis/` | Placeholder for the Phase F Python pipeline |

## Development

See [`docs/DEV_SETUP.md`](docs/DEV_SETUP.md) for the Windows junction setup, the `/reload` loop and optional local tooling. CI runs `luacheck .` and `busted` on Lua 5.1 for every push.

Working rules for Claude Code live in [`CLAUDE.md`](CLAUDE.md). Session state is kept in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## Licence

MIT. See [`LICENSE`](LICENSE).
