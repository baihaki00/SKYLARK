# Pass 55: Wall run - wall-side bug, firmer arc, feet and hand on the wall

The owner asked to fix the wall-side bug found in Pass 54. They also said the wall run "still looks funky, not physically accurate and slow", and asked for IK on the arms so the hand looks like it is touching the wall.

## Findings

1. **The wall-side bug.** When `SpatialModule.detectWallRunSurface` failed at the start of a run, `WallRunState.enter` assumed the wall was on the Quin's left. A Quin with the wall on its right then probed empty air and dropped off after about 0.1 s (`WallEnd`). It also showed in natural play: 2 of 5 natural runs in Pass 53 ended `WallEnd` early.
2. **"Slow".** The arc fell at 0.10 g, so a run lasted 2.3 s for 16 studs of rise and 98 along. It read as slow motion.
3. **The legs.** The ordinary ground run clip played at a fixed 1.35× (about 40 studs/s of stride), whatever the body was doing.
4. **The feet.** The body was held 2.4 studs off the wall and leaned only 18°, which brings the feet about 1.2 studs closer. They ran on air, 1.2 studs off the wall.
5. **The arms.** They swung as on the ground. The arm layers are switched off during a wall run, so nothing put a hand on the wall.

## Changes

**`States/WallRunState`**
- `wallBeside` looks both ways from the root for a near-vertical surface within 6.5 studs. It is used when `detectWallRunSurface` fails.
- With no wall on either side, the run is dropped at once (`WallKickReason` "NoWall") instead of being attempted on the wrong side.
- New attribute `WallRunFound` for debugging.
- The run clip's rate follows the body's real speed, along and up: |(along, rise)| ÷ `Gait_RunAuthoredSpeed` 29.5, clamped 0.9–1.9.

**`CombatConfig`: the arc**

| Setting | Before | After |
|---|---|---|
| `WallRun_GravityScale` | 0.10 | 0.20 |
| `WallRun_ClimbRatio` | 0.5 | 0.75 |
| `WallRun_Drag` | 5 | 3 |
| `WallRun_SinkSpeed` | 20 | 22 |

**`CombatConfig.WallRunTiltDegrees`:** 18 → 30, so the whole-body lean away from the wall brings the feet to the wall.

**New body layer `Procedural/WallHand`** (client, `ProceduralCombatReactionController`, registry entry `WallHand`, Workspace `Layer_WallHand` for A/B):
- During a wall run, the wall-side arm is solved as two bones. The elbow is bent down and back, and the hand reaches a point on the wall found by a ray from the shoulder: 0.25 studs off the surface, 0.9 ahead of the shoulder, 0.3 below it.
- The hand sways 0.55 studs along the wall in time with the stride, one sway per run stride.
- The fingers turn forward and up along the wall.
- It blends in over about 0.1 s and out over about 0.15 s, and lets go if the wall is out of reach.
- Config: `CombatConfig.ProceduralLayers.WallHand`.

## Measured

All in Studio Play.

**Staged runs at 40 studs/s** beside the straight arena wall, both directions:
- Before: 2.3 s, 98 studs along, 16 up, but only with the wall on the Quin's left. With the wall on the right, most runs failed at 0.1 s.
- After, both directions: 1.33–1.37 s on the wall, 51–52 studs along, 12.9–13.1 studs up.
- About 40% of staged attempts ended "NoWall". These are the staging catching the Quin before it reaches the wall. In one traced run that worked, the run's start was logged at the staging spot (x −109, z −733).

**Client pose during a run** (62 drawn frames, measured after the layers), distance from the wall face:

| Point | Average | Range |
|---|---|---|
| Wall-side hand bone | 0.49 studs | 0.25–1.05 |
| Wall-side toe | 0.30 studs | −0.23 to 1.90 |
| Other toe | 0.98 studs | |
| Other hand | about 3.5 studs (free) | |
| Hips | 2.41 studs | |

**Natural 16v16, 100 s:** 4 runs `ArcSpent` (about 1.11 s each), 1 `WallEnd` after 0.11 s. No server or client errors.

## Not checked

- **By eye (owner):** the hand, the lean and the shorter arc.
- **Run length:** the run is now about half the length of Pass 50's, by design for a firmer feel. The owner earlier asked for further and higher. The knobs are `WallRun_GravityScale`, `WallRun_ClimbRatio` and `WallRun_Drag`.
- **The remaining natural `WallEnd` at 0.11 s:** not traced.
- **The run clip:** it is still a ground run. A dedicated wall-run clip would read better than any layer.
