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

---

# Fifth round (2026-10-04): the three missing layers, thighs, the stress test

Owner: build stride warping, inertial blending and hand contact IK, then stress test everything;
the thighs on D need work and a leg flashes while strafing.

## A measurement error found first

The body numbers were read at `PreAnimation`. When the engine runs several animation steps per
drawn frame (Studio in the background: about 4), the steps in between show the pose without the
pose-level edits, which only exist in the drawn frame. D's head and hands read as flickering at
20-50 times the clip's acceleration; nothing of the kind was on screen. Measurements are now taken
in the render step, after the edits. The old "turn in place" body numbers (knee x11-30) were the
same artifact for a different reason and are gone too. Earlier rounds' body numbers for B and C
are unaffected (IK is solved in the animation step); D's round 4 numbers are not to be trusted.

## Thighs and the strafe flash

D had knee hinges and no pole, so nothing fixed the thigh's twist. Now, in C and D, the knee pole
is placed every frame where the clip's own knee points (the knee is baked with the foot and hip).

| Knee against the clip (lane C) | pole fixed in front (round 2) | pole from the clip's knee |
|---|---|---|
| Strafe: rotation / position | 72 deg / 0.82 studs | 17 deg / 0.33 |
| Backward | 32 deg | 29 deg |
| Run | 16 deg | 10 deg |

With that pole, a hinge on top changes nothing measurable (strafe: knee 17 vs 16 deg, peak 28 vs 39
studs/s, slide 0.22 vs 0.20), so `KneeHinge` is off by default. In the final run D's legs in the
strafe match C's (knee peak 32-39, foot peak 24-42 studs/s, acceleration 1.1-1.2 times the clip's).

## The three layers

- **StrideWarp**: when the body moves slower or faster than the clip's feet, the step is shortened
  or stretched about the hip along the clip's travel. New tour parts play the walk clip with the body
  at 0.6 and 1.4 times its speed. Body slower: planted-foot slide 2.15 (A) / 0.35 (C) / 0.15 (D)
  studs/s, knee 71 -> 41 deg off the clip. Body faster: 1.61 / 0.53 / 0.53: no gain. The foot lock
  already hides most of a mismatch; warping helps only when the body is slower.
- **Contact**: the hand nearest a rail within arm's reach rests on it (arm IK, one hand; rails beside
  lane D over the ramp, plateau and stairs, `Workspace.IKLab.Rails`). Hand to rail: 0.23 studs at
  IK weight 0.85. The hand travels to the rail at up to 170-235 studs/s for a frame when a run brings
  it in reach.
- **Inertial** (a new clip takes over at once and the last pose is carried into it): built, measured,
  **off by default**. The upper body carries over well. The legs pop: the engine solves leg IK before
  the pose can be edited, so a carried pose cannot be handed to it. A jump with it: knee and foot
  acceleration 3.2-6.9 times the clip's, peaks 170-540 studs/s; with the plain cross-fade 1.0-1.1
  times and 27-59.

## Final run, defaults (A / B / C / D, 228 fps)

| Scenario | Planted-foot slide studs/s | D: hips / head / hand offset from the clip, studs | D: worst acceleration against the clip (any group) |
|---|---|---|---|
| Walk | 0.45 / 0.45 / 0.17 / 0.21 | 0.35 / 0.43 / 0.56 | 1.3 |
| Run | 2.28 / 1.96 / 0.04 / 0.05 | 0.45 / 0.62 / 0.91 | 1.1 |
| Jog | 1.12 / 1.06 / 0.09 / 0.09 | 0.35 / 0.45 / 0.54 | 1.6 (hand) |
| Strafe left | 0.37 / 0.32 / 0.14 / 0.25 | 0.35 / 0.45 / 0.86 | 1.5 (hand) |
| Strafe right | 0.40 / 0.30 / 0.12 / 0.17 | 0.29 / 0.36 / 0.39 | 1.2 |
| Backward | 0.45 / 0.46 / 0.18 / 0.24 | 0.31 / 0.36 / 0.75 | 1.3 |
| Circle walk | 1.36 / 1.33 / 0.18 / 0.22 | 0.23 / 0.33 / 0.60 | 1.1 |
| Circle run | 1.99 / 1.70 / 0.04 / 0.05 | 0.92 / 1.33 / 1.12 | 1.1 |
| Turn in place | 1.69 / 1.69 / 0.11 / 0.11 | 0.02 / 0.07 / 0.43 | (clip nearly still) |
| In the air | - | 0.76 / 0.93 / 0.86 | 1.1 |
| After landing | 2.62 / 2.70 / 0.03 / 0.00 | 0.46 / 0.66 / 0.46 | 1.0 |

D's feet slide a little more than C's in walk, strafe and backward (0.21-0.25 against 0.14-0.18):
the root-level layers move the hip the legs reach from.

## Cost (full-procedural Quins beside the four lanes)

| Full Quins | Script per animation step | Script per drawn frame | Frame rate |
|---|---|---|---|
| 1 | 0.16 ms | 0.02 ms | 240 (cap) |
| 17 | 0.63 ms | 0.17 ms | 241 |
| 33 | 1.10 ms | 0.35 ms | 188 |
| 65 | 2.24 ms | 0.78 ms | 119 |

About 35 microseconds of script per full Quin per animation step and 12 per drawn frame. The frame
rate falls faster than the script time explains (65 Quins: 8.4 ms a frame, 3 ms of it script): the
rest is the engine (animation, IK, skinning), not split further.

## Not done

- Each layer on its own (only Inertial and KneeHinge were toggled).
- The foot flutter, the stair-edge dips at a run, the tag's wobble, the trail.
- Look and Point engaging near the ball (Point's range was cut to 30 studs; lane D passes 40 away).

## A faster way to edit a Studio script

A local `python -m http.server` in `studio_snapshot` and `HttpService:GetAsync` from an Edit-mode
command: the script is edited on disk with ordinary tools, then pushed (compile-checked first).

---

# Sixth round (2026-10-04): chest to the front in a strafe, thigh roll, arms out of the body

Owner: the strafe clips should read "moving 90 degrees left or right, looking forward"; on D the
thighs still turn inward ("shy legs") and the arms go through the body; hide the props.

## Strafe clips and the chest (layer `SquareUp`)

The clips, on the rig: travel exactly 90 degrees to the side; hips turned 63-68 degrees toward the
travel (30 in the Tired clips), chest 42-46 (24), head 2-6: the head already looks to the front.
`SquareUp` measures the chest's turn from the shoulders, averages it over a stride (the swing
stays), turns Spine and Spine1 back by it, and turns the neck the other way so the head stays
where the clip has it.

| Strafe test part | Chest off the front, clip (A) | D |
|---|---|---|
| Walk left / right | 44 / -43 | 7 / 9 |
| Run left / right | 42 / -44 | 1 / 1 |
| Tired left / right | 24 / -24 | 5 / 7 |
| Circle walk left / right | 41 / -36 | -5 / 5 |
| Circle run left / right | 41 / -44 | -7 / 6 |
| Tight circle (radius 4) | 41 | -10 |

D's head while circling: within 2-11 degrees of the point it circles. New programme "Strafe test"
(button on the bar, `Clip = "#Strafe"`): each strafe clip along a line on the open floor, then
circling a marker the Quin faces (radius 8 walk, 12 run, 4 tight).

## Thigh roll (layer `ThighTwist`)

The leg IK puts the knee and the foot where they belong but rolls the thigh about its own length
freely. Against the clip's thigh (lane C, no fix): 14 degrees RMS walking, 26 backward, 72 with the
body slower than the clip, single frames up to 180. A knee hinge does not change it (16 RMS on and
off). The thigh's rotation is now baked with the clip; at the pose step the thigh is rolled back to
the clip's and the shin turned the other way by the same amount, so knee, shin and foot stay put.
D: 0 degrees RMS, worst 1-3; foot to its IK target 0.00-0.02 studs average, 0.15 worst.

## Arms and the trunk (layer `ArmClear`)

Distance of the wrists and elbows from the line through the trunk (under the hips to the upper
chest). The clips themselves keep 0.88-1.10 studs. Before: D's elbow came to 0.26-0.75 and its
wrist to 0.03-0.08 (arm lag, the squared chest, and arm IK reaching across the body). Now: an
elbow or wrist closer than 0.95 is turned back out (the wrist on the elbow's side); a hand only
takes a rail on its own side; the left hand only points ahead or to its left.
Tour plus strafe test, 205 s: D's elbow never under 0.95; D's wrist under 0.90 on fewer than 0.005%
of frames (closest 0.61, in the strafe run to the left); the clip's own arms are under 0.90 on 0.38%.

## Props

Baton, hanging tag and trail are a layer (`Props`), off by default.

No IK Lab script errors; 208-235 fps with the four lanes.

---

# Seventh round (2026-10-04): limbs that look like sticks (in progress)

Owner: D's knees turn inward, the legs and arms look like wood / sticks with no muscle.

Measured and seen (front views of A and D at the same paused frame):
- **Hands.** A Roblox arm `IKControl` (Position type) sets the hand bone's own Transform to identity
  even at Weight 0. D's wrists had not moved since the arm IK was added (sd of the hand's rotation:
  A 5-11 deg, D 0.0); the hands hung flat and open. The control is now enabled only while a hand
  has a goal, and a held hand gets the clip's baked rotation back. After: A 7.9, D 7.9.
- **Knees.** Against the planted foot, D's knee direction matches the clip's (walk +2 vs +4 deg, run
  +8 vs +8, strafes -8 vs -8), hinge on or off. The inward knee is in the clips: at a run the knee is
  more than 15 deg inward of the foot on 43% of planted frames (worst 27), walking 8% (worst 36).
  New `KneeOverToe`: the knee may point at most 5 deg inward (25 outward) of the foot under it,
  held-foot heading included. Not measured yet.
- **Leg reach.** `REACH_LIMIT` 0.97 kept 28 deg of knee bend; D's knees never went under 20 deg
  (clip: 8). Now 0.995. After: straightest knee A 8, D 8.
- **Elbows.** The walk clip's arms are dead straight (under 5 deg) on 6-11% of frames. `SoftElbows`
  keeps 10 deg. After: straightest elbow A 1, D 10.
- **Arm sway** is now three parts (upper arm, forearm through the elbow hinge, hand through the
  wrist) on three springs, not the arm as one piece. `SquareUp` is spread over three spine bones.
  `Weight`: a footfall adds a small pelvis dip. None of these measured yet.

State: pushed, runs with no script errors, 5 s smoke test only. Not done: the full tour and strafe
test with the new layers (knee-over-toe result, arm clearance, foot targets, accelerations), front
views after, and the port of D into QuinCore the owner asked for next.

## Round 7b (2026-10-04): the knee jump at a run

Owner's report after round 7: "a new glitch for the foot ... during running".

**Measured** (Heartbeat, 4 s of `Movement.Run`, knee and foot bones, speed relative to the root):

| | A | C | D |
|---|---|---|---|
| Knee peak, round 7, all layers | 66 | 95 | **1021** (86 steps over 60 studs/s) |
| Same, `D_KneeOverToe` off | | | 94 (4 steps) |
| Same, `Weight` off / `StrideWarp` off | | | 1512 / 1557 (no change) |
| Foot bone peak, foot-to-target gap | same in A, C and D in every configuration | | |

So the foot bone was on target; what flickered was the knee. Cause: `KneeOverToe` compared the
knee with the foot's direction on every step, also in the air. A running foot in swing points
down and back, its flat direction swings through half a turn, and the full correction was applied
at once, so the knee pole was thrown round and back.

**Fix:** the rule now fades out with foot lift (`KNEE_TURN_LIFT` 0.6 studs), is limited to
`KNEE_TURN_MAX` 35 deg, and eases in and out (`KNEE_TURN_RATE` 12/s, per-leg `kneeTurn` state).

**After** (same probe, rule on / off alternated in one session):

| | A | C | D |
|---|---|---|---|
| Run, knee peak (steps over 60) | 36-46 (0) | 56-63 (0-1) | 64-78 (1-2) |
| Run, rule off | 39-43 (0) | 46-70 (0-2) | 54-67 (0-3) |
| Walk | 14 | 30 | 29 |
| Strafe test | 23 | 24 | 30 |
| Tour | 19 | 26 | 25 |

The rule still does its job. Share of planted steps with the knee more than 5 deg inside the
foot, and by how much on average:

| | A | C | D rule on | D rule off |
|---|---|---|---|---|
| Run | 66-71 %, 15-17 deg | 60-64 %, 14-19 deg | 50 %, **2.8 deg** | 69 %, 20.5 deg |
| Walk | 61-63 %, 13.7 deg | 48 %, 11-12 deg | 44 %, **3.6 deg** | 54 %, 11.3 deg |

Note: lane A shows the same inward knees, so the "shy legs" are in the run and walk clips
themselves, not caused by the IK.

**Not measured:** the pose-level layers (arms, thigh roll, SquareUp) and anything by eye. The
Studio window was not drawing during this session (RenderStepped 0/s), so those layers did not run.
