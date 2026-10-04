# Pass 42 (2026-10-05): torso (phase 4) and a first stress run (phase 5)

## Hip twist with the stride: not ported

Lane D turns the hips with the leading foot and the chest against them. Measured on the arena's
clips first (16v16, forward travel in Chase / Retreat, clip pose before any layer):

| | Hips yaw swing (sd) | Chest yaw swing (sd) | Hips against the foot gap (r) |
|---|---|---|---|
| Walk | 7.0 deg | 11.5 deg | -0.54 |
| Run | 18.6 deg | 21.0 deg | -0.37 |

The clips already turn the hips and the chest through every stride, coupled to the feet. A
procedural twist on top would double an existing motion, so `HipTwist` / `SpineCounter` are not
ported. (The run figures include slides and landings played in Chase.)

## Breathing: ported, tied to energy

The three idle clips move the chest 2.5-5.2 deg over a loop of 2-8 s, the same whatever state the
Quin is in. The "exhausted" social clip has no animation yet. So the layer adds what the clips
do not carry: **`Procedural/Breath`** lifts the chest on Spine1 and Spine2 (the neck gives half
back), 0.25 breaths/s and 1.2 deg when fresh, rising to 0.9 breaths/s and 4.5 deg as energy runs
out (eased at 0.8/s). Each Quin breathes on its own beat. It fades out by 10 studs/s of travel
and while striking, guarding or thrown. Layer `Breath`, `Layer_Breath`, HUD row.

**Measured** (chest pitch the layers add to the clip, other spine layers switched off, Quins
moving under 2 studs/s and not striking, breath alternated on / off / on / off, 16 s each):

| Energy | Breath on | Breath off |
|---|---|---|
| Under 15 | 3.41 deg (n 23) | 0.33 deg (n 17) |
| 15-50 | 4.78, 3.40 | 1.56, 4.97 |
| Over 50 | 4.39, 4.98 | 3.84, 4.06 |

Only the first row is clean, and it is small: 3.4 deg against 0.3 for spent Quins (the layer's
4.5 deg sine has an sd of 3.2). In the other rows hit reactions, the look turn and the lean move
the chest by 4 deg with the layer off, and the 1.2-3 deg of breathing does not stand out of
that. Fresh-Quin breathing is therefore **not confirmed by measurement**.

## Stress run: cost

One 16v16, presets cycled Default / Legacy / None twice, 14 s each:

| Preset | Frames per second | Worst frame |
|---|---|---|
| Default (all 15 layers) | 41, 40 | 35 ms |
| Legacy (the 8 added layers off) | 42, 41 | 34 ms |
| None | 41, 41 | 36, 33 ms |

No measurable cost from the layers at 32 Quins (the probe itself and the window hold the rate
near 41; earlier unprobed runs showed 82). No script errors on server or client.

## Layer list now (QuinDebugHUD "Body:" rows)

Legacy: body tilt, foot planting, plant when still, pivot pin, arm follow-through, hip twist with
sideways travel, per-Quin style (off). Added by the port: chest squared in a strafe, strafe clip
carries the body, knee over toe, soft elbows, arms out of the trunk, loose wrists, breathing,
weight on each footfall.

## Still open in the port

- The permanent `layer_ablation` probe (every figure so far came from one-off probes).
- By-eye review with the split, and the decision on defaults: by measurement every added layer
  except Footfall, loose wrists and fresh-Quin breathing has shown a gain; those three are
  unconfirmed either way.
- Running knees only partly fixed (pass 38); fight footwork spinning with a strafe clip (pass 39).
- A real Arena match (orchestrator) with the layers on.
