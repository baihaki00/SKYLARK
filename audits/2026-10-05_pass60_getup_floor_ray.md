# Pass 60: A get-up that floats (the floor ray took effect parts for the ground)

The owner: "one of the getup front animation are floating ... due to the baked animation".

## What the clips do alone

Three get-up clips have no hips travel (Pass 44): `GetUpFrontFast`, `GetUpFrontSlow`,
`GetUpBackSlow`. The body layer lowers them on to the floor (`ClipCorrections` `ground`).
Played alone on a standing Quin (client, final pose, every bone against a ray-found floor), both
front clips lie 0.03 - 0.4 studs above the floor: the correction works.

## Cause

`ProceduralCombatReactionController.ikRayParams`, the ray that finds the floor for that
correction (and for foot planting), excluded the Quins but accepted **any** part, solid or not.
The dust, shockwave, ground mark and impact parts that appear exactly where a body lands are
non-solid parts at the body's height. With one of them under the root the "floor" is found there,
the correction computes zero, and the body lies in the air at hip height.

(My own probe did the same thing first and reported bodies "5 studs underground": the proof that
such parts are under a landed body most of the time.)

Reproduced on purpose, `GetUpFrontFast`, lying part of the clip, lowest bone above the real floor:

| | mean | max |
|---|---|---|
| nothing under the root | 0.25 | 0.33 |
| a non-solid part 1 stud under the root | **3.97** | 4.19 |

## Fix

`ikRayParams.RespectCanCollide = true`: only what a body can stand on is ground.

Same test after, with the effect part under the root:

| Clip | lowest bone above the floor |
|---|---|
| GetUpFrontFast | 0.18 (0.12 - 0.23) |
| GetUpFrontSlow | 0.34 (0.07 - 0.39) |
| GetUpBackSlow | 0.20 (0.11 - 0.30) |

Foot planting uses the same ray, so feet no longer plant on effect parts either (not measured
separately).

## Also seen, not changed

- Fingers dip up to 0.5 studs under the floor while the hands push up (the correction watches
  the wrists, not the fingers).
- While it eases in (first ~0.15 s of a get-up) the body is still on its way down.
- A fall pose (`FallFront` / `FallBack`, held at hip height by design for the air) stays on the
  body for 0.05 - 0.09 s after touchdown before the get-up takes over.
- If a second corrected clip is at full weight at the same time, only one correction applies
  (seen once, on a Quin I froze in mid-knockdown; not in normal play).
- The real cure for all three clips is still a re-export with hips travel.

## Parked from this session: item 12 (wall run)

Measured, not yet changed: on the wall the vertical speed moves in steps of 4 studs/s every
0.1 s (the arc is integrated in the 10 Hz update), and at the kick the vertical speed jumps from
-21 to +18 studs/s in one frame, is held flat for 0.22 s, and only then does gravity start.
Planned: integrate the arc every frame and let gravity act from the kick's first frame.
