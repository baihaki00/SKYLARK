# Pass 26: procedural spatial crowd FX

Owner request: a PES/FIFA/WWE-style crowd.
- Spatial rows along the 9 `CrowdFX` stand parts, not point emitters.
- Procedural loops, fades and one-shots.
- Sections cheer or boo for a team and stick with it until the arena ends.
- Not too loud, with smooth transitions.
- Loads from the CrowdFX folder.
- A toggle in the Arena System menu.
- Anthem `_CrowdFX` / `_DrumFX` stems come from the crowd, not the ArenaGlobe speaker.

## What was built

**New `ServerScriptService.ArenaCrowdManager`.** It was created with the MCP `multi_edit` tool; `execute_luau` can't parent scripts into ServerScriptService.

**Library.** Built at runtime from `Workspace.argoniaonion.ArenaOne.ArenaSoundFX.CrowdFX/<Group>/<Category>/<Sound>`.
- Config names categories only, never sound ids, so the owner can swap or add sounds.
- Sounds that failed to load (`TimeLength` 0) are skipped.

**Sections.** Each stand part named `CrowdFX` gets 2–6 emitter attachments spread along its longest axis (one every 110 studs), plus a centre `CrowdStem` attachment for anthem stems. Each emitter carries:
- **bed:** a murmur loop on every emitter (`Base/*`);
- **mood layer:** on every other emitter (`Sustained/*` or `Chant/ChantBed`);
- **one-shots:** reactions on a random emitter of the section.

Every sound gets a random start point and ±4% pitch, so copies never phase. All loop changes crossfade over 2.5 s.

**Allegiance.** Assigned when the fighters teleport in, kept until the match ends.
- Sections are sorted by angle around ArenaGround and split into two contiguous arcs of about equal row length.
- The arc nearer a team's fighters backs that team.
- In FFA every section is neutral.
- Each part shows its side as the `CrowdTeam` attribute.

**Moments.** Driven by fighters' `HealthChanged`, `CurrentState == "Knockback"` and the `QuinEliminated` BindableEvent. Combat code is untouched.

| Moment | Backing sections | Other side |
|---|---|---|
| Light hit (10%) | ScatteredCheer | – |
| Heavy hit, at least 2% of MaxHealth (45%) | MediumCheer | SmallGroan |
| Knockdown (80%) | MediumRoar | ShortGasp |
| Elimination | HugeCheer | MassiveDisappointment, then AngryCrowd (boo) for 8 s |
| Winner | MassiveCelebration plus Celebration layer | MassiveDisappointment, then Calm |
| Draw | MassiveShock | MassiveShock |

- Minor reactions are rate limited: 0.5 s apart stadium-wide and 3 s per section.
- One-shots are capped at 12. At the cap a minor one is dropped, and a major one fades out the oldest one-shot to make room.

**Excitement.** Each team has an excitement level (0..1).
- It rises with that team's hits and decays to 0.3.
- It picks the mood layer: Calm, then Excited above 0.55.
- Once either team is down to its last fighter, the layer switches to Tense and the bed to CrowdTense.
- **Chants:** every 22–40 s a team, weighted by excitement, chants for 9–15 s: a ChantBed layer plus a ShortChantPhrase.

**Phases.** Each arena phase has a bed and level (`ArenaConfig.CrowdFX.Phases`).
- Cues: applause at open, cheer at teleport, HugeRoar at kick-off, applause at post-game.
- The crowd sits low under the anthem.

**Anthem.** In `ArenaAudioManager.playAnthem`, stems whose name contains CROWD or DRUM are played from every section's `CrowdStem`.
- The scale is `AnthemStemScale` (0.45), with crowd roll-off.
- The ARIA stem stays on the ArenaGlobe.
- Ducking and stopping still work, because every copy is in `activeAnthemStems`.

**Mixing and ducking.** The crowd plays through `ArenaCrowdChannel` (under ArenaSpeakerGroup, so Master applies). It dips to 75% while ARIA speaks.

**Toggle.** "Procedural Crowd FX" in the Arena System panel (`DefaultToggles.CrowdFX` = true). It switches live: off fades everything out, and on resumes with the same allegiances.

**Studio test hook.** The Workspace attribute `CrowdDevCommand` accepts:
- `winner TeamAlpha|TeamBeta|Draw`;
- `react <Team|all> <Category>`.

The `CrowdFXState` attribute shows phase, loops, one-shots, excitement and chant.

All tunables live in `ArenaConfig.CrowdFX`.

## Measurements (Play)

- **Library:** 75 sounds loaded, 9 sections, 22 emitters.
- **Beds:** 22 loops through the opening phases, crossfading CrowdMedium → CrowdLow at the prep room.
  - PRE_GAME and IN_GAME: 33 loops (beds plus mood layers).
  - Client: 37/37 crowd sounds playing and loaded.
- **Allegiance (4v4):**
  - Alpha (spawn at (−151, −244), north-west): the east stand plus the two north-west rows, 760 studs of row.
  - Beta (spawn at (144, −616), south-east): the 4 south rows plus the two south-west rows, 698 studs.
- **Anthem:** 2 stems (crowd, drum) on each of the 9 sections; only `ANTHEM1_ARIA` on the globe.
- **In game:**
  - Excitement moved 0.30 → 0.66 → 0.97 with the hits.
  - Chants alternated between the teams; Beta's 6 sections ran ChantBed while Alpha's 3 ran ExcitedCrowd.
- **Elimination (killed a Beta fighter):** Alpha's 3 sections played HugeCheer; Beta's 6 played MassiveDisappointment, then AngryCrowd.
- **Winner:**
  - First run: the winner cue was lost, because the 12-slot cap was still full from the previous big moment.
  - After the fix: `winner TeamBeta` fired 2 s after kick-off and played MassiveCelebration on all 6 Beta sections and MassiveDisappointment on all 3 Alpha sections, while the oldest roars faded.
- **Toggle (clicked in the panel):** off took 34 sounds to 0; on brought back 33 loops with the same sides.
- **FFA (6):** 9/9 sections Neutral, excitement 0.80, whole-stadium chant.
- **Stop:** every crowd sound removed after the fade.
- **Regression:** Arena match to IN_GAME, 0 errors; 16v16 (`team:16`), 32 Quins, 0 errors in 40 s.

## Notes for the owner

- **Loudness:** I can't measure it from Studio, so tune by ear in `ArenaConfig.CrowdFX`. The main knobs are `Volume` (whole crowd), `BedVolume`, `LayerVolume`, `ReactVolume`, `MajorVolume` and `AnthemStemScale`.
- **No boo sounds in the library:** booing uses AngryCrowd plus groans. Adding a `Boo` category folder and pointing `Moods.Angry` or `Reactions.*.Against` at it is enough.
- **Pass 25 audit correction:** the drone label modes are `"on"` / `"fade"` / `"off"`, not "show"/"hide".

## Pass 26b: live crowd mix sliders

Owner request: sliders in the Arena System panel for the whole crowd and each category.

- **Panel:** a new **CROWD MIX (LIVE)** card under AUDIO ACOUSTICS (`ArenaController` section 4b) with 8 sliders:

  | Slider | Config key |
  |---|---|
  | Crowd (Whole) | `Volume` |
  | Murmur Bed | `BedVolume` |
  | Mood Layers | `LayerVolume` |
  | Chants | `ChantVolume` |
  | Reactions (Hits) | `ReactVolume` |
  | Big Moments (KO, Win) | `MajorVolume` |
  | Anthem Crowd & Drums | `AnthemStemScale` |
  | Crowd Under ARIA | `DuckMultiplier` |

  - `createSliderRow` now takes an optional container, state table and change callback, so the crowd card reuses it.
  - The playlist sections moved down two layout slots.
- **Path:** the sliders send `{Crowd = {...}}` through the existing `UpdateAudioSettings` remote. `ArenaAudio.updateAcoustics` passes it to `ArenaCrowd.setLevels`, which clamps the values and writes them into the live `ArenaConfig.CrowdFX`.
  - The whole-crowd level applies at once, and keeps the ARIA duck.
  - Loops follow on the next director step (1.5 s fade); one-shots use the new level from their next play.
  - Anthem stand stems that are already playing follow the Anthem Crowd & Drums slider live (base weight kept per sound).
- **Saving:** values aren't saved. 1.5 s after the last change the server prints `[ArenaCrowd] Mix (paste into ArenaConfig.CrowdFX to keep): Volume = ...`.
  - The current mix is also in the Workspace attribute `CrowdFXLevels`, and a panel opened later starts from it.
- **Test (Play):**
  - Clicked Murmur Bed to 0.60 and Crowd to 0.50.
  - The server showed `CrowdFXLevels` with BedVolume 0.6 and Volume 0.5, and printed the paste line.
  - Prep-room beds settled at 0.42 (0.60 × level 0.7).
  - The crowd channel was at 0.38 (0.50 × 0.75 duck) while ARIA spoke.
  - 16v16: 32 Quins, 0 errors.
