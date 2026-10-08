# Decision log

Entries here override `docs/SPEC.md`. Add new decisions with the next D-number. Never renumber.

| ID | Date | Decision | Rationale |
|---|---|---|---|
| D-001 | 2026-10-08 | The add-on lives in a subfolder of a mono-repo, alongside the probe, tests, docs and tools. | Supports the v2 Python tooling and Phase 0 without separate repos. |
| D-002 | 2026-10-08 | All WoW API access goes through `Core/Adapter.lua`. | Contains API drift; gives tests a seam for mocking. |
| D-003 | 2026-10-08 | No external libraries (Ace3 etc.) in v1. | Fewer dependencies during an unstable beta. Revisit for the v2 config UI and comms. |
| D-004 | 2026-10-08 | v1 runs entirely out of combat; the UI hides on entering combat. | Secret values and encounter restrictions; Blizzard policy risk. |
| D-005 | *pending* | Interface number and client folder name. | To be filled in from the probe (V-01). |
| D-006 | 2026-10-08 | M0 ships a minimal `Core/Adapter.lua` (`GetBuildInfo`, `GetAddOnVersion`, `Print`) instead of calling `GetBuildInfo` from `Init.lua`. | `/ww version` needs build data, and D-002 forbids data API calls outside the Adapter. M2 extends this file rather than replacing it. |
| D-007 | 2026-10-08 | The probe records an event argument's **value** (by plain assignment, with no operations on it) only when a secret checker exists and reports the value as not secret. Otherwise it records type and secret status only. | Type alone cannot answer V-07 ("readable spellID") or V-09 ("is the tag readable"). Storing a value that has been confirmed non-secret cannot error. If no checker exists, that is itself the V-10 finding. |
| D-008 | 2026-10-08 | The probe wraps every `RegisterEvent` in `pcall` and records which registrations succeeded. `UNIT_SPELLCAST_SUCCEEDED` is registered for `player` only. | Mainline errors when an add-on registers an unknown event, so a failed registration is an existence check. Unfiltered spellcast events would flood SavedVariables with casts from party members and nameplates. |
| D-009 | 2026-10-08 | The probe registers the `WWPROBE` add-on message prefix at load. It sends `[WW:PING]` on `INSTANCE_CHAT`, `RAID` or `PARTY` as appropriate, and listens to the `*_LEADER` and `INSTANCE_CHAT` variants too. | Without these the V-08/V-09 comms test could fail silently: unregistered prefixes are not delivered, group-finder dungeons use instance chat, and the leader's lines arrive as `*_LEADER` events. |
| D-010 | 2026-10-08 | Files for later milestones exist as comment-only placeholders and are **not** listed in the `.toc` until implemented. | Satisfies the Section 4 structure without loading dead code. A test checks that every file the `.toc` lists exists. |
