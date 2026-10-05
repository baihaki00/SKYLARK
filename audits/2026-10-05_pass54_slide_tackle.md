# Pass 54: Slide tackle and hurdle (combination moves, item 21)

**Owner item 21:** a slide tackle against a timed jump over it. If the tackle connects, it takes the legs, and the victim falls forward, rotating about 180 degrees (ragdoll-like).

## What was there

ChaseState's "tactical gap-close slide" ran in when the target was 18–35 studs away and ended short, at striking distance. It touched no one.

## What it does now

**New module: `Modules/SlideTackle`.** `SlideTackle.slide(fighter, humanoid, rootPart, target)` starts the slide. It is called from ChaseState instead of `LocomotionModule.slide`. `LocomotionModule.slide` takes two new options:
- `aim`: a direction to turn the slide onto, if it is within `maxTurn` of the run;
- `onGlide(t, speed, dir)`: called every frame of the glide (the low part of the clip).

**Aiming.** The slide is aimed at where the target will be when it gets there (its motion, led up to 0.8 s). A target more than 40° off the slider's run gets no tackle.

**When to slide.** The slide is decided once per approach, then waits until the run lines up. The window is now 8–19 studs to the target, because the glide covers about 17 studs at a run plus the legs' reach. The old 18–35 window never got there.

**The sweep.** In the glide, an enemy in the lane (within 4.5 studs ahead and 2.5 to the side) whose feet are still within 2.5 studs of the ground is swept:
- damage goes through `DamageModule.apply` (×0.8; guards, protections and duel rules apply);
- a launch of 45 studs/s up, carrying a share of the slide's speed;
- `ForceState` Knockback.

**The flip.** The body turns over 180° about the sweep's axis (dir × up). The legs go the slide's way and the head the other, which is a forward fall for a victim facing the slider. The turn is flown frame by frame over 0.4 s: an angular velocity alone was damped to about 90° before touchdown. KnockbackState skips its random tumble and holds its stabiliser off for a swept Quin, which gets up from its back (`SlideTackle_FallSide`).

**The hurdle.** Each enemy in the lane gets one reflex roll, 0.32 s before contact. A Quin that is facing the slide, on its feet and not striking hops with chance 0.35 × (0.5 + mobility). The hop is 6 studs, using the new `Parkour.SlideHurdle` slot, which borrows Procedural Jump 01. The slide passes under the raised feet.

**Bug found and fixed.** ChaseState's hand-over to Fight at striking range stopped the slide clip, which ends the glide, so every tackle was cut off about 10 studs short. ChaseState now keeps a Quin whose slide is in progress (`LocomotionAction == "Slide"`). The slide owns the body anyway.

**Config and debug.**
- Tunables: `CombatConfig.SlideTackle_*`.
- Debug attributes: `TackleView` (target relative to the slide line), `TackleSkip`, `SweptAt`, `SweepSpin`, `SlideHurdledAt`, and Workspace `TackleStats`.
- Studio-only test switch: Workspace `SlideTackleAlways`.

## Measured

| Run | Slides | Sweeps | Hurdles | Blocked |
|---|---|---|---|---|
| Before the fixes, 16v16 | 132 | 4 | 2 | 0 |
| After, natural 16v16, 100 s (no switches) | 29 | 11 | 3 | 1 |

Before the fixes, slides went 10–20 studs to the side of their target.

**Demos staged for the owner** (2v2 on the strip by the arena wall, camera override):
- **Tackle:** slide from 16 studs, swept, turned 180°.
- **Hurdle:** hopped 10 studs, the slide passed under, not swept.
- **Air dash (Pass 53):** jump at 27 studs, dash, landed 7 studs from the target.
- **Wall run then dash (Pass 53):** 2.27 s run peaking 16 studs up, then a dash off the wall that landed 9 studs from the target.

**Health:** no script errors, except an unrelated DataStore message (Studio API access).

## Also found, not fixed

When `SpatialModule.detectWallRunSurface` fails at the start of a wall run, `WallRunState.enter` assumes the wall is on the Quin's left. A Quin with the wall on its right then probes empty air and drops off after 0.1 s (`WallEnd`). This is why staged runs failed in one direction and worked in the other. It may also cut some natural runs short, and belongs with items 11 and 12.

## Not checked

- **By eye (owner):** the look of the flip, the borrowed hurdle clip, and the landing on the back.
- **Rate:** 11 sweeps per 100 s of 16v16 may be often. `SlideTackle_*` and Chase's slide chance are the knobs.
