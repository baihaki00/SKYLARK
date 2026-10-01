# Pass 16 (batch 2 of the 2026-10-02 list): whole-body tilt, directional gait, reachability, hurdles

Backup: `ServerStorage.backup_pre_16v16audit16_20261002`. Base: pass 15 (`f115c80`).

## Owner requests in this pass
- Skid-over clip replaced by `82934009896094`.
- Whole-body tilt "like Tales Runner / Watch Dogs 2". The owner then said the running tilt is "top notch, never break it", and asked that it be switchable.
- Check the strafing animations ("6 of them, only work at certain angles").
- Batch 2 of the list: locomotion re-audit on MovementTestArena (#2, #3, #7, #8, #9, #10, #13 partly, #17, #18).

## 1. Skid-over clip
`Parkour.SkidOverOB` now uses `82934009896094`. Pose lab: loads (1.2 s), faces forward (hips +0.98..+1.00), in place (hips rise 1.6 studs mid-vault, feet lead, no drift). Time-scaling to the obstacle length stays in batch 3.

## 2. Whole-body tilt (ProceduralCombatReactionController 4c)
- **What it does:** the whole body turns about a point on the ground under the root by the lean a runner needs for the acceleration it is under, atan(|a| / g) × `BodyTilt_Scale` 0.6, capped at 16°. A run lean up to 7° grows with speed above 8 studs/s.
  - The acceleration is the controller's smoothed velocity derivative, so turns lean into the curve, a start leans forward and braking leans back.
- **When:** smoothed at 7/s; fades below 4 studs/s; off in the air, Knockback, Recovery, ProjectileJump, MidAirClash, WallRun, BeamStruggle and PlatformStand.
- **Order:** applied after the hips layer and before the leg solver, so the feet stay planted.
- **Switches:** `CombatConfig.BodyTilt_*`; workspace `BodyTilt` = live on/off.

| | tilt off | tilt on |
|---|---|---|
| body lean from vertical, moving > 10 studs/s (median) | 20° | 27° |
| shuffle (two runs) | 10.0-10.4% | 4.8-6.3% |
| head spikes, median Quin per 1000 | 3.1 | 2.7 |

- **Measurement note:** spike counts are dominated by a few Quins in a few windows. Bucket totals swung 4 → 42 between runs for the same setting, so A/B now compares the **median Quin**.
- **Neck/head springs (pass 15):** confirmed jitter with this method (median 4.4 vs 2.7, one Quin at 138/1000). They stay off.

## 3. Strafes and directional gait (GaitModule)
Pose lab of the six clips (Left/Right × Run/Walk/Tired): all in place (hips fixed, feet step ±2.6 studs sideways), all travel the right way, none inverted.

The problem was selection:
- **Circling** used them only within 35° of straight sideways, turning the body so the motion was exactly sideways.
- **No other state** used them. Fight footwork, step-backs and sidesteps ran the forward cycle sideways or backwards (crab running).

Fix:
- **GaitModule** picks by the angle between the motion and the facing:
  - under 50°: forward;
  - 50-130°: Strafe Left/Right (Run above 10 studs/s, else Walk), rate = sideways speed ÷ authored speed;
  - over 130°: backpedal, the forward cycle played at negative rate (no backward clips exist).
  - 10° hysteresis between bands; the forward loops idle at ~0 weight under a strafe to keep their phase.
- **Ownership:** the gait's own strafe track is not "foreign locomotion". In Circling the gait stays forward-only (Circling owns the same clips).
- **Circling band:** `Circling_MaxFacingBias` 35 → 60.
- **Switches:** `Gait_Directional`, `Gait_StrafeAngle`, `Gait_BackpedalAngle`, `Gait_StrafeRunSpeed`; workspace `GaitDirectional` for A/B.

| moving > 50° off facing, outside Circling | off | on |
|---|---|---|
| crab running (forward cycle) | 27% | 6% |
| clip on the legs | Sprint 1847 frames | Strafe Left/Right Sprint 785/712 |

## 4. Backward sliding (#3)
- **Cause:** spacing step-backs (ImpulseModule SelfMotion) and hit flinches (Reaction, 2-5 studs) were treated as "being pushed" by the foot solver, so the feet glided.
- **Fix:** ImpulseModule publishes the highest active request priority on the mover (`Priority` attribute). The foot solver now only lets the feet slide for Knockback (priority 3, 10-18 stud skids) and landing skids, and run slides/dashes (`LocomotionAction`) leave the feet to the clip.
- **Result:** moving backwards, feet without a plant for 0.4 s: 9.1% of frames. Sideways: 23.1%, mostly Circling's own strafe; not improved yet.

## 5. MovementTestArena
- **`movement_test` mode:**
  - spawned at stale coordinates (the course was moved); it now uses the course's checkpoint parts;
  - its target only had WalkSpeed 0, which states override, so the runner chased it into the maze; it is now anchored.
- **`SpatialModule.getArenaBounds`** always used the main arena's ground. On the course every Quin was "out of bounds" and the safety net flung it back to the main arena with a cinematic re-entry. It now uses the course ground while `CurrentMode` is MovementTestArena.

### Hurdle line (2, 5, 8, 10, 20, 30, 40, 60, 83 studs)
Before:

| hurdle | what the runner did |
|---|---|
| 2 | full jump from 19 studs out |
| 5 | jumped |
| 8 | ran into it, stopped dead (27 → 0 in a frame), hopped up from a standstill, landed sideways |
| 10-30 | went round |
| 40 | Fight for 50 s against the far side of the wall, 10 studs from a target it could not reach |

Causes:
- Chase jumped as soon as its 22-stud look-ahead saw anything.
- The traversal planner only probes 4 + 0.16 × speed ahead (10 at 40) and plans every vault to land *on top*, so early jumps were refused ("HitsWall" × 10) until the Quin was at the face.

Fixes:
- **Timed takeoff:** the apex is over the obstacle's near face, at takeoff distance = speed × time to apex (clearance 0.8).
- **Thin vs deep:** probing the top 7 studs beyond the face tells thin obstacles from deep ones. Thin ones get a new `hurdle` jump (momentum kept, launched along the velocity, lands beyond); deep ones keep the planner's land-on-top vault at the planner's range.
- **Flight:** the jump's facing lock is softened (AlignOrientation responsiveness 80 → 30).

After: the 2-stud hurdle is taken 6.1 studs out at 40 studs/s and cleared. The rest of the line is gone round (the target is behind the 60/83-stud ones; the route-finding goes round the side).

### Reachability (#7, #13 partly): NavigationModule (new)
- **`isReachable`:** a sweep at +4.5 studs between the two roots (Quins and non-collidables ignored) plus a 7-stud height limit; obstacles below the sweep can be stepped, vaulted or jumped.
- **`detourWaypoint`:** a PathfindingService path (agent 2.5 × 8, can jump), computed in a background thread and refreshed after 1 s or when the target moves 10 studs.
- **Fight** hands over to Chase after 0.5 s of an unreachable target. **Chase** only enters Fight/Circling when reachable, and follows the path ("Going round") while blocked.
- **Seen:** "Going round" from 0.6 s on the course. On a blocked path with the target unreachable by height (on a platform) the pathfinder returns NoPath and Chase keeps its old platform logic (climb / projectile jump).

## Checks
- 16v16: 0 server / 0 client errors; dive oscillation 2/109 forced jumps; state shares normal.
- The one error in the course runs ("Network Ownership API cannot be called on Anchored parts") comes from the anchored test target only.
- Screenshot of the tilt: a running Quin banks into its turn.
- Screen capture timed out for the strafe; not visually verified.

## Not comparable / open
- The shuffle metric now counts flinches and lunges as moving (they were excluded as pushes), so 15.7% here is not comparable with earlier runs.
- Sideways sliding 23% (Circling strafes); diagonal blending (forward + strafe at once) not done: the clips' cycle lengths differ (run 0.47 s, strafe 0.67 s).
- Pacing: the runner walks ("ConfidentWalk") at 7.5 studs/s while more than 45 studs from its target, 35 s on the course. Passive; goes with the face-off work in batch 3 (#13).
- Batch 3: face-offs (#13), platform behaviour (#7, #14), AOE smack-down for arc jumps, skid-over time-scaling.
