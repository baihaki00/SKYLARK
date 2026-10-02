# Pass 17 (batch 3 of the 2026-10-02 list): face-offs, high platforms, smack-down, skid-over

Backup: `ServerStorage.backup_pre_16v16audit17_20261002`. Base: pass 16 (`834baf9`).

## Owner requests in this pass
- #13 face-offs too long ("fight idle, staring, no punches landed")
- #14 on high platforms: walk around, back and forth, jog in circles
- #7 stuck below a platform running in circles when the enemy is on it
- AOE smack-down `71743026406362`: arc jump (style 1) only, time-scaled to the flight and landing
- Skid-over `82934009896094`: a parkour move over a 5x3 OB, also for lengths beyond 5-7 studs, time-scaled

The body tilt (client 4c) and the foot/hips layers were not touched.

## 1. Face-offs (#13)
### Measured
Circling runs are short (median 1.1 s, max 3 s), and the median idle gap between exchanges is 0.12 s. Neither is the face-off. The distance histogram of close fighting peaked at 9 studs.

| close fighting (Fight, target < 15 studs) | before | after |
|---|---|---|
| standing 9-10.3 studs from the target, not attacking | 21% | 2-3% |
| longest such stand | 11.3 s | 0.66 s |

### Cause (FightState)
The approach stops at `idealRange + 0.3` (8.5) and only restarts past `idealRange + 2` (10.2). Strikes are only thrown inside `Combat_StrikeRange` (9.0). A Quin 9-10.2 studs out wanted to strike, could not, and did not close: two of them stood facing each other.

### Fix
A strike that is out of range now sets `closingGap`, so the Quin steps in.

### Pacing (ChaseState)
`WalkThenSprint` walked until 65 studs from its target and `ConfidentWalk` until 45. From across the arena that is up to 18 s at 7.5 studs/s, staring at the target. A stalk walk now lasts at most `Chase_StalkWalkMaxTime` (2.5 s); then the chase commits to a run. Measured max stalk walk: 2.56 s.

### Strike telemetry
Every strike now writes `StrikeResult` (Hit / Blocked / Dodged / Whiff / Interrupted) and `StrikeSeq` at its impact frame. Whiffs with nothing in the hitbox also write `StrikeMissDist`.

16v16: Hit 62%, Interrupted 18-21% (hit during its own wind-up), Whiff 12-15%, Blocked 5-6%.

## 2. High platforms (#14): OverwatchState routines
### Measured
On high platforms, Quins were in Overwatch ("Holding high ground") at speed 0 for 10-25 s. On narrow (7-stud) platforms pointing at the enemies, every lookout clamped to the same end point. The Quin "arrived" at once and paused again for the whole watch.

### Fix
Each leg now picks a routine:
- **loop:** jog (`Overwatch_JogSpeed` 14) 1-2 laps of an ellipse one stud inside the edge inset. Only where the top has `Overwatch_LoopMinRadius` (4) of room; chance 0.2 + 0.3 × mobility.
- **pace:** walk end to end along the long axis 2-4 times, turning at a different spot each time, 0.3-0.9 s stop at each turn.
- **lookout:** as before (edge facing the enemies). If that point is under 5 studs away, the Quin looks from where it is and then plans something else.

`ObstacleAwareness` shows the routine.

| Overwatch time | stand | walk | jog |
|---|---|---|---|
| before | ~100% | 0 | 0 |
| after (two runs) | 26% | 33% | 41% |

Six dives off the platform; no falls seen.

## 3. Under a platform (#7): CirclingState reachability
### Measured
Quins on the ground with their target on a platform above spent 15-30 s per minute in **Circling**, orbiting underneath. Circling never checked reachability: pass 16 added it to Fight and Chase only.

### Fix
Circling hands over to Chase after 0.5 s of an unreachable target (`NavigationModule.isReachable`). Chase climbs up, finds a way round, or projectile-jumps.

### Result
Circling under a grounded target on a platform: longest run 1.0 s. The remaining Circling under a raised target is under knocked-up or jumping targets.

## 4. Arc-jump smack-down
- **Asset:** `Attacks.Specials.ProceduralSmackDown` now uses `71743026406362`; it had an older id. KeyframeSequence markers: ProjectileJump (takeoff) 0.53 s, BodyLanding 1.20 s, end 2.73 s.
- **Pose lab:** in place, not inverted (the head stays ahead of the root and comes down forward into the smash).
- **When:** `ProjectileJump_SmackDownChance` (0.5) of arc jumps (style 1, not point jumps) fly it instead of a Ninja/Standard kit.
  - The clip starts at the takeoff frame.
  - Every physics frame (in the per-frame guard), its rate = (1.20 − time position) ÷ time to touchdown (from height above the floor and vertical speed), clamped 0.15-2.5. The BodyLanding frame meets the touchdown whatever the arc.
  - At Impact the clip plays on at 1× as the landing. RecoveryState uses it (`LandingClipPath` / `LandingClipRemaining`) instead of a random slam-landing clip.
- **Seen:** landing at time position 1.21-1.27; the landing ran 1.39 s in Recovery and handed back to Fight. A Quin hit at landing went to Knockback and the clip stopped cleanly.

## 5. Skid-over
- **Not used before:** `Parkour.SkidOverOB` was not played anywhere. Its markers: Hands 0.6 s, Footsteps 0.6 / 0.97 / 1.1 s.
- **ChaseState:** obstacles up to `SkidOver_MaxRise` (4.5) high, at 14+ studs/s, are crossed in one speed vault.
  - The top is probed every 1.5 studs for the far edge (up to `SkidOver_MaxLength` 16).
  - The flight is solved to clear the height + 0.8 at **both** edges with the apex over the middle: T² = (L/v)² + 8(h+0.8)/g.
  - Takeoff and landing are each (vT − L)/2 from the edges. Arcs above `SkidOver_MaxFlightRise` (9) fall back to the planner's vault.
  - Chase updates at 10 Hz (4 studs a tick at 40 studs/s), so the takeoff is scheduled with `task.delay` to the exact distance.
- **LocomotionModule `skidover`:** launches along the velocity like a hurdle.
  - The clip's airborne part (0.08 → 0.97 s) is fitted to the flight: rate 0.5-2.6.
  - On first use, before the asset has loaded, the clip is moved to where it should be once it arrives.
- **MovementTestArena, 3-stud-high box:**

| length | takeoff before face | feet clearance | landing past far edge | clip at touchdown |
|---|---|---|---|---|
| 5 | 5.5 | 4.5 | 15 (lag of the floor probe) | 1.20 |
| 12 | 3.5 | 1.5 | 4.9 | 0.97 (footstep frame) |

  - The first 12-stud try, with the apex over the middle only, clipped the near edge. That led to the both-edges solve and the timed takeoff.
  - 16 studs: the runner kept being routed sideways by the navigation detour in this test setup; not verified.
- **16v16:** 7 natural skid-overs in 50 s.

## Checks
- 16v16 (several runs): 0 server errors. One error only in MovementTestArena runs: the known "Network Ownership API ... Anchored" from the anchored test target.
- State shares normal.
- **Test artefact, not a bug:** a runner teleported into an 83-stud block lay prone and looped Chase ↔ Recovery.

## Open
- Navigation detour paths are not invalidated when the Quin is displaced (teleport, long knockback). The 1 s refresh covers most cases.
- Interrupted strikes (~20%) are trades: both swing, one lands first. Untouched.
- Sideways sliding in Circling (23%), diagonal gait blending and the Survey/FightIdle shared track remain from pass 16.
