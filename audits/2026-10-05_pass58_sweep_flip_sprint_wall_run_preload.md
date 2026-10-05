# Pass 58: The swept Quin flips; a wall run is a sprint; clips are fetched up front

The owner, after the Pass 57 demo: "just use the FallAirKnockback animation, flip it 180 then play
the fallback or fallfront or they land properly like superhero landing", and "why can they jog
wall run or walk wall run?". The sweep and the wall-run numbers were written by the previous
session (which ran out before testing); this pass finished, corrected and measured them.

## Sweep: flail, turn over, fall pose, land

`SlideTackle.sweep` launches the victim higher (`SlideTackle_Launch` 12 -> 55, about 0.55 s of air)
and `flip` turns its root once over, the way it topples, frame by frame (an angular velocity alone
was damped to ~90 degrees). The first half is under the flailing clip (`FallAirKnockback`, started
by KnockbackState like any air knockback); half-way round the fall pose for its side
(`FallBack` / `FallFront`) takes over; it comes round upright and Recovery picks the landing as
for any knockdown (ninja kip-up from the back, a landing clip from the front, or down and up when
heavy). Pass 57's "drop into the get-up's first frame", `GetUpClipOverride`, the 0.8 s hold-down
and the two-clip preload are gone.

Measured (server, two Quins, 5 sweeps after the preload below):

| | |
|---|---|
| flail at full weight | 0.06 - 0.13 s |
| fall pose for its side | 0.27 s, every time (3 Front, 2 Back) |
| upright again | 0.44 s |
| touchdown (Recovery) | 0.51 - 0.64 s |
| landing / get-up clip | 0.02 - 0.03 s after touchdown |

## First-use blank: every clip is fetched at session start

Before: the first sweep onto the front showed **no fall pose at all** and stood 0.45 s after
touchdown before its get-up clip appeared (0.38 - 0.94 s with no Action clip): `FallFront` and
`GetUpFrontFast` were being loaded for the first time. The second sweep (Back, clips already
used in that session) had none of it. This is not a sweep problem: any clip first played in a
session has it.

`AnimationModule.preload()` walks `AnimationConfig.Registry` and fetches every clip once
(`ContentProvider:PreloadAsync`). Called from `ServerScriptService.Server` and from
`AIGhostHandler` on each client (the client shows the server's animations and loads them itself).
After it, in a fresh session, the first front sweep had its fall pose at 0.27 s and its landing
clip 0.03 s after touchdown.

## Wall run: sprint only

Config (previous session): `WallRun_MinEntrySpeed` 32 (new), `WallRun_MinAlongSpeed` 14 -> 26,
`WallRun_MinClipRate` 0.9 -> 1.15.

Corrected here: the entry check had been put inside `WallRunState.enter` as a `tooSlow` flag, so a
slow Quin still entered the state (paid the energy, kicked up dust, started the clip, took the
cooldown) and was dropped on the next update. It is now one question asked before the state is
chosen: `WallRunState.fastEnough(rootPart, wallSurface)` (speed along the wall's tangent >=
`WallRun_MinEntrySpeed`), used by ChaseState and RetreatState, the only two ways in.

Measured: forced runs (test hook, 48 studs/s) are full arcs, 1.54 - 1.55 s, 7 of 7.
**Not measured:** a natural entry being refused for being slow (two Quins rarely wall run by
themselves); the rule is one comparison.

## Demo loop

Two Quins (`DevCommand "team:1"`), looping until Workspace `DemoLoop` is false: hurdle, sweep,
wall run, wall run + dash, on the strip by the south wall (x -105..25, z -716 / -734).
Four rounds: sweeps 4 of 4 stages, hurdles in 3 of 4 (the first stage timed out with no slide),
wall runs 7 of 7 full, dashes off the wall counted in both "+ dash" stages checked.

## Not checked

- By eye (owner): the flip (360 degrees in 0.44 s is quick), the landing choice, the wall run.
- The client side of the preload (measured on the server only).
