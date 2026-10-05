# Pass 52: Projectile jump, the dive holds its speed (items 8 and 9)

Owner items:
- **8.** The trajectory slows mid-dive; it must be smooth.
- **9.** A style that changes direction after the apex should be treated like a dive: dive FX, dive, dive FX, dive to the ground or the target.

## Cause

`States/ProjectileJumpState` had three ways of losing the dive's speed.

**1. Style 5 (swoop).** The Bezier curve was timed by an ease curve (fast, slow, fast) instead of being flown at one speed.

**2. Styles 4 and 6 (turns in the air).** Each turn was a "strafe" leg.
- The leg ended by setting the velocity to zero.
- The dive only started on the next 10 Hz update, so the body hung in the air in between.
- The 0.5 s variant also decelerated linearly to zero.
- The turn had no dive treatment: no clip, no boom, no vapour cone.

**3. Style 6 (combo).** It went turn, then wait, then dive, with an extra `ComboWait` stop after every turn.

## Fix

The draft was written by the previous session and pushed and measured in this pass.

- **Every dive leg flies at one speed.** That speed is `ProjectileJump_SlamSpeed`, or ×1.15 for styles 3, 6 and 7, held from the leg's first frame to the floor.
- **A turn is a dive leg.** `startTurnLeg` dives off to one side, slightly downhill (`ProjectileJump_TurnLegSlope` 0.2). Its length comes from `pickStrafe`, and its duration is distance divided by speed.
- **Each leg opens the same way** (`diveEffects`): the flying clip, the sonic boom and the vapour cone. The body flies head first along the path (`DIVE_PHASES`).
- **Legs chain without a stop.** The per-frame Heartbeat guard ends a leg on its own frame and starts what follows: the final dive, or the combo's next action.
- **The swoop is flown along its curve at dive speed.** `curveT` advances by speed × dt ÷ |tangent|, with a small pull back onto the curve (`CURVE_PULL` 4).
- **Cleanup.** `triggerComboNext` became the module-level `comboNext`. The `Strafe` and `ComboStrafe` update branches are gone, along with `fluidEaseOutIn`, `BezierDashDuration` and `BezierSpeedFloor`.

## Measured

**Setup:** Studio Play, generated arena (`run 4`), 16v16. A driver forced a projectile jump every 1.2 s, cycling styles 1–7, and a Heartbeat probe sampled each jumper's speed and `PJPhase`.

**Run sizes:**
- Before: 201 jumps.
- After: 275 jumps, a few more than forced because Quins also jump on their own.

### Middle 80% of the final dive

Studs per second, average of the minimum / median / maximum across dives. The first and last 10% are excluded: launch and touchdown.

| Style | Before | After |
|---|---|---|
| 2 High dive | 402 / 480 / 480 | 416 / 480 / 480 |
| 3 Double | 482 / 552 / 552 | 418 / 552 / 552 |
| 4 Sidestep | 345 / 480 / 480 | 403 / 480 / 480 |
| **5 Swoop** | **25 / 132 / 797** | **428 / 480 / 480** |
| 6 Combo | 379 / 552 / 552 | 315 / 552 / 552 |
| 7 Rocket | 367 / 552 / 552 | 451 / 552 / 552 |

### Lowest speed within 0.15 s of the end of a turn leg

| Style | Before (average / minimum) | After (average / minimum) |
|---|---|---|
| 4 Sidestep | 27 / 0 | 478 / 478 |
| 6 Combo | 29 / 0 | 463 / 202 |

Style 6's 202 is a combo turn followed by a mid-air jump (the sequence's own Jump action), not a stall.

**Health:** no script errors or state warnings in the log.

## Not checked

- **By eye:** whether the turn legs read as dives (clip, boom, cone on each leg).
- **Straight-dive dips:** the remaining dips in straight dives, a minimum of about 400 against a median of 480, happen on some dives only. These are likely the wall probe or the arena containment; not traced.
