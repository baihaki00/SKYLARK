# Pass 21: Circling sideways slide, the Arena System, the globe ring

Base: pass 20 (`88280ce`).

## 1. Sideways sliding in Circling (`a0274a9`)

### Measured
16v16, 40 s, every Quin in Circling. A frame counts as "sliding" when the Quin is moving and has had no clean foot plant for 0.4 s (planted toe still: slip under max(2, 0.15 × speed)).
- Before: **41.8%** of moving frames.
- Strafe-run clips moving straight sideways: about 45%.
- Forward run, jog and walk cycles played while moving sideways: 53-72%.

### Causes
- **Forward drift:** the planted toe was dragged *forward*, not sideways. In body space the body moved about 4 studs/s forward of pure sideways (about 13°), and strafe clips cannot step forward.
  - The orbit curves toward the target all the time.
  - Circling set the facing at 10 Hz from the last tick's velocity, through a 25-responsiveness gyro, so the body was always behind the curve.
- **Travel form:** in Circling's travel form the gait was forward-only (Circling owns the strafe clips), so a body still turning toward its travel ran its forward cycle sideways.

### Fixes
- The strafe facing is led by the orbit's own turn rate × `Circling_FacingLeadTime` (0.25 s), and the gyro is stiffer (`Circling_GyroResponsiveness` 35).
  - The turn rate is smoothed and reset on feint reversals.
  - Mean forward drift: 4.3 → 1.1 and 3.5 → 0.6 studs/s.
- GaitModule's directional gait (strafe/backpedal by real angle) now also runs in Circling's travel form.

### Result
| | Circling sliding |
|---|---|
| before | 41.8% |
| after | **17.3%** |
| Fight (same run, for reference) | 21.6% |
| Chase (same run, for reference) | 20.8% |

0 errors.

## 2. Arena System Orchestrator

### Drift found
Seven arena scripts in Studio no longer matched git (a newer rewrite). They were committed as found first (`e4e8f69`).

### Faults in that version
- **Anthem never played:** the orchestrator called `ArenaAudio.playAnthemGroup`, which does not exist (it is `playAnthem`). The error ended the whole match at the anthem.
- **Other missing calls:**
  - `playIngameMusic` (the function is `playInGameMusic`);
  - `ArenaDroneManager.deployDrones` / `stopDrones` (the functions are `startDrones` / `resetDrones`);
  - `ArenaFireworks.launchCombatBurst`;
  - `ArenaAudio.setChannelVolume`, which every slider move called through a second, broken `UpdateAudioSettings` handler.
  - `playWarhorn` was passed a name as its volume.
- **Panel timings ignored:** the phase durations were hard-coded (Generation 10, Teleport 5, Game 180, Victory 10, Post-game 5) instead of the panel's 15 / 10 / 600 / 8 / 180.
- **Skip was partial:** each wait reset the skip flag, so in the anthem a Skip only ended the lead-in wait and the anthem still played. Skips also left ARIA lines and stems running.
- **FFA:**
  - it called a `getArenaMetrics` that the drone manager does not have, and crashed;
  - its end check (`alphaAlive == 0 or betaAlive == 0`) is always true with no beta team.
- **Panel:**
  - **Section order:** all `LayoutOrder` 0, so the list sorted by name (every Frame before every TextLabel). The section headers piled up at the bottom, team sizes read 1v1 / 16v16 / 2v2…, and the right column lost its headers.
  - **O hotkey:** bound twice (ContextActionService plus a UserInputService fallback), so one press could open and close the window.
  - **Phase badge:** formatted a fractional time with `%d`, which errored on every update, so it stayed on IDLE.
  - **Missing glyph:** the close button "✕" is not in Gotham.
- **Screen:**
  - titles were written before the scene switch, so they landed on the previous phase's scene;
  - the countdown numeral re-pulsed 4×/s.

### Changes
- **Orchestrator (rewritten on the same structure):**
  - Phases: ARENA_OPEN → ARENA_GENERATION → PREPARATION_ROOM → TELEPORTING_QUINS → STADIUM_ANTHEM → PRE_GAME → IN_GAME → WINNER_DETERMINATION → POST_GAME → IDLE.
  - Every duration comes from the panel; defaults are in `ArenaConfig.DefaultDurations`, now including `StadiumAnthem` 60.
  - **Skip ends the whole phase** (an epoch counter checked by every wait). A skipped anthem fades out, and skipped ARIA lines stop.
  - **Globe and screen** ignite at T+5 s of Arena Open (still ignited if Arena Open is skipped earlier).
  - **Anthem** back-timed to end 1 s before its window.
  - **Countdown:** warhorn at T-5, drones at T-4 (Drones toggle); with the Pre-Game Timer off, the countdown is skipped and the warhorn and drones fire at fight start.
  - **Ending:** FFA ends at one survivor. Winner by elimination, else more fighters alive, else health.
  - **Post-game:** music, closing lines, drone outro in the last 15 s, closure, then IDLE.
  - Studio-only test hook: Workspace `ArenaDevCommand` = `start <json>` / `skip` / `stop`.
- **Config:** `ArenaConfig.DefaultToggles.Drones = true`.
- **Panel:**
  - explicit layout order everywhere;
  - one O binding;
  - whole seconds in the badge;
  - FFA sizes shown as Quin counts (2× the squad size);
  - "Procedural Terrain [not built yet]" is read-only (no generator exists);
  - close button "X".
- **Screen:** the countdown numeral pulses only when it changes.

### Verified in Play
- **Full sequence with the panel timings:**
  - globe and screen at T+5.1 s;
  - every ARIA line plays;
  - pre-game music fades at teleport;
  - ANTHEM1 (45 s, 3 stems) plays;
  - warhorn, then drones at T-4, then in-game music;
  - victory ceremony, post-game music, drone outro, closure fade;
  - IDLE with no fighters left.
- **Skips** in Arena Open (before T+5), Preparation Room and Anthem each ended the phase at once.
- **Panel buttons:** START, SKIP and STOP work through the panel itself (clicked), and the badge counts down.
- 0 errors, 0 warnings.

## 3. The ring around the ArenaGlobe (LiveFeedScreen, client)

### Why it looked bad
- **Squashed text:** 32 separate panels each carried a 1920×600 canvas stretched onto a 19 × 36-stud panel, so the text was crushed about 6× sideways.
- **Repeated text:** the same advert was copied on every panel.
- **Motion:** the whole band rolled ±7.5° while it turned.
- **Timing:** it glitch-flickered on together with the globe.

### Now
- **One continuous stadium LED ribbon:** 48 panels, 12 studs tall, cyan neon top rail and gold bottom rail.
- **Canvas:** pixels-per-stud, so nothing is stretched.
- **Ticker:**
  - one message scrolls around the whole ring;
  - each panel shows its own slice, on both faces, and the slices join up;
  - the text is sized so a whole number of repeats closes the loop (`TextSize` is capped at 100 by Roblox; 14 px/stud makes that about 60% of the band).
- **Messages** follow the match phase and cross-fade.
- **Motion:** slow yaw only.
- **Appears 1 s after the globe** (T+6 s of Arena Open) as a light-up sweep around the ring.
- The "✦" separator is not in GothamBlack; it is now "•".

## Open
- "Procedural Terrain Obstacles": no generator exists; the toggle is marked "not built yet".
- The ARIA categories `ARIA_54321GameCountdown` / `ARIA_AnnounceWinner` are filled by the Aria manager's local list; `ARIA_Congratulations` and the team-win lines play from it.

## 4. Follow-up from the owner's screenshots (pass 21c)

### One-frame camera flash onto a flying Quin
- **Cause:** the Quin Manager menu (`MenuController`) had **Action Cam ON by default**.
  - Whenever any Quin entered a MidAirClash, Action Cam set `CameraSubject` to that Quin. SmoothCamera (DEFAULT mode) put the subject back on the player the next frame, so the view jumped to the Quin for one frame and back.
  - When the tracked Quin died, the menu cycled to the next Quin: another flash.
- **Fix:**
  - Action Cam is off by default.
  - Tracking (Action Cam or Q/E in that menu) now goes through the spectator camera (`shared.SpectatedQuin` / `SpectatedQuin` attribute), so it actually follows instead of flashing.
  - The dead-target cycle only runs while the player is spectating.

### "Ghost shirts" at both spawn sides
- **What they are:** T-posed Quin torsos sticking out of ArenaGround.
- **Cause found first (wrong):** the spawn height. Spawning only put the root about 1.5 studs low; `getSpawnPositions` already adds 5. The real cause is in section 5.
- **Fix:**
  - `QuinSpawner.spawn` stands every Quin's root at floor + its standing height, found by ray, for every caller.
  - The orchestrator keeps that height when it turns them to face each other.
  - AIGhostHandler keeps an un-animated body hidden (20 s last resort instead of 3 s).
- **Measured:**
  - Arena System 4v4: all 8 Quins at y 7.43-7.58 on their first frame (standing height).
  - 16v16 and Arena runs: no Quin un-animated or below standing height on the client, 0 errors.
- **Not reproduced:** the buried bodies did not appear in this build's runs, so the fix is to the cause found in the code, not to an observed reproduction.

## 5. The ghosts, actual cause (pass 21d)
- **What the owner saw:** FFA 32, the ghosts appeared mid-game on the spawn ring while the Quins were moving, and never in pre-game.
- **Streaming:** Workspace instance streaming is on, and the Quin models used `ModelStreamingMode.Default`, so their parts stream in and out one by one.
  - With the player away from the fight, the client held **0** of the 24 Quin bodies.
  - A body mesh kept on a client without the rest of its rig is not animated, so it stood frozen in the bind pose (the T-posed torso) where the Quin had been.
  - This explains why the ghosts were never on the server.
- **Fix:** `QuinSpawner` sets every Quin model to `ModelStreamingMode.Persistent`, so the whole model is always on every client as one unit (the drone and spectator cameras need far Quins too).
- **Verified, FFA 32 after 25 s:** the client sees all 32 Quin bodies every frame, each attached to its root and animated: 0 detached, 0 without a root, 0 visible-and-unanimated.

## 6. The ghosts, real cause (pass 21e)
- **Evidence:** the owner's recording (`this one.gif`) shows smooth, untextured, low-poly grey figures in a T-pose, floating and leaning. Two or three appear at once for 2-3 frames, then vanish.
- **Cause:** `ReplicatedStorage.QuinType.QuinMale` had **`LevelOfDetail = StreamingMesh`**. With streaming on, the engine draws a generated low-detail stand-in for such a model (grey, low-poly, built from the bind pose) for the moments when its real parts are not on the client.
  - Section 5 (streaming) was close: the model streaming made the parts come and go.
  - But the visible ghost is the engine's stand-in mesh, not a leftover body part.
  - Section 5's `Persistent` setting alone did not stop it.
- **Fix:**
  - Both templates are set to `LevelOfDetail = Disabled`. This is a property of the place file: **save the place**.
  - `QuinSpawner` sets `Disabled` on every clone, so a re-imported rig cannot bring it back.
- **Not verified:** the stand-ins never showed in Claude's own runs, so the owner needs to confirm.
