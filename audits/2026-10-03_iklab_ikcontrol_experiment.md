# IKLab (2026-10-03): is Roblox IKControl worth it on the Quin rig?

An experiment outside QuinCore. Everything lives in `Workspace.IKLab` (place QUIN_COMBAT_V3):
`IKLab_Quin` + `Targets` (drag-the-balls dummy), `Course` (ramp 15 deg, stairs, rubble, cross slope),
`IKLabDemo` (client Script, snapshot `Workspace/IKLab/IKLabDemo.client.lua`).

## Facts about IKControl on the Quin (one skinned mesh, Mixamo bones)

- Works on Bones (`ChainRoot` / `EndEffector` = Bone). Does not solve in Edit mode.
- Without a `Pole` the knee bends backward. A pole fixed in the world is wrong once the body moves;
  it has to ride with the root.
- Constraints between two bones are honoured (Bones are Attachments): a `HingeConstraint`
  hip bone -> knee bone with limits 0..0 held the leg straight; any hinge made the knee bend forward
  with no pole. The tutorial's rig-attachment steps do not apply, but the idea does.
- A target beyond reach straightens the leg completely (knee 180 deg). Clamp the reach.
- IKControl writes its result into `Bone.Transform`, so the clip pose cannot be read back while IK
  is on. The demo bakes each clip's foot path (24 samples) and looks it up by `TimePosition`.
- A target set in RenderStepped is used one frame later. Set root and targets in `PreAnimation`.
- Default `SmoothTime` 0.05 adds lag; the demo uses 0.

## Demo

Three lanes, same clips (Idle / WalkConfident / Run), same path and speed (walk 6.9, run 26.7 studs/s
from the baked foot speed), walk out and run back:

- A animation only (root follows the ground under it)
- B basic IK: a foot that would sink is pushed up onto the ground
- C foot placement: ground-relative foot height, lock while planted, slope tilt, pelvis drop, reach clamp

## Results (one clean lap each way, 242 fps, planted = clip foot within 0.1 of its lowest point)

| Gait : terrain | Sole inside ground, avg / max (A, B, C) | Planted foot above ground (A, B, C) | Planted foot slide studs/s (A, B, C) |
|---|---|---|---|
| Walk flat | 0.020/0.90, 0.000/0.02, 0.001/0.57 | 0.03, 0.03, 0.09 | 0.97, 0.94, 0.38 |
| Walk ramp | 0.170/0.60, 0.002/0.04, 0.005/0.15 | 0.04, 0.04, 0.08 | 0.59, 0.61, 0.48 |
| Walk stairs | 0.073/0.87, 0.001/0.78, 0.000/0.00 | 0.16, 0.16, 0.04 | 0.61, 0.63, 0.21 |
| Walk rubble | 0.031/0.52, 0.000/0.00, 0.001/0.25 | 0.08, 0.32, 0.07 | 0.59, 0.59, 0.27 |
| Walk cross slope | 0.034/0.86, 0.002/0.03, 0.000/0.02 | 0.11, 0.11, 0.06 | 0.61, 0.63, 0.25 |
| Run flat | 0.002/0.16, 0/0, 0/0 | 0.00, 0.01, 0.08 | 1.49, 1.33, 0.22 |
| Run ramp | 0/0, 0/0, 0/0 | 0.47, 0.47, 0.17 | 3.48, 3.18, 0.05 |
| Run stairs | 0.177/0.92, 0/0, 0.046/0.53 | 0.06, 0.07, 0.04 | 3.74, 3.40, 0.03 |
| Run rubble | 0/0, 0/0, 0.003/0.31 | 0.18, 0.16, 0.08 | 3.29, 2.99, 0.04 |
| Run cross slope | 0.003/0.08, 0/0, 0/0 | 0.11, 0.11, 0.06 | 3.73, 3.41, 0.03 |

Straight-knee frames while walking: A 1.2-1.6%, B 0.2-0.4%, C 0%.
Script cost per rig per frame: about 19-25 microseconds in all three lanes (the engine's own solve is
not included and was not measured).

## Reading

- B (what the tutorials show) only stops sinking. It leaves the float and the slide, and on rubble it
  makes the float worse (0.08 -> 0.32).
- C is where the gain is: slide while running 3.3-3.7 -> 0.03-0.05 studs/s, stairs and slopes grounded.
- C is slightly worse than A on flat ground for float (0.03 -> 0.09) and still dips into stair edges
  at a run (max 0.53): ground smoothing lags at 27 studs/s.
- A's slide depends on the travel speed matching the clip; here the speed came from the clip itself.

## Not tested

Strafe, backward, turning while moving, jump / landing, upper-body layers, many rigs at once,
engine solve cost, hinge limits in the moving demo (poles were used).
