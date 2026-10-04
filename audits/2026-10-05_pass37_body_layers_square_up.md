# Pass 37 (2026-10-05): body layer switches, chest squared in a strafe

First two steps of `PROCEDURAL_PORT_PLAN.md` (lane D's mechanics into QuinCore).

## What was built

- **`Modules/Procedural/Layers`** - one registry for every procedural rule on the body.
  `Layers.isOn(name, quin)` is decided, first match wins, by: the Quin's own attribute
  `Layer_<Name>`; Workspace `LayerSplit = "odd"` (every other Quin, by the letters of its name,
  goes without the added layers); the layer's Workspace attribute; its `CombatConfig` default.
  `Layers.set`, `Layers.preset("Default" | "Legacy" | "None" | "All")`.
- The six existing switches in `ProceduralCombatReactionController` (`BodyTilt`, `FootPlant`,
  `PlantWhenStill`, `PivotPin`, `SecondaryMotion`, `ProceduralStyle`) now ask the registry. Same
  attribute names, same defaults.
- **`Modules/Procedural/SquareUp`** - the strafe fix. While a strafe clip plays (the six
  `Strafe.*` clips; `Tactics.RetreatBackstep` borrows one of them), the shoulders' turn off the
  facing is measured, averaged (5/s) and taken back out over Spine, Spine1, Spine2; the neck is
  turned back by the same amount so the head stays where the clip and `LookController` put it.
  Runs at the top of the controller's update, before anything else reads the spine.
  Config: `CombatConfig.ProceduralLayers.SquareUp`.
- **`QuinDebugHUD`**: a "Body:" row per layer, the split switch and three presets (replacing the
  three hand-written motion toggles).

## Measured (16v16, split on, one match, 40 s, steady strafes only)

Chest heading off the facing, signed toward the travel, read after the pose edits:

| | samples | mean | RMS | over 25 deg |
|---|---|---|---|---|
| Legacy half | 1321 | 40.8 deg | 45.1 | 84 % |
| Squared half | 286 | -5.0 deg | 12.8 | 3 % |

Head (mean absolute yaw off the facing, all strafe samples): 17.7 legacy, 18.6 squared: the head
is not dragged round. Hips: 44.6 / 45.2, untouched. No script errors; 82 fps with 32 Quins.

## Measurement trap found

In the arena the pose edits happen in `AIGhostHandler`'s `RenderStepped` handler. A probe's own
`RenderStepped` handler and a `BindToRenderStep` callback (even at `Last + 100`) both run before
it and read the unedited clip pose (both halves showed 42 deg). Read from
`RenderStepped:Connect(function() task.defer(sample) end)`.

## Not done

- The permanent ablation probe (`DevCommand "layer_ablation"`) and the baseline table for the
  other layers: the numbers above came from a one-off probe.
- The squared half had few samples (286) and overshoots by about 5 deg; not tuned.
- Not looked at by eye, no screenshots. Diagonal strafe blends and the retreat backstep were not
  measured separately. Whiff baseline not re-measured (the layer does not act outside strafe
  clips).
- IK Lab round 7 arm / thigh layers still unmeasured.
