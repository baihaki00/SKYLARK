# Chase stop-go ("running in place"): measured, step 1 built

2026-10-29, Studio (QUIN_COMBATV4), 16v16 TeamBattle, server side.

**The owner's report (bookmarks 2-4):**
- "shuffling ... when the animation looks like running, but its still in place".
- "legs are striding hard, but barely no movement".
- "the animation doesnt really resemble the actual movement".

In the bookmarks, Chase speed swings 2 → 27 → 3 → 22 studs/s about every 0.3 s, with a `ReversalPhase` brake and pivot each time, while Movement.Run stays at weight 1.

## Measured

**Reversals** (`LocomotionModule` plant-and-pivot when the wanted direction is more than 115° off the motion): 93 in 50 s across 32 Quins. 27 of them came within 1.5 s of that Quin's previous one.

| State / ObstacleAwareness | Reversals |
|---|---|
| Chase, Going round | 34 |
| Chase, Clear | 23 |
| Chase, backing off for a run-up | 9 |
| Chase, under a platform | 8 |
| Retreat, jumping to high ground | 6 |

Quick repeats came every 0.7-1.3 s. The last leg often ran 130-180° away from the target.

## Cause (step 1)

`NavigationModule.detourWaypoint`:
- A path is planned in the background (`ComputeAsync` in `task.spawn`) from where the body was when it asked.
- Every re-plan (`Nav_PathRefresh`, 1.0 s) starts again at waypoint 2, 6 studs from that old start.
- At a run, the body is already past it, so it turns back for it (a reversal) and turns round again for the next point.

## Built: skip passed waypoints

- A waypoint is skipped when the body is beyond it along the leg to the next one.
- Switches: Workspace `NavSkipPassedOff = true` (off), `CombatConfig.Nav_SkipPassedWaypoints`.

**A/B** (10 s windows, 100 s):

| | Off | On |
|---|---|---|
| Reversals per 50 s | 75 (90/min) | **35 (42/min)** |
| … while Going round | 23 | **6** |
| Repeats within 1.5 s | 25 | **6** |
| Chase, more than 25 studs from the target, under 8 studs/s | 40% of frames | 36% |

No script errors.

## Still open (step 2): slow chasing with a Run pace

In 40 s, 30% of far-chase frames were under 8 studs/s with `PaceGear` Run, but Humanoid WalkSpeed was 0-5:

| Group | Frames |
|---|---|
| `PaceReason` TargetDown | ~600 of 3,422 |
| Sprint with WalkSpeed 0: Going round / Clear / stepping stone / turning to the run-up / sliding under a gap / no room to stand | ~1,000 |

Next: find what hands the driver a target speed of 0 while Chase asks for a run:
- landing hold (`LandingHoldUntil`);
- the Chase target speed for a downed target;
- the climb, run-up and slide waits;
- `cancelSteer`.

Each fix gets a switch, then re-measure the slow-chase share.

Also seen: route dispersion in `ChaseState.Steer` offsets the target 16 studs along the Quin's own `RightVector`, which swings with its facing. Suspected in the "Clear" reversals; not measured.

## Step 2 (2026-10-29): where the slow far-chase frames come from

A probe on the LocomotionModule driver and on each `return` in `ChaseState.update` (Workspace `LocoDebug`), 45 s of a 16v16. Chasers more than 25 studs from their target, under 8 studs/s: 2,904 of 7,743 frames (37%).

| Group | Frames | What it is |
|---|---|---|
| Asks for walking speed (7) | ~1,350 | `shouldWalk`. By `PaceReason`: **TargetDown ~780**, CasualDrop ~220, Stalk WalkThenSprint ~160 |
| Asks to run, driver brakes | ~380 | landing hold ~260, reversal brake/pivot ~170 |
| Asks to run, still slow | ~460 | blocked (WalkSpeed ≥ 10, not moving) ~260; ramping up ~200; strafe cap in about half |
| Steer expired | ~700 | Chase returns before `Steer.update`: run-up turn (309), stepping stones and climbs (301/309), slides (250), Fight/Circling hand-offs (683/685); or Chase not ticked for >1 s |

**TargetDown was the biggest single cause.** A chaser walked at 7.5 studs/s to any downed target, from any distance. From 25-60 studs, the target was up long before it got there.

## Fix: walk to a downed target only on the last stretch

- `ChaseState`: the TargetDown walk now applies only within `CombatConfig.Chase_TargetDownWalkRange` (22 studs). Further away, the chaser runs.
- Switch: Workspace `TargetDownFarRunOff = true` (walks from any distance, as before).

**A/B, two runs, 10 s windows, 40 s + 50 s:**

| | Off | On |
|---|---|---|
| Far chase with a downed target, under 8 studs/s | 39% / 64% | **4% / 21%** |
| All far chase under 8 studs/s | 29% / 32% | **13% / 22%** |

No script errors.

## Still open

- Blocked bodies: WalkSpeed ≥ 10 but not moving. Probably the "shoves into obstacles/enemies" the owner sees; needs its own look.
- Landing hold and reversal brakes in far chase (~380 frames).
- Chase exits before steering on run-up turns and stepping stones.
- CasualDrop and WalkThenSprint walks are by design. They're left as they are.
- The `LocoDebug` probes (LocomotionModule driver, ChaseTick, SteerTick) stay in, gated by the attribute.
