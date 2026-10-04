# Pass 50 (2026-10-05): the wall run is an arc (item 20)

Owner: the wall run is liked but too shallow; both further and higher, but physically
believable ("not Spiderman, not stick to the wall"), and it must work in a chase: a Quin can
chase one that retreats along a wall.

## Before

Every run climbed 3.5 studs, held that height at a fixed 48 studs/s whatever speed the Quin
arrived with, and let go after 1.25 s: 60 studs along a level line.

## Now

The speed it arrives with (along the wall, 18 to 48 studs/s) is what it has:

- half of it goes into the climb (`WallRun_ClimbRatio` 0.5);
- on the wall it falls at a tenth of gravity (`WallRun_GravityScale` 0.10): its feet pushing
  against the wall carry the rest;
- it loses 5 studs/s along the wall every second (`WallRun_Drag`);
- it kicks off when it is sinking at 20 studs/s (`WallRun_SinkSpeed`), when it is back down
  where it started, or under 14 studs/s along the wall; a corner, the end of the wall or an
  enemy within 14 studs still end it as before. `WallRunMaxDuration` (3 s) is only a ceiling.

So the run rises, tops out and comes down, and a faster arrival goes higher and further.

**In a chase:** a Quin whose target is wall-running may take to the wall without waiting out its
own 5 s cooldown (ChaseState). Wall runs already start from both Chase and Retreat.

**Trespass:** a wall run is over the arena floor, so it costs nothing (pass 49).

## Measured (a Quin staged at the east wall with a set arrival speed)

| Arrival speed | Time on the wall | Along | Peak above the start | Leaves the wall at |
|---|---|---|---|---|
| 48 studs/s (final settings) | 2.31 s | 98 studs | 16.0 studs | +5.5 |
| 48 (first settings: climb 0.6, gravity 0.15, sink 20) | 1.67 s | 74 | 15.6 | +9.6 |
| 40 (first settings) | 1.55 s | 56 | 11.0 | +4.1 |
| 30 (first settings) | 1.35 s | 36 | 6.4 | -0.4 |

With the final settings the same arc gives about 10 studs up and 75 along from 40 studs/s and
6 up and 40 along from 30 (worked out, not measured: the staging failed for those runs).

A first version let go at a sink of 8 studs/s, which is the top of the arc: high, but no
further than before (58 studs at 48). Raised to 20.

## Not shown

- **Only one full run with the final settings was measured** (48 studs/s). Staging a wall run by
  hand is unreliable: 7 of 9 attempts ended in 0.1 s (the AI turns the Quin before it starts, or
  the lane probe trips).
- **Not seen in natural play.** Wall runs are rare in a match (about 1-2 per 80 s), and the
  follow-onto-the-wall rule was not seen firing.
- The body's lean and the Run clip on the wall are as before; how a 16-stud arc reads by eye is
  unchecked.
- `WallRunState` carries a test hook: the attribute `WallRunEntrySpeed` on a Quin stands in for
  its arrival speed once.
- Items 11 (awareness of the wall's rim) and 12 (lag after touching a wall) are still open.
