# Pass 23 (2026-10-03): head shake, walk feet, doubled footsteps

Owner watched the stalk-walk demo (MovementTestArena, one Quin walking at 7.5 studs/s) and
reported: legs / feet look odd, the head vibrates at high frequency sometimes, footstep audio
is mismatched. Base: `25f68ae`. No Studio backup folder (the MCP sandbox cannot write to
ServerStorage any more); the git snapshot matched Studio before the edits.

## 1. Head shake (and spine, legs): pose layers stacked on frames with no animation step

- **Measured:** head, neck and Spine2 reversed direction about 23 times a second with single
  frame jumps of 40-80 degrees; hips steady. Arm/spine springs off made no difference.
- **Cause:** AIGhostHandler runs the client pose layers (ProceduralCombatReactionController,
  LookController) every RenderStepped. They edit `Bone.Transform` in place, on top of what the
  Animator wrote. The Animator does not write every rendered frame: at the owner's 235 fps,
  1 frame in 13 has no animation step (1409 rendered frames, 1220 PreAnimation). On such a
  frame the layers were applied a second time on top of their own result: the head moved by
  its whole look angle again and snapped back on the next frame. The foot solver also read
  its own output as the clip's pose.
- **Why rarely seen in a 16v16:** lower frame rate, so nearly every frame has an animation step.
- **Fix:** the layers run once per animation step (flag set on `RunService.PreAnimation`), with
  the time since their last run. Workspace `PoseEditEveryFrame = true` restores the old
  behaviour for comparison.
- **A/B, drawn pose (read after all RenderStepped handlers), 4.2 s each, look angle up to 50:**

| bone | jumps over 6 deg, old -> new | back-and-forth reversals, old -> new |
|---|---|---|
| head | 309 -> 0 | 183 -> 0 |
| Spine2 | 219 -> 0 | 165 -> 0 |
| left knee | 33 -> 9 | 47 -> 0 |
| right knee | 39 -> 5 | 53 -> 0 |

## 2. Walk feet: the solver stepped a foot all through a plain walk

- **Measured (solver state, walk):** right foot in a procedural step 50% of the time, left foot
  released ("waitLift") 52%; a foot held planted about 1% of the time.
- **Not the clip:** the walk clip's planted foot drifts 0.1-0.2 studs per stance, on server and
  client.
- **Cause:** the "out of reach" rule compared the pinned spot with the bare leg length. A walk
  lands on a nearly straight leg, and the pin sits at floor height, a little lower than the
  clip has the ankle: the spot was 0.1-0.2 studs out of reach from the first frame of every
  stance (57-64% of stance frames). Out of reach means step again (one foot) or let go (the
  other, since only one foot steps at a time).
- **Fix:** out of reach is judged against the clip's own leg extension plus
  `FootIK_OverreachSlack` (0.3 studs).
- **After:** both feet planted ("lock") 49-56% of the time, i.e. through the stance; procedural
  steps 0%.

## 3. Footsteps: every step sounded twice

- **Measured (walk):** touchdowns at 0.31, 0.81, 1.26 s...; sounds at 0.39 + 0.54, 0.84 + 1.03,
  1.31 + 1.47... Two per step, about 0.16 s apart.
- **Cause:** `AnimationModule` plays a footstep on every `Footstep` marker of every loaded
  track. The gait keeps its other clips (jog, run, strafes) running in step at near-zero
  weight for blending; their markers fired too. The 0.15 s debounce let the second through.
- **Fix:** a clip's `Footstep` markers are silent below blend weight 0.35.
- **After:** 19 touchdowns, 19 sounds (plus one at the start), each 0.03-0.08 s after the toe
  comes down.

## Regression
- 16v16, 50 s: 0 server errors, 32 alive; footsteps 1.2 per Quin per second overall.
- Play As Quin (P) and walking forward: 0 errors.
- Arena System match not re-run. Not checked on screen by me; the A/B numbers are from the
  drawn pose.

## Also answered
- The stalking walk is a pace (7.5 studs/s) plus the forward walk clip `WalkConfident`; not a
  strafe. It happens only when the target is far (over 40-65 studs by style). Owner: keep it.

## 4. The male's left leg looked broken while walking (owner's frames 4, 6, 9)

- **Owner's check:** a viewer was set up with the male and female rigs playing the walk clip in
  place (no game layers) and labels with clip id, time and frame on them and on a live walking
  male. The raw clip looked normal on both rigs; the live male showed a severely bent ankle and
  a raised left leg at walk frames 4, 6 and 9, always the left leg.
- **Cause:** the walk sets the left heel down around frame 2 while the foot is still reaching
  forward (about 1.3 studs more until frame 6). The foot solver pinned a foot the moment it was
  low, so it nailed the left heel at first touch and then bent the leg and wrenched the ankle
  to hold it while the clip pulled it on. The right foot comes down later in its reach, so it
  barely suffered.
- **Fix (`FootIK_PlantWhenStill`, live A/B Workspace `PlantWhenStill`):** a foot is planted only
  once the clip has stopped it: clip foot travel over the ground below
  max(`FootIK_PlantStillMin` 3 studs/s, `FootIK_PlantStillPerSpeed` 0.35 x body speed).
- **A/B, live male walking (shin direction drawn vs clip):**

| left leg, walk frames | old: mean / max | fix: mean / max |
|---|---|---|
| 0-3 | 8 / 29 deg | 3 / 8 deg |
| 4-7 | **51 / 65 deg** | 1 / 10 deg |
| 8-11 | **53 / 66 deg** | 7 / 13 deg |
| 12-15 | 24 / 34 deg | 3 / 9 deg |
| 16-19 | 25 / 32 deg | 7 / 9 deg |

  The right leg was within 14 deg before and is within 12 after. Left ankle raised above the
  clip at frames 2-10: max 0.36 -> 0.09 studs.

## 5. Near-straight walking pulled in a strafe clip

- The diagonal blend (pass 22D) blended the strafe set in from 0 degrees off the facing. A body
  walking slightly off its facing (facing its target) got about 26% of a strafe clip; one foot
  then dragged about 2 studs per step. The pass 22 plan said the blend should start around
  25 degrees.
- **Fix:** below `Gait_DiagonalBlendStart` (20 deg) off straight ahead or straight back the
  forward cycle alone carries the motion; the blend ramps in to `Gait_DiagonalBlendFull` (40).
- Walking backward still slides by the stance measure with the blend on or off; that measure
  depends on fixed foot heights and is not reliable across rigs. Not changed; open.

## Regression (4 and 5)
- 16v16, 50 s: 0 server errors, 0 client errors, 32 alive.
- Not re-run: Arena match, P to possess. The owner checks the walk on screen with the viewer.
