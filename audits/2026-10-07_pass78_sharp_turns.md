# Pass 78: Sharp turns (reversals)

Owner: "when I press W while running then immediately S, it feels heavy, same with A↔D, S↔W; it doesn't turn in place, it takes a small diagonal arc; same for jog and walk."

## Measured before (Player Quin, the player's machine moving the body, W → S)

| Pace | Faces the new way | Back to 80 % speed the new way | Carried on the old way | Arc width | Slowest |
|---|---|---|---|---|---|
| Run | 0.50 s | 0.86 s | 5.4 studs | 1.7 studs | 7.7 |
| Jog | 0.39 s | 0.31 s | 1.6 studs | 2.7 studs | 11.0 |
| Walk | 0.40 s | 0.33 s | 1.0 studs | 1.7 studs | 6.4 |

Why:
- **Below 13 studs/s there was no reversal at all.** The plant-and-pivot only started above the skid threshold (13 studs/s). A jog or walk kept its speed and swung round an arc (slowest 11 at a jog).
- **At a run:** the brake was soft (220 studs/s²), and the pivot kept 8 studs/s while turning at 11 rad/s (a small loop). Out of the pivot, the plain 80 studs/s² took 0.3 s to get going.
- **No turn clip plays.** RunTurn180 (0.67 s, an in-place 180° with two pivot steps) is in the config, but no reversal uses it.

## Changes (every Quin: the body is one)

- `Locomotion_ReversalMinSpeed` = 3: a reversal plants and pivots from any pace above a slow walk. The old skid stays at a run.
- `Locomotion_ReversalBrake_Agile` 220 → 320: a plant.
- `Locomotion_ReversalPivotSpeed_Agile` 8 → 3: it turns on the spot.
- `Locomotion_ReversalTurnRate_Agile` 11 → 15 rad/s: a half turn in ~0.2 s.
- `Locomotion_ReversalDriveOutAccel` 150 for `Locomotion_ReversalDriveOutTime` 0.35 s out of a pivot.
- `Locomotion_FacingMaxTurnRate` 14 → 20: the steer's facing constraint trailed a 15 rad/s pivot.
- The skid-smoke burst only on a plant at a run.

## After

| Pace | Faces the new way | Back to 80 % speed | Carried on the old way | Arc width | Slowest |
|---|---|---|---|---|---|
| Run | 0.41 s | 0.52 s | 3.4 studs | 0.6 studs | 2.7 |
| Jog | 0.32 s | 0.30 s | 0.8 studs | 0.5 studs | 2.7 |
| Walk | 0.32 s | 0.27 s | 0.7 studs | 0.5 studs | 2.6 |

## Not done

The 180° turn clip. With the pivot now about 0.2 s, the 0.67 s clip would have to run at about 3× speed. Its own 180° hip rotation would also have to be taken out and handed to the body, the same way the jump's hip lift was. It's the owner's call after feeling the mechanics.

## 16v16 check (the reversal settings are every Quin's)

Flow probe, 240 s, generated arena:

| Measure | Pass 76 | Pass 78 |
|---|---|---|
| Strikes per Quin-minute | 15.1 | 16.6 |
| Hit / whiff / blocked / interrupted % | 69 / 6.2 / 3 / 21.6 | 66 / 6.3 / 3.2 / 24.3 |
| Engaged % / standing % | 45.4 / 11.7 | 45.3 / 11.1 |
| Speed kept, Chase → Fight | 0.51 | 0.50 |
| Answers % | 40.6 | 42.3 |
| Swings per minute / CV | 11.1 / 0.25 | 10.7 / 0.24 |
| Knockdowns per Quin-minute | 3.17 | 2.92 |

Within run-to-run variance (16v16 runs have read 13.9–16.6 strikes per Quin-minute): the 16v16 is unchanged.
