---
name: crowdfx-system
description: Owner's crowd sound library (75 sounds) is in Studio at ArenaOne.ArenaSoundFX.CrowdFX/<Group>/<Category>; requirements for the procedural crowd system and anthem crowd/drum tracks
metadata:
  type: project
---

2026-10-03: the owner's crowd audio is on disk at `D:\SKYLARK\CROWDFX` (category folders; `CROWDFX.txt` describes the categories). I renamed the files to `Group_Category_NN`. The owner bulk-imported them; they now sit in Studio at `workspace.argoniaonion.ArenaOne.ArenaSoundFX.CrowdFX/<Group>/<Category>/<Sound>`:
- Groups: Base, Small, Medium, Major, Sustained, Chant.
- 74/75 loaded; `Base_CrowdLow_01` did not load (moderation or failed upload).
- Spatial emitters: 9 `CrowdFX` parts, long strips along the stands at y≈131.

**Why:** the owner wants a PES/FIFA/WWE-style crowd:
- spatial along rows, not point emitters;
- procedural: loops, fades, one-shots;
- sections stick with a team for the whole match;
- not too loud, smooth transitions;
- loads from the CrowdFX folder so the owner can reorganize or replace sounds;
- a system toggle in the Arena System orchestrator menu;
- simple first, polish later.

**How to apply:** build the loader to read that folder tree, never hardcoded IDs. The owner also asked that the anthem's crowd and drum tracks (`Anthem.ANTHEM1_CrowdFX`, `ANTHEM1_DrumFX`, and any future anthem's `_CrowdFX` / `_DrumFX`) play through the crowd emitters like the other crowd FX, not from the ArenaGlobe speaker ("sounds weird").

Batch order agreed: camera, drone and arena-system fixes, then crowd FX, then procedural arena generation.

Progress (2026-10-03):
- Pass 25 (`f8eebdc`) finished the fixes batch.
- Pass 26 (`b2f9ca6`) built the crowd in `ServerScriptService.ArenaCrowdManager`:
  - tunables in `ArenaConfig.CrowdFX`; toggle `DefaultToggles.CrowdFX` (on);
  - anthem CROWD/DRUM stems routed to each section's `CrowdStem` in `ArenaAudioManager.playAnthem`;
  - test hook: Workspace attribute `CrowdDevCommand` (`winner X` / `react <Team|all> <Category>`); telemetry attribute `CrowdFXState`; each part shows its side as `CrowdTeam`.
- Pass 26b (`185a62b`) added live CROWD MIX sliders to the Arena System panel. They don't save; the server prints a `[ArenaCrowd] Mix (paste into ArenaConfig.CrowdFX...)` line to copy into config. Workspace attribute `CrowdFXLevels` holds the current mix.
- Loudness still needs tuning by the owner's ear. There are no boo sounds yet (AngryCrowd stands in).
- Next: procedural arena generation; drive it through `ArenaScreen.setGenerationProgress(fraction, stage)`.

Related: [[studio-git-export]]

Pass 29: server Sounds report TimeLength 0 until loaded. Never filter templates by TimeLength on the server: that silenced the whole crowd. A loop that hasn't loaded after `LoadTimeout` marks its template bad instead.
