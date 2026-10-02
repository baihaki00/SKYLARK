# Pass 19: facing on curves, and the torso-to-head shiver

Base: pass 18 (`627c2c9`). The Studio scripts were verified identical to that commit by hash before starting (the sandboxed Studio session cannot copy scripts into ServerStorage, so git is the backup).

## Owner requests
- Turning and curves (#2, #8, #18).
- New in this pass: "their body or head or from torso to head is jittering, high frequency vibrations".

## 1. Facing follows the motion (LocomotionModule)

### Measured
The circle slab, using the Studio lap driver (`DevLapRadius`), radius R = 8 / 14 / 20 / 27. The body faced 9-17° off its actual motion, more on tighter turns: about turn rate × 0.11 s.

### Cause
With AutoRotate, the body snaps to face the heading passed to `Humanoid:Move`. The Humanoid's velocity follows that heading about 0.1 s behind. So on any curve the run cycle drives one way while the body moves another. The first attempt, an AlignOrientation aimed at the velocity, showed the same lag with the opposite sign: the constraint trails a turning target by its own ~0.11 s.

### Fix
While the per-frame steer driver moves an AI Quin, it owns the facing:
- `SteerFacing` AlignOrientation, AutoRotate off.
- Target: the actual velocity, led by the motion's own turn rate × `Locomotion_FacingLeadTime` (0.11 s, feed-forward for the constraint's lag), plus `Locomotion_FacingIntoTurn` (0.3) of the way toward the steer heading.
- Below `Locomotion_FacingMotionMinSpeed` (6) and in reversals it faces the heading as before.
- It yields (AutoRotate back on) whenever another AlignOrientation is active on the root: Fight's lock on its target, jumps, recovery, wall-runs and so on. It also yields when the steer goal expires, when a slide or PlatformStand takes over, and on `cancelSteer`.
- `Locomotion_FacingFollowsMotion = false` restores the old behaviour.

### Result

| R | facing vs motion before | after | heading jolts (6 s) before → after |
|---|---|---|---|
| 8 | 17° | -0.1° (max 1) | 51 → 4 |
| 14 | 14° | -0.2° | 6 → 0 |
| 20 | 12° | -0.1° | 6 → 2 |
| 27 | 9° | -0.1° | 3 → 0 |

### Regression notes
- The body tilt is untouched: it uses world acceleration, not facing.
- 16v16: 0 server errors. The client shows 2 unrelated sound-permission errors.

## 2. Torso-to-head shiver (ProceduralCombatReactionController secondary motion)

### Method
- Client, 16v16, sampled at `PreAnimation` (the pose that was rendered).
- Counted per joint against its parent bone, and the head against the root: direction reversals (> 0.3°/frame on consecutive frames, opposite directions).
- Layers switched off in alternating blocks.

### Found
With the spine springs on, the upper spine joints reversed 4.2-6.8 times/s (p90 11). With only the spine springs off: 1.2/s. Head vs root: 3.9/s median, 11.8 for the worst Quin.

### Causes
1. **World-space springs.** The springs tracked the bone tips in world space, through the body's replicated position, which arrives in steps (and far Quins' animation is stepped too). On short spine bones a few hundredths of a stud of that became degrees of turn every frame.
2. **Torso spring tuning.** The torso used the arms' 6 Hz under-damped spring, so it overshot and rebounded.
3. **Huge accelerations.** Projectile-jump launches and knockbacks (thousands of studs/s²) pushed the springs past their 4-stud reset distance every other frame, so bones flipped between bent and straight.

### Fixes
- **Body frame:** springs run in the body's frame. Replication steps cancel; sway comes from the body's acceleration (`leanAcceleration`, scaled by `SecondaryMotion_Inertia`) plus the clip's own motion. The physics is the same as before: the world-space spring already ignored steady velocity.
- **Acceleration input:** capped at `SecondaryMotion_MaxAcceleration` (80 studs/s²), with its own low-pass (`SecondaryMotion_AccelerationResponse` 6/s).
- **Torso spring:** spine and neck get a heavier one, `SecondaryMotion_TorsoFrequency` 3.5 Hz and `SecondaryMotion_TorsoDamping` 1.0 (no overshoot). The arms keep 6 Hz / 0.75.
- **Soft leash:** a spring further than `SecondaryMotion_Leash` (1.5 studs) from its tip is held at the leash instead of being reset.

### Result (grounded states, reversals/s: median / worst Quin)

| | before | after | spine springs off |
|---|---|---|---|
| head vs root | 3.9 / 11.8 | 1.2 / 3.4 | 0.7 / 2.1 |
| upper spine joint | 6.8 / ~11 | 4.0 / 6.3 | 1.1 / 2.6 |

The remaining extra at the spine joints is mostly the spring holding its tip steady against wobble below it (a counter-rotation), which steadies what is seen.

### Ruled out (measured)
- **Animator skipping frames** (multiplicative bone writes stacking): it rewrites the clip pose on 99-100% of frames.
- **The head-look controller's aim:** LookYaw is smooth frame to frame.
- **Frame rate:** steady at ~48 fps.
- The large "jerk" windows seen with whole-body angle metrics were projectile-jump dives and flips (gimbal lock at a vertical head pitch), not vibration.

## Open
- **Not checked on screen:** no visual confirmation of the shiver fix by the owner yet.
- **Spine sway:** if the owner still sees some, `SecondaryMotionTorso = "none"` (live switch) or a lower `SecondaryMotion_MaxSpineDegrees` takes the spine sway out entirely.
- Sharp pivots and 180s (#2) are not done; next in this batch.
