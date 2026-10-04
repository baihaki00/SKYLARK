# Plan: lane D's body mechanics into QuinCore, with ablation

Written 2026-10-04. Nothing in this plan is built yet.

## Goal

Arena Quins get the lane D mechanics that are worth having, each one a layer that can be
switched off and on while a match runs, so every layer can be judged by eye and by numbers
against the same match without it.

## What QuinCore already has (read from the code)

- All body procedural work runs on the client, per Quin, in `AIGhostHandler`'s render step, once
  per fresh animation step: `ProceduralCombatReactionController:update` and then
  `LookController:update`.
- `ProceduralCombatReactionController` (68k characters) already does: hit reaction, force lean,
  the whole-body running tilt, foot planting and stepping, pelvis dip, toe flex, and arm / spine
  follow-through (`SecondaryMotion`).
- Its leg solver is its own two-bone solve written into `Bone.Transform`. The `IKControl`s are
  kept off. The clip's foot stays readable, so nothing has to be baked.
- Switches already exist as Workspace attributes with a `CombatConfig` default: `BodyTilt`,
  `FootPlant`, `PlantWhenStill`, `PivotPin`, `SecondaryMotion`, `SecondaryMotionTorso`,
  `ProceduralStyle`, `BodyAwareness`. Three of them have buttons in `QuinDebugHUD`.

Consequence: lane D's *code* is not moved across (it is built on `IKControl` and baked clips).
Its *rules and tuned numbers* are, written against QuinCore's pose pipeline.

## Which lane D layers are ported

| Lane D layer | In QuinCore today | Plan |
|---|---|---|
| SquareUp (chest back to the front in a strafe) | nothing | **Port, phase 1.** The strafe fix |
| KneeOverToe | nothing | **Port, phase 2**, into the leg solver's knee direction |
| Weight (dip on each footfall) | pelvis dip for uneven ground only | **Port, phase 2** |
| ArmClear (arms never inside the trunk) | nothing | **Port, phase 3** |
| SoftElbows (no locked straight arm) | nothing | **Port, phase 3** |
| ArmLag hand spring | upper arm and forearm only | **Extend, phase 3** (add the hand) |
| HipTwist, SpineCounter | nothing | **Port, phase 4** |
| Breath | nothing | **Port, phase 4** |
| ThighTwist | not needed in theory: it corrects an `IKControl` side effect | **Measure first** (phase 2); port only if the thigh rolls |
| Lean, SlopeLean | force lean + whole-body tilt | Not ported. The tilt stays as it is |
| PelvisSpring | hips dip | Not ported |
| Toes | toe flex | Not ported |
| Look | `LookController` (same module) | Already shared |
| StrideWarp | `GaitModule` matches clip rate to speed | Not ported unless a measurement shows foot slide it would fix |
| Point, Contact | nothing to point at or hold in the arena | Not ported now |
| Inertial, KneeHinge, Props | | Not ported (off in the lab, no measured gain) |

## Ablation design

1. **One registry, `QuinCore/Modules/Procedural/Layers`.** `Layers.isOn(name, aiModel)` answers
   in this order:
   1. attribute `Layer_<Name>` on that Quin (one Quin on or off);
   2. Workspace attribute `Layer_<Name>` (all Quins);
   3. Workspace attribute `LayerSet`: `"all"`, `"none"` or `"legacy"` (only what exists today);
   4. the default in `CombatConfig.ProceduralLayers`.
2. **Old switches keep working.** `BodyTilt`, `FootPlant`, `PlantWhenStill`, `PivotPin`,
   `SecondaryMotion`, `ProceduralStyle` are registered as layers under their current names and
   attributes. No existing default changes.
3. **Side by side in one match.** Workspace attribute `LayerSplit = "team"` gives team A the new
   layers and team B the legacy set (or `"odd"` for every other Quin). Same match, same clips,
   same moment: the fairest comparison there is.
4. **No pops.** Every layer carries a 0..1 weight that eases to its switch (about 0.2 s), and
   writes nothing at weight 0.
5. **Buttons.** A "Body layers" list in `QuinDebugHUD` next to the three existing toggles: one
   row per layer, plus All / None / Legacy / Split.
6. **Numbers.** A probe (client, started by `DevCommand "layer_ablation"`) runs a 16v16, switches
   each layer off for 10 s in turn and writes one row per layer:
   - chest heading off the facing during strafe clips (deg);
   - share of planted steps with the knee more than 5 deg inside the foot, and mean excess;
   - frames with an elbow or wrist inside the trunk radius;
   - frames with an elbow under 10 deg from straight;
   - planted-foot slide (studs/s);
   - per-bone acceleration peaks for head, hands, knees, feet (the pop detector);
   - script time per Quin per animation step, and fps.

## Code shape

- New folder `QuinCore/Modules/Procedural/`: `Layers` (registry) and one small class per new
  layer (`SquareUp`, `KneeOverToe`, `Footfall`, `ArmClear`, `SoftElbows`, `TorsoTwist`,
  `Breath`), each with `new(ctx)` and `apply(ctx, dt, weight)`.
- `ProceduralCombatReactionController` owns the ordered list and builds one shared context per
  update (root frame, speed, acceleration, server state, bones, planted feet). It calls the pose
  layers after its own steps and before `LookController`.
- The existing 68k controller is not reorganised. Two touch points only: the layer loop, and one
  hook where the leg solver picks the knee direction (for `KneeOverToe`).
- `Spine2`, `Neck` and `Head` belong to `LookController`. `SquareUp` turns `Spine` and `Spine1`
  and hands the remainder to `LookController` as a chest offset, so the two never fight.
- Every layer is silent in the states the tilt already skips (Knockback, Recovery,
  ProjectileJump, MidAirClash, WallRun, Death, BeamStruggle) and fades out while a strike clip
  moves the limb fast, the way `SecondaryMotion` does today. Attacks stay as authored.
- Male and female use the same code; lengths come from the rig, not from constants.

## Phases

Each phase: build, switch on/off inside one 16v16, numbers before and after, screenshots, export,
audit note, commit, push.

0. **Scaffold, no behaviour change.** `Layers`, old switches registered, HUD list, `LayerSplit`,
   the ablation probe. Result: a baseline table for today's QuinCore.
1. **SquareUp.** The strafe fix. Target from the lab: chest about 44 deg off the facing down to
   under 10. Checked in Circling, Fight footwork and Retreat, including `GaitModule`'s diagonal
   blends.
2. **Legs.** Measure thigh roll and knee-inside-foot on the arena solver first. `KneeOverToe`
   (ground-only and eased, as fixed in round 7b), then `Footfall`.
3. **Arms.** `ArmClear`, `SoftElbows`, hand spring added to `SecondaryMotion`.
4. **Torso.** `TorsoTwist` (hips with the stride, chest against it), `Breath`.
5. **Stress and defaults.** Full ablation run, 16v16 and Arena match, cost per Quin, by-eye
   review by the owner with `LayerSplit`. A layer that shows no gain ships off by default.

## Before phase 0

Round 7 in the lab is only smoke-tested for the arm layers, thigh roll and chest squaring. They
need one measured run with the Studio window in front (they do not run while it is not drawing).

## Risks

- **The running tilt.** No layer writes the root or the hips' tilt. `BodyTilt` is in every
  ablation row as a check that it is unchanged.
- **Two writers on one bone** (`SecondaryMotion` spine follow and `SquareUp`, `LookController`
  and anything on the neck). Fixed order, one owner per bone, measured in phase 1.
- **Strikes.** A layer that bends an elbow or clears an arm during a punch would change reach
  and hit timing. Layers fade during strikes; the whiff baseline (66 % hit / 8 % whiff) is
  re-measured in phase 5.
- **Cost.** The lab measured about 35 microseconds per full Quin per animation step; 32 Quins is
  about 1 ms. Checked in phase 5.

## Decisions for the owner

1. Start order: strafe fix first (as above), or legs first?
2. `LayerSplit` by team or every other Quin as the default comparison?
3. New layers on by default as each phase lands, or all off until phase 5?
