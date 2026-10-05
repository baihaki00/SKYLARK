# Pass 68: The jump down off a platform is sized for where it wants to land

The owner's diagram (Pass 63): from a platform a Quin leaves by a normal jump of whatever
length suits (red arcs), a projectile arc (blue) or a style (yellow). The projectile arcs and
styles already existed. The normal jump down was one fixed hop.

## Before

`ChaseState`'s "Ledge Dive Down": apex 2 studs, 28 - 52 studs/s, so 8 - 14 studs across,
whatever the distance to the target, and only from close to the ledge. Measured in a generated
arena (22 jumps down in 126 s): about 8 studs across on average, landing 24 studs from the
target on average; it then ran the rest.

## Now

`TraversalModule.solveJumpDown(drop, distance, ledgeDistance, margin)`: the arc for a landing
`distance` away and `drop` lower. It rises `Jump_DownArcPerStud` (0.12) studs per stud to cover
(3 at least), flies at the speed that lands it there (14 - 58 studs/s), and is only taken when
it comes back down past the ledge; otherwise the Quin gets nearer the ledge first. A target
beyond a jump's speed gets the longest jump that way: it lands short and runs on.

ChaseState aims it at striking distance in front of the target, from wherever on the top the
Quin stands, and needs it to be facing the target.

`LocomotionModule.jump` takes an optional `flightTime`: a jump aimed at a landing spot keeps
its launch speed across the ground until it is down. Without it the chase's own pace (braking
for its target) took over in mid-air and the jump came down about 40 % short (17 across for a
33-stud jump).

A first version raised the arc until it cleared the ledge. A near target with the ledge far
off then got a 15-stud jump straight up that came down where it started (7 of 10 jumps in the
first test): removed; the solver now says "not from here".

## Measured

Staged: a 14-stud platform, the target frozen on the floor, the chaser made urgent (a calm,
confident Quin walks off the ledge instead: Pass 46, unchanged).

| Stood (from the ledge) | Target beyond the ledge | Jumped from | Peak | Landed from the target |
|---|---|---|---|---|
| 4 | 12 | ran off the ledge, no jump | - | 2 |
| 4 | 30 | 2 in | 3.4 | 9 |
| 4 | 55 | 4 in | 7.0 | 19 (beyond a jump's speed: lands short) |
| 14 | 35 | 14 in | 5.6 | 10 |
| 22 | 20 | 21 in | 4.5 | 8 |
| 10 | 45 | 3 in | 5.7 | 2 |

It aims for about 7 studs in front of the target.

A new debug attribute, `DiveSkip`, says why a Quin on a platform has not jumped yet (casual,
ledge too far for the arc, not facing, in the air).

## Not checked

- Natural play after the change: the one generated arena tried had 2 jumps down in 117 s, too
  few to say anything.
- By eye.
- Whether the landing clip suits the longer flights.
