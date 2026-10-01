# 16v16 pass 13: foot placement, intercept range, head gaze fix

Backup: `ServerStorage.backup_pre_16v16audit13_20261001`. Base: pass 12 (`2dd19f1`).

## Requests (owner)
1. Intercept range at most 200 studs.
2. Quins have no eyes (mannequin heads).
3. Foot IK placement.

## 1. Intercept range
`CombatConfig.Intercept_MaxRange` changed from 300 to 200.

## 2. Head, not eyes, and a head-gaze bug
- Comments in Gaze, Senses, LookController, OverwatchState, Cognition and CombatConfig now say head. Sight is a cone around where the head points; nothing models eyes. `SpatialModule.getEyePosition` keeps its name (head-height point used across the code).
- **Bug:** `AIGhostHandler` wrote the head's shown pitch into `GazePitch` every frame on the client. That is the same attribute the server's `Cognition.Gaze` uses for the gaze target, and LookController reads it. The head chased its own output and stayed near level, so the pass 12 sky glances and the look-down from platforms were hardly visible.
- The client now writes `LookYaw` / `LookPitch`. Checked in play: the shown pitch reaches the gaze (gaze +45 shown +41..+44, gaze -35 shown -31..-36).

## 3. Foot placement (ProceduralCombatReactionController)

### What was there
- Foot IK was on (`FootIK_Enabled`), but it did nothing on flat ground by design and only adjusted foot height on steps and slopes. It was active 0.6% of the time in a 16v16.
- `FootIK_AnkleAlignment`, `FootIK_ToeFlexion` and `FootIK_GaitModulation` are read nowhere.
- The 4.2-stud reach clamp was longer than the legs (3.6 male, 3.9 female), so it never did anything.

### Measured cause
A client probe sampled feet within 0.05 studs of their rest height. Those feet slid at a median 6-12 studs/s while the body moved, and 31 studs/s when it was fast. Two sources:
- **Clip/body pace mismatch:** the feet follow the clip, not the ground.
- **Gliding:** the fight-idle stance clip plays while the body moves, mostly in Circling and Fight. The feet stay still under the body and the Quin glides, so 41% of moving foot-down samples moved at body speed.

### Why IKControl could not do it
IKControl writes its result into `Bone.Transform` (checked: hand-built leg chain = IK target). Once it was on, the clip's own foot position was gone. A pinned foot then always looked still and pinned, and the plant only let go when the leg overstretched. The first attempt, built on IKControl, barely changed the numbers.

### What it does now
- **Leg solve:** two bones, written into the thigh/shin/foot `Transform` in RenderStepped after the Animator. This is the same place the controller already edits the hips and spine.
  - The knee bends in the plane the clip bends it in.
  - If the clip leg is nearly straight, or the knee would point backward, the knee bends forward.
  - The foot keeps the clip's orientation.
  - The IKControl instances stay, but disabled; their `Weight` mirrors the solver for the Animation Lab and telemetry.
- **Plant:** a foot that comes down (within `FootIK_PlantContact` 0.15 of rest height) is pinned there until the clip lifts it (`FootIK_PlantLift` 0.35).
- **Release:** if the clip drags the foot more than `FootIK_PlantMaxDrift` (1.4 studs) away, or the leg would exceed 98% of its length, the foot lets go. It fades back to the clip from the pinned spot instead of snapping.
- **Step** (`FootIK_Step`): when a pinned foot falls behind and the clip does not lift it, the foot takes an arc step and plants again.
  - Lands just ahead of where the body is going, within the leg's reach.
  - Arc 0.25-0.7 studs; 0.14-0.3 s depending on speed.
  - One foot at a time.
  - If the clip lifts the foot during a step, the clip takes over.
- **No plant or step** while an `ImpulseLV` push runs (flinch slide, lunge, dash), during a landing skid, in the air, in Knockback/Recovery, or on PlatformStand. Those slides are intended.
- **Pelvis:** may sink up to `FootIK_MaxHipsDip` (0.6, was a fixed 0.15) so the lower foot reaches a lower surface (platform edge, step).
- **Switch:** workspace attribute `FootPlant` (true/false) overrides `FootIK_Plant` live, on the client, for A/B.

### Measurements
One 16v16 match, alternating 20 s blocks with `FootPlant` off/on (3 cycles), client probe in PreAnimation (the final pose). "Slide" = horizontal speed of a foot within 0.05 of its rest height, not being pushed.

| | off | on |
|---|---|---|
| standing: slide > 3 studs/s | 23% | 9% |
| moving slowly (2-20): median slide | 6.4 | 1.7 |
| moving fast (> 20): median slide | 31.8 | 0.9 |
| gliding (foot moving at body speed) | 41% | 21% |
| knee pointing backward | 1.1% | 0.5% |
| leg at full length | 1.5% | 4.8% |

- An earlier run of the same build without the knee rule gave the same picture (fast median 31.7 → 1.2, glide 41% → 20%).
- Capping leg length at 97% removed most straight legs, but made standing feet jerk (dragged with the hip). It was reverted.
- 0 server and 0 client errors.
- Screenshots: a circling Quin with one foot planted and one mid-step; a running Quin with the front foot planted and the back foot on its toes; knees forward.

## Open
- Legs are fully straight more often (4.8% vs 1.5%), mostly standing legs reaching a pinned foot. Not visible in the screenshots; watch for knee pops.
- The 90th-percentile slide while moving is still high (14-43 studs/s): feet the clip drags faster than a step can follow, and fades after a release.
- Ankle alignment to slopes and toe flex are still not implemented (config keys exist, unused).
- The fight-idle stance during Circling is the real source of the glide. A strafe/shuffle clip would fix it at the root; the steps cover it procedurally.
