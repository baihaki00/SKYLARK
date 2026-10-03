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

---

# Second round (same day): untested gaits, whole-body comparison, no-code engine parts

Demo is now four lanes (D = C + knee hinges instead of poles, head LookAt, part on a hand bone,
trail, hanging tag) and a scenario loop: walk / run the course, strafe and walk backward over
ramp + stairs, turn in place, walk circle (r 4), run circle (r 10), run + three jumps.
The rubble repeats every 8 studs so every lane crosses identical ground.

Two flaws of lane C found by the first full run and fixed:
- foot rotation came from the heaviest clip, so a cross-fade popped the toe (peak 266 -> 48 studs/s);
  rotations are now blended by weight.
- "planted" was lift only; the strafe clip shuffles low feet, so the lock dragged
  (strafe slide 1.24 vs 1.16 for plain animation). Planted now also needs the clip to hold the foot
  still in the world (same rule as QuinCore pass 23b). The slide metric uses the same definition.

## Feet, final run (A / B / C / D), 242 fps

| Scenario | Planted-foot slide studs/s | Sole inside ground avg (worst) | Planted foot above ground |
|---|---|---|---|
| Walk flat | 0.46 / 0.46 / 0.13 / 0.12 | 0.021 (0.91) / 0 / 0.001 (0.60) / same | 0.02 / 0.02 / 0.05 / 0.04 |
| Walk stairs | 0.46 / 0.47 / 0.15 / 0.14 | 0.084 (0.85) / 0 / 0 / 0 | 0.14 / 0.14 / 0.02 / 0.02 |
| Run ramp | 3.76 / 3.46 / 0.05 / 0.03 | 0 | 0.48 / 0.49 / 0.17 / 0.17 |
| Run stairs | 3.64 / 3.49 / 0.05 / 0.02 | 0.096 (0.50) / 0 / 0.037 (0.73) / same | 0.03 / 0.03 / 0.02 / 0.02 |
| Strafe flat | 0.37 / 0.30 / 0.12 / 0.12 | 0.014 (0.94) / 0.001 / 0.001 / 0 | 0.03 all |
| Strafe ramp | 0.39 / 0.33 / 0.23 / 0.22 | 0.182 (0.60) / 0 / 0.037 (0.26) / same | 0.06 / 0.06 / 0.03 / 0.03 |
| Strafe stairs | 0.35 / 0.29 / 0.12 / 0.11 | 0.069 (0.86) / 0 / 0 / 0 | 0.20 / 0.20 / 0.02 / 0.02 |
| Backward ramp | 0.40 / 0.40 / 0.17 / 0.15 | 0.050 / 0.004 / 0.001 / 0.001 | 0.18 / 0.18 / 0.03 / 0.03 |
| Backward stairs | 0.42 / 0.43 / 0.16 / 0.15 | 0.239 (1.08) / 0 / 0.048 (0.76) / same | 0.11 / 0.11 / 0.05 / 0.05 |
| Turn in place | 1.66 / 1.66 / 0.11 / 0.07 | 0 | 0 / 0 / 0.10 / 0.09 |
| Circle walk | 1.37 / 1.36 / 0.18 / 0.15 | ~0 | 0.01 / 0.01 / 0.06 / 0.05 |
| Circle run | 1.94 / 1.69 / 0.04 / 0.03 | ~0 | 0.02 / 0.03 / 0.06 / 0.06 |
| After landing | 4.11 / 3.67 / 0.03 / 0.02 | 0.009 (0.22) / 0 / 0 / 0 | 0 / 0.04 / 0.04 / 0.04 |

Straight-knee frames: A about 1%, C and D 0%.

## Whole body: each bone against lane A's same bone (the layer's own contribution)

Per bone: offset RMS, speed of the offset RMS, reversals per second of that speed (vertical,
above 0.3 studs/s) and RMS acceleration against lane A's.

- Hips, chest, head, arms, hands: untouched by B. In C they only ride the pelvis: offset 0.15-0.25
  studs, 0.9-1.4 studs/s, 2-3.5 reversals/s (the step rhythm), zero on flat ground.
- Feet and toes, B and C alike: offset 0.15-0.3 studs but 15-55 reversals/s, also on flat ground
  (circle run: 55/s). A flutter of about 0.02 studs per frame; cause not isolated (suspect the
  one-frame clip look-ahead). Acceleration against A is 0.8-1.1, so it adds no visible energy.
- B snaps at edges: knee / foot offset speed peaks 120-250 studs/s on the course, 25-35 on flat.
  C peaks 22-50.
- Knees, pole (C) against hinge (D): knee rotation off the clip by 16-72 deg RMS with poles,
  7-15 deg with hinges; strafe knee position 0.82 vs 0.34 studs. Hinges are better and need no pole.
- Head LookAt (D) at a fixed world target: head turned 43-108 deg RMS off the clip, with a
  157 studs/s snap while strafing. It has no limits of its own.
- The acceleration ratio is noisy: lane B's head reads 0.53x lane A's in Walk although B does not
  touch the head. Only large ratios mean anything. Turn-in-place body numbers are from about 1.4 s
  and include one unexplained frame (hips peak 24 studs/s in every lane); not used.

## No-code engine parts on the bone rig

- RigidConstraint, bone -> part: follows the animated bone exactly (gap 0.000).
- HingeConstraint hip bone -> knee bone (limits 0..150): knee direction without a pole, see above.
- Trail between two bones: created without error; not checked by eye.
- BallSocketConstraint hanging a part from a bone-fixed part: did not follow (161 studs behind)
  on these anchored, CFrame-moved rigs. Not tried on a physics-driven Quin.
- IKControl LookAt: works, but over-rotates and snaps without code that gates it.

Script cost per rig per frame: 17-25 microseconds, all lanes. Engine solve cost still not measured.

---

# Third round (same day): IK Lab becomes a test mode

- The demo no longer runs on every Play (its follow camera took over the view in any mode). It runs
  only while `CurrentMode == "IKLab"` and removes its rigs, bar and camera when the mode changes.
- `GameModeManager.startIKLab()`, `SetTestMode` branch "IKLab", `GameCommand` / `DevCommand` "ik_lab",
  first card on the TEST MODES tab (the other cards moved one column right).
- Clips come from `AnimationConfig.getAllPaths()` (106 entries); each is baked the first time it is
  chosen. Looping clips that travel cross the course; the rest play standing on the rubble.
- Tour gained jog and strafe right.
- Bottom bar: clip browser, Tour, camera on all / orbit one Quin, slow motion, pause.
- Checked in Play: start by DevCommand and by the card's remote, Movement.Jog (9.2 studs/s) on the
  course, Attacks.Kicks.HighKick standing, orbit camera 13.8 studs from lane C, start of Pose Viewer
  removes the lab, no script errors. The card itself was not clicked by hand.

---

# Fourth round (same day): lane D becomes "full procedural"

Owner: put every procedural layer on D, cost no object, then stress test.

- Engine `IKControl` LookAt removed; QuinCore's `LookController` drives head, neck and upper back
  (target override = the blue ball), so the in-front gate and the caps come from the game's own code.
- Root level (before the leg solve, feet stay planted): Lean (acceleration + speed), SlopeLean,
  PelvisSpring (with a landing dip), HipTwist.
- Pose level (Bone.Transform after animation and IK, once per animation step): SpineCounter
  (Spine, Spine1), ArmLag, Toes, Breath. Arm IK: Point (left hand, IKControl Position).
- Each layer has a switch (`D_<Name>`, panel at the bottom left).
- Checked: starts with no script errors; D root tilt 4.5 deg walking the side slope and 6.9 deg peak
  strafing; no NaN over 8.5 s. Not yet measured: run, circles and jumps with the layers on, each
  layer on its own, Point and Look actually engaging near the ball.
- Stride warping, inertial blending and hand contact IK are not implemented.
