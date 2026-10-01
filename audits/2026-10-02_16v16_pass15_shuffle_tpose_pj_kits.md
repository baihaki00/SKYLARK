# 16v16 pass 15 (batch 1 of the 2026-10-02 list): shuffle, T-pose, frozen strikes, projectile jump kits, head/spine

Backup: `ServerStorage.backup_pre_16v16audit15_20261002`. Base: pass 14 (`b84bb7c`).
Owner's full list (18 items + animation changes) is tracked in memory; this pass covers #1, #4 (top priority), #5, #6, #15, #16 and the animation changes except the AOE smack-down and skid-over (batch 3).

## Measuring
Client probes in `PreAnimation` (final pose), 16v16, workspace switches alternated in 10 s blocks in one match.
- **Shuffle:** a Quin moving > 4 studs/s on the ground, not pushed and not in a scripted slide, with neither foot slower than max(1.5, 15% of body speed) for 0.4 s. The first version used a fixed 1.5 studs/s and counted good sprint plants as shuffles (27% → 9.6% once corrected).
- **Winning clip:** the highest-priority track with weight > 0.3. Highest weight is misleading: an idle at weight 1 under a run at Movement priority does not show.

## Causes found and fixed

### 1. Frozen tracks: overlapping hit-stops (AnimationModule.applyHitStop)
- **Cause:** each hit-stop froze every playing track and saved its current speed to restore 50-80 ms later. Two hits within that window saved speed 0 the second time and restored it last, so the track stayed frozen until it ended.
- **Effects:**
  - punches and kicks hung mid-swing (Action4, top priority) for up to 3.9 s, over a running body;
  - the walk/run loops froze too. GaitModule caches the rate it set and never re-set it, so the legs stood still under a moving body.
- **Fix:** one freeze per humanoid; each track's real speed is saved once; only the last hit-stop to run out restores it.
- **Result:** frozen dominant tracks > 0.3 s: 70 → 0 (max 0.20 s).

### 2. Full-body clips played while running (Chase, Fight)
`Rear Threat Glance` and `Target Assessment Survey` are full-body Action2 clips. Played at a run, they froze the legs mid-stride.
- **Fix:** above 6 studs/s (survey: below 4 required) only the head and upper back look back, through a new LookController mode (`GlanceBackUntil`, server time). It looks at the rear threat if known, else over a shoulder, up to 100° with the upper back's share.

### 3. Foot planting at a run (ProceduralCombatReactionController)
- **Cause:** a sprinting clip's planted foot still creeps 4-14 studs/s. The fixed 1.4-stud drift allowance let go halfway through the stance; the foot then either took a procedural step while the clip was about to lift it anyway, or slid until the next lift. Debug sample at contact height: pinned 44%, mid-step 31%, sliding 23%.
- **Fix:** drift allowance 1.4 + 0.04 × speed (3 studs at 40); procedural steps only below 12 studs/s (they exist for stance clips that never step).

### 4. Turn rate from sideways grip (LocomotionModule.resolveGroundIntent)
- **Cause:** turn ceiling was 14 rad/s at a jog and 5.5 at a sprint, i.e. 200-380 studs/s² sideways.
- **Fix:** turn rate = min(previous ceiling, `Locomotion_LateralGrip` 90 / speed), so 2.2 rad/s at 40 studs/s and 9 at 10. Reversals still use the skid plant.
- **Result:** measured sideways acceleration p50 20, p90 116, p99 190. The upper tail is mostly collisions between Quins, wall deflection and per-frame velocity noise (2° at 60 Hz reads as ~85 studs/s²), so the shuffle effect could not be isolated.

### Shuffle result (one match, FootPlant off/on blocks)

| | shuffle (moving frames) |
|---|---|
| foot planting off (clip only) | 30.4% |
| foot planting on | 11.4% |

- **Remaining:** mostly the run clip in Chase/Fight during speed changes and turns.
- **Caveat:** before/after this pass is not one clean number, because match windows differ (9.6% → 9.2-11.4% across runs).

## 5. T-pose (#1)
Two sources:
- **At spawn:** every Quin showed its bind pose for 0.1-0.3 s before the first clip loaded. AIGhostHandler now hides a new Quin (`LocalTransparencyModifier`) until a clip with weight > 0.5 drives it, at most 3 s.
- **Mid-match, in Circling:** `Target Assessment Survey` (Action2, one-shot) and the fight-idle stance are the same asset id and share one cached track. Playing the survey turned the idle track into a one-shot; when it and a strike faded, nothing was playing at all.
  - Fix 1: a 0.1 s watchdog in GaitModule's ground contract starts the base idle whenever a living Quin has no track with WeightTarget > 0.05.
  - Fix 2: Circling is no longer excluded from the gait base-layer fill (its strafe clips already block the fill while they play).
- **Result:** visible no-pose frames 758 → 156 per ~150 s match. These are now gaps of under 0.1 s.

## 6. Projectile jump

### Dive oscillating up/down (#5)
- **Cause:** the aim point's floor ray was 35 studs long. Under an airborne target or a tall platform it hit nothing, and the aim fell back to the target's own height. The dive (re-aimed at 480-550 studs/s at 10 Hz) then went up past the target, down, up again.
- **Fix:** the ray reaches the floor (Quins and non-collidable effects excluded), and dive directions always descend (slope ≥ 0.3).
- **Result:** oscillating jumps 6/109 → 4/186. The rest: a curved dive (style 5) at a target in a mid-air clash, and the plain arc bouncing.

### Facing the trajectory (#6)
Per-frame `AlignOrientation` target in the flight guard:
- launch/airborne (upright clips) tilt forward into a climb, up to 35°, and lean 11° when falling;
- the dive points head first along the velocity (flying clip, a horizontal pose) and flares back upright over the last ~25 studs.

### Kits
- Each jump picks Ninja or Standard: kit launch clip → kit airborne loop when the launch clip ends → `DiveFly` (120414990498875) for every dive style (the default dive had kept the launch pose).
- Landings: `RecoveryState.SLAM_LANDINGS` = superhero, hard, Ninja landing, Standard landing (random).
- `PJPhase` attribute added for probes and the HUD.

### Inverted clips (owner suspected forward/back swapped)
Pose lab: hips facing vs the idle pose (idle +0.99).
- **All six kit clips face backwards** (−0.8 to −0.97).
- **The Ninja clips' hip translation is ~10× too large:** the landing's crouch dips 46 studs, the jump shifts 4.7 sideways. Rotations are fine; at 1/10 the numbers are a normal deep crouch.
- Fix: `CombatConfig.ClipCorrections` (yaw 180, plus translationScale 0.1 for Ninja), applied on the client to the hips (whole body) before any procedural layer, while the clip has > 50% weight.
- The flying clip faces correctly (head forward). The AOE smack-down faces correctly. The skid-over clip (100662167599815) did not load in Edit mode (length 0) and is unchecked.

## 7. Hook punch removed
- `135206101877204` (played as "Hook Punch" and as "Cornered Desperate Counter") is a re-upload of `118776942028972`: same 37 keyframes, 1.2 s, 2,479 poses.
- Removed from the punch pool and the punch index list; Desperate Counter now uses Cross Right.
- The combo step named "Hook" is only a damage label; its clip is picked from the pool.

## 8. Head turns (#15) and head/spine secondary motion (#16)

### LookController (head turns)
- **Zone split:** head 100% to 30°, then 60/40 with the neck, then 40/30/30. The head jumped back 12° when a target crossed 30°. Now fixed shares: 50% head, 30% neck, 20% upper back.
- **Smoothing:** the exponential lerp started every turn at full speed, and a 1.2° dead zone held then jumped. Now a critically damped spring (11 rad/s) with a 420°/s cap.

### Secondary motion on the torso
Spine (Spine1, Spine2) springs added to the arm layer, caps 5°; neck/head springs 7°. Live A/B with workspace `SecondaryMotionTorso`:

| torso springs | head spikes / 1000 | spine spikes / 1000 |
|---|---|---|
| none | 1.9 | 1.0 |
| spine | 3.2 | 1.7 |
| spine + neck + head | 7.6 | 1.6 |

- Default: spine on, neck/head off (`SecondaryMotion_Neck = false`). The neck/head springs added jitter mostly in Chase; the head moves on LookController's spring instead.

## Checks
- 0 server / 0 client errors in the final runs.
- Kit clips and the flying clip seen playing in forced jumps (Ninja launch/loop, Standard launch/loop, Flying).
- Not visually verified: the kit clips' corrected facing in flight, the head-first dive. A still capture of a 500 studs/s dive was not attempted.

## Debug aids added
- workspace `FootDebug` = true makes each Quin's client presentation write `FootDbg` (why the left foot is or is not planted).
- `PJPhase` attribute.
- workspace `SecondaryMotionTorso`, `FootPlant`, `SecondaryMotion` switches.

## Open (next batches)
- Shuffle still ~10% (run clip in Chase/Fight through speed changes and turns); jog (9 studs/s) and run (29.9) blend between 11 and 18 studs/s with very different strides.
- Dive oscillation 2% of jumps (style 5 curve at mid-air-clash targets; arc bounce).
- No-pose gaps under 0.1 s remain; the root fix is giving `Target Assessment Survey` its own track (it shares the idle's asset id).
- Batch 2: locomotion re-audit on MovementTestArena: 180° turns, backward slide, corners, jumps / small steps, natural input arcs (#2, #3, #8-#11, #17, #18).
- Batch 3: face-offs, platform behaviour, AOE smack-down and skid-over clips (#7, #13, #14).
