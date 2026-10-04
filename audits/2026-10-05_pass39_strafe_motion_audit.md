# Pass 39 (2026-10-05): strafe motion audit, upright strafes, paces from the clips

Owner: turn the whole-body tilt off in a strafe; strafing is a straight motion and a circle under
it looks wrong; recalculate the motion from the animation for the slow, walk and run strafes.

## The clips themselves (rig, 48 samples per cycle, stance foot under the root)

| Clip | Length | Body speed at 1.0x | Direction | Config before |
|---|---|---|---|---|
| StrafeLeft/RightTired ("slow") | 1.467 s | 1.99-2.32 studs/s | sideways within 1-7 deg | not used |
| StrafeLeft/RightWalk | 1.033 s | 6.0-6.8 | within 1 deg | 7.3 |
| StrafeLeft/RightRun | 0.667 s | 17.8-18.5 | within 1 deg | 18.9 |

The old 7.3 / 18.9 match the stance foot's peak speed, not its average: the clips played 12 % and
4 % too slowly for the body. A tired Quin played the walk clip at 0.63x (slow motion).

## The arena before (16v16, Circling, strafe clip at full weight, final pose)

| | Walk (tired, 0.65x) | Run |
|---|---|---|
| Body speed, sideways part | 4.7, 4.2 | 18.4, 16.9 |
| Travel off pure sideways | 14.6 deg | 15.2 deg |
| Turning, mean absolute | 120 deg/s | 112 deg/s |
| Turning the orbit needs | 9 deg/s | 62 deg/s |
| Lean toward the travel | 7.1 deg | 18.1 deg |
| Grounded foot speed over the ground | 4.0 studs/s | 8.8 studs/s |

A frame-by-frame trace showed a squared-up strafe is clean (0-1 deg/s of turning, dead sideways,
18.1 studs/s). The bad frames come in bursts: 45-68 % of the first 0.6 s of every standoff (the
body arrives facing its travel and turns 90 degrees to its target with the strafe clip already
playing), and about 22 % afterwards (the facing taken in 10 Hz steps, each snapped in 3 frames).
`Humanoid.AutoRotate` fighting the gyro was tested and ruled out (holding it off changed nothing).

## Changes

1. **Upright in a strafe** (`StrafeUpright` body layer, HUD row): the whole-body tilt fades out
   by the share of the body in a strafe clip. The tilt is untouched everywhere else.
2. **Paces from the clips**: `Strafe_SlowAuthoredSpeed` 2.1 (new), `Strafe_WalkAuthoredSpeed` 6.4,
   `Strafe_RunAuthoredSpeed` 18.1. A tired Quin now strafes with the slow clips at their own
   speed (`Strafe_TiredPace` removed).
3. **Pace limited by the circle** (`Circling_MaxStrafeTurnRate` 40 deg/s): speed / radius is the
   turn an orbit forces on a straight-stepping clip; above the limit the pace steps down a clip
   (run needs a circle of about 26 studs, walk 9). Respect-custom standoffs keep their own pace.
4. **Facing lead from the orbit**: the lead uses the orbit's own turn rate (speed across the line
   to the target over the distance) instead of the tick-to-tick change of the velocity direction.
5. **Even turning once squared up**: within 20 deg of its strafe facing the gyro is held to 1.5x
   the orbit's turn rate (at least 0.6 rad/s); further off it squares up at the full rate.
6. **Legs follow the real motion**: the strafe clip carries the legs only while the real motion is
   within 30 deg of sideways to the real body; otherwise the shared gait does.

## After (same probe)

| | Slow | Walk | Run |
|---|---|---|---|
| Body speed, sideways part | 2.1, 2.1 | 6.4, 6.2 | 16.9, 16.1 |
| Play rate | 1.02 | 1.00 | 0.97 |
| Travel off pure sideways | 5.9 deg | 8.4 deg | 6.7 deg |
| Turning, mean absolute | 40 deg/s | 59 deg/s | 42 deg/s |
| Lean toward the travel | -5.3 deg | 6.0 deg | 12.6 deg |
| Grounded foot speed over the ground | 0.7 | 4.4 | 7.9 |

Run strafe frames fell from 3621 to 474 in a comparable window (most run standoffs are on
circles too tight for it and now walk). No script errors.

## Not solved / not shown

- **Foot speed over the ground at a walk and run is about where it was** (4.4, 7.9). The mean
  along the travel is small (+0.7, +2.0), so pace and clip agree on average; what is left is
  within the stride. The clips' stance foot does not move at a constant speed (walk 3.8-7.5
  within one stance) while the body does. Matching that needs the body's speed to follow the
  clip's own profile through the stride: not built. The measure also counts an ankle rolling
  over a planted toe as movement.
- The run strafe still leans 12.6 deg toward its travel with the tilt off: that is the clip
  (or the upper-body force lean, not separated).
- Turning is still 40-59 deg/s on average: the entry turn and reversals are in the figure.
- Fight footwork was seen playing the walk strafe while turning at about 178 deg/s with almost
  no sideways travel. Not touched.
- The standoff changes pace of play: fewer run strafes at close range. Knockout rate and the
  whiff baseline were not re-measured. Not looked at by eye.

## Pass 39b (same day): correction, and the layer that was sliding the feet

**The clip speeds in the first half of this note are wrong.** They were measured at the ankle,
which rolls over the planted toes. Measured at the ball of the foot (ToeBase), which is what
stays on the ground, the clips are constant through the stride and match the old config:

| Clip | Body speed at 1.0x (ball of the foot) | Within-stride sd | Config now |
|---|---|---|---|
| Slow (Tired) | 2.56 | 0.07 | 2.55 |
| Walk | 7.27-7.28 | 0.14-0.19 | 7.3 (restored) |
| Run | 18.7 | 0.78 | 18.8 (was 18.9) |

So the 6.4 / 18.1 / 2.1 set in the first half was a 12 % mismatch introduced by this pass and is
reverted. No stride profile is needed: the body moving at one speed is what the clips want. The
"foot speed over the ground" rows above (ankle) are not a valid slide measure either.

**What was sliding the feet.** With the toe as the measure, in steady strafes the raw clip moved
the ball of the planted foot at 3-4 studs/s, but the final pose moved it at about 6. An on/off
run with the layer switches cleared foot planting and knee-over-toe. The cause was an older rule
in the controller ("Procedural Hip & Spine Twist"): the hips are turned up to 34 degrees toward
any sideways travel. Under a strafe clip, whose hips are already turned 65 degrees, that swung
both legs 0.9 studs off their steps.

**Change:** that twist now fades out by the share of the body in a strafe clip (same switch as
the tilt, relabelled "strafe clip carries the body (no tilt, no hip twist)"), and the twist
itself is a registered layer (`HipTwist`, `Layer_HipTwist`).

**Measured** (16v16, Circling with a strafe clip at full weight, switch alternated off / on /
off / on, 22 s each, ball of the grounded foot):

| | Switch off | Switch on |
|---|---|---|
| Final pose, speed over the ground | 5.7, 6.4 studs/s | 3.1, 2.3 |
| Raw clip in the same frames | 4.2, 3.6 | 3.7, 2.9 |
| Toe moved sideways of the clip by the layers | 0.86, 0.88 studs | 0.37, 0.32 |
| Chest toward the travel | -2 deg | -3, -5 deg |
| Toe samples | 962, 421 | 1076, 889 |

No script errors on server or client.

**Still open:** the raw clip itself reads 3-4 studs/s in a live match against 0.2 on the rig, so
part of the remaining movement is the body not travelling exactly as the clip assumes (turning,
speed changes) or the probe's ground test; not separated. Fight footwork still untouched. Not
looked at by eye.
