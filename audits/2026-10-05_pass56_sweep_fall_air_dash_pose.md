# Pass 56: Swept fall without the spin; air dash pose and effects

The owner watched the looping demo and said two things:
- The flipping Quin after a slide tackle "looks odd, something is not right".
- The dash off the wall looks odd. They asked for the dash effects and sound, and to reuse the ninja jump's start animation briefly.

## The odd flip: cause

Pass 54 spun the victim's root 180° over 0.4 s. That leaves the body upside down, effectively landing on its head.

Every other knockdown keeps the root upright (KnockbackState's stabiliser) and lets the fall clips (FallBack / FallFront) lay the body down. At touchdown, RecoveryState turns a tipped root upright with a torque, while it plays a get-up clip that starts lying down. So the swept Quin was rotated upright and lifted by the clip at the same time: it got up twice.

## Changes

**`Modules/SlideTackle`: no root spin.**
- The victim's side is worked out at the sweep: the trunk topples against the sweep (weight `SlideTackle_Topple` 1), plus the victim's own velocity divided by `SlideTackle_MomentumSpeed` 30. If that points the way it faces, it falls on its front; otherwise on its back.
- So a Quin standing with its back to the slide falls on its back, one facing it falls on its face, and a runner swept head-on goes down forward.
- It is published as `SweepFallSide`. `SweepSpin`, `FlipDegrees`, `FlipTime` and `SlideTackle_FallSide` are gone.
- `SlideTackle_Launch` drops from 45 to 30.

**`States/KnockbackState`.** A swept Quin skips the flailing clip and the random tumble. It plays the fall clip for its side from the first frame (Action4) with the root kept upright, `FallSide` is set at once, and Recovery gets it up from that side.

**`Modules/AirDash`: pose and effects.**
- The `Movement.AirDash` slot now borrows `ProjectileJump.NinjaJump` (the push-off). It plays at 1.4× for the burst, is held 0.1 s past it, then faded out over 0.15 s.
- The vapour cone runs 0.4 s, the ground dash's length.
- A shockwave puff (7 studs) is added where it pushes off.
- The dash sound is unchanged.
- Config: `AirDash_ClipSpeed`, `ClipHold`, `ClipFade`, `ConeTime`, `PuffSize`.

## Demo for the owner

Two Quins only (`DevCommand "team:1"`), camera free, in a loop until Workspace `DemoLoop` is false:
1. A wall run along the straight arena wall, alternating direction, with the target standing within dash reach of the run's end.
2. A head-on slide tackle: both chase each other.

Holding a target still by anchoring it did not work for the tackle demo. Releasing it at 6 studs popped its feet up (0.3–0.8 studs, so the slide passed under). Releasing it at 14 studs let its AI walk out of the lane.

First 40 s of the loop:
- Wall runs: `ArcSpent` 1.35 / 0.83 / 1.35 / 1.40 s; the dash off the wall fired on 3 of 4.
- Tackles: 2 of 3 swept, one falling on its back and one on its front.

## Not checked

- **By eye (owner):** the new fall, and the ninja push-off pose in the air dash.
- **Fall-side split:** only two sweeps were recorded, so the split is not measured over many.
