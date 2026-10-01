# Pass 11 (2026-10-01): platforms by geometry, jump vs projectile jump, the dive

Studio backup: `ServerStorage.backup_pre_16v16audit11_20261001`.

## Jump scale (a Quin is 8 studs tall, gravity 196.2)

Every obstacle is named `OB`; what a Quin can do with one depends on geometry only.
`Modules/PlatformCatalogue` scans the in-arena `OB` parts once: a platform is a part with a
level top at least 5 studs wide. How it is reached depends on how far its top is above the
floor the Quin stands on:

| Rise of the top | Access | How |
|---|---|---|
| up to 0.5 | Level | walk |
| up to 2.2 | Step | walk (Humanoid step-up) |
| up to 6.8 | Vault | hop / vault in stride |
| up to 12 (`Jump_MaxReach`) | Jump | a jump solved for the edge (below) |
| above 12 | ProjectileJump | only a projectile jump gets there |

A jump's apex is 14 studs at most. `TraversalModule.solveJumpOnto(rise, edgeDistance, maxReach)`
returns the jump height and speed that put the feet over the edge on the way down, or
`TooHigh` / `TooClose` / `TooFar`. At 40 studs/s the take-off window from the edge is
6-13 studs for a 4-stud rise, 9-16 for 8, 11-18 for 12. Too close: the Quin backs off for a
run-up. A platform whose underside is 9+ studs above the floor is floating (can be passed under).

Arena today: 13 platforms need a projectile jump (7 floating), 1 jump, 1 vault, 11 step,
6 `OB` parts are not standable.

## Projectile jump

Styles (attribute `JumpStyle`), all ending in the same impact:

| Style | What it does | Flight | Apex | Peak speed |
|---|---|---|---|---|
| 1 Arc | one ballistic arc onto the target, no dive | 1.3 s | 67 | 230-290 |
| 2 High dive | launch 350-400 studs/s up, dive | 2.6-3.3 s | 320-385 | 540-690 |
| 3 Double | second jump in the air, faster dive | 2.2-2.7 s | 190-270 | 550-630 |
| 4 Sidestep | high launch, sideways strafe (150-300 studs in 0.2-0.5 s), dive | 3.4-3.6 s | 340 | 1030-1490 (strafe) |
| 5 Swoop | high launch, curved swoop | 2.9-3.5 s | 300-365 | 1090-1150 |
| 6 Combo | 2 jumps + 2 strafes in sequence, faster dive | 2.2-3.3 s | 120-210 | 880-1450 (strafe) |
| 7 Rocket | high launch, fastest dive | 2.7-3.5 s | 320-400 | 550-790 |

### The slow dive

The flight's `LinearVelocity` was never put in per-axis force mode. Every phase switches the
mover through `MaxAxesForce`, which is ignored in the default mode; the mover pushed with the
default `MaxForce` of 1000. The "dive" was free fall with a nudge, and the style 1 arc fell
short of its target. No committed version of the state had the mode set; the speed in the
config was 150. What made it look instant before pass 4 was the teleport onto the target at
the end of the dive, removed then.

Fix: `ForceLimitMode = PerAxis`; `ProjectileJump_SlamSpeed = 480` (x1.15 for styles 3, 6, 7).
Measured peak downward speed per style, before / after: 2: 324 / 423-486, 3: 221 / 377-450,
4: 310 / 471-486, 7: 256 / 476-585. Same missing mode fixed in `MidAirClashState` (the loser's
throw-down) and `ProjectileFightState`.

Other fixes in the state:
- Style 7 never dived (it was not in the dive branch); it now does.
- A jump started from Chase flew at the target of the Quin's *previous* jump (the
  `ProjectileTarget` value was never cleared). The request is now consumed on entry.
- Style 1 leads a moving target, and arrives on the way down at a target above it.
- A target standing on a high platform no longer starts a mid-air clash (the test was
  "Y > 20").
- Touchdown: the last gap to the floor is covered in one frame instead of hanging.

Landing distance from the target, high-dive styles: 10-24 studs average. The landing spot has
a designed scatter of 5-25 studs (12% of the jump distance); not changed.

## Platforms in play

- `ProjectileJumpState.aimAtPoint(fighter, position)`: a projectile jump to a spot (style 1,
  no scatter). Forced test: 6 of 6 landed on a platform 105 studs up, 0-9 studs from the spot.
- Retreat: `TO_HIGH_GROUND` plans come from the catalogue; a platform within jump reach is
  jumped onto with the solver, a higher one with a projectile jump if allowed. In a 77 s
  16v16: 15 such jumps, 9 landed on platforms 43-107 studs up, 4 were met in the air by a
  pursuer's jump (mid-air clash), 2 fell short.
- Chase: the jump onto a perched target is solved against the platform edge. "Perched" now
  means standing on something: a target that was merely airborne counted as high ground and
  drew a projectile jump every time (39 in 64 s, 20 mid-air clashes); now 3-4 per run.
- Debug layer "Platforms": each platform's top and its access class.

No script errors in the final run.

## Open

- Time spent standing above 20 studs is still small (about 22 Quin-seconds in 77 s, mostly
  the landing recovery); a Quin that reaches a platform comes down again once its retreat ends.
- Styles 2-7 land 10-25 studs from the target by design (scatter); style 1 at a target that
  changes direction still misses.
- IK foot placement not done. Rejected jumps in unstick / climb callers are not rerouted.
