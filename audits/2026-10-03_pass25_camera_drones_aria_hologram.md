# Pass 25: camera bob and first-person smoothing, drones, Aria timing, ducking, hologram, generation bar

Owner list (11 fixes). All edits are in Studio, exported to `studio_snapshot/`, and tested in Play.

## Changes

| # | Fix | Where |
|---|---|---|
| 1 | Orbit camera (spectator and Play As Quin, zoomed out) follows the hips bone's vertical motion: `bodyBobScale` 0.85, max ±1.6 studs, 18/s smoothing, rest height adapts slowly | `SmoothCamera` |
| 2 | First person: yaw/pitch smoothed at `orbitSmoothness`, eye position lerped at `posSmoothness` | `SmoothCamera` |
| 3 | The watched drone hides itself for that viewer: parts `LocalTransparencyModifier = 1`, Trail/Light/BillboardGui off; restored when switching | `ArenaDroneClientController` (`hideOwnDrone` / `showOwnDrone`) |
| 4 | Combat chase drone: holds a target 8 s (`CHASE_HOLD_TIME`), smoothed position/look/heading (1.6 / 2.6 / 1.0), offset 32 back, 15 up, 10 right, bank 0.2 | `ArenaDroneTrajectories` |
| 5 | Drone parts and trails 50% transparent; name labels fade after 3 s (`DroneVisuals.LabelMode` = `"fade"` / `"show"` / `"hide"`) | `ArenaConfig.DroneVisuals`, `ArenaDroneManager.applyDroneLook` |
| 6 | "Arena generation complete" now plays when the generation phase finishes (the 55% line was removed) | `ArenaSystemOrchestrator` |
| 7 | 5 s gap (`ArenaConfig.AriaGapAfterGeneration`) before the preparation-room line | `ArenaSystemOrchestrator` |
| 8 | Music ducking at about 40% (`DuckingMultiplier` 0.60) | `ArenaConfig` |
| 9 | Hologram hover moves the screen too: lazy part lookup every 1 s, because StreamingEnabled had the screen missing at script start | `LiveFeedScreen` |
| 10 | The globe hovers; the ring pivots with the globe, tilted 18°, radius 80 | `LiveFeedScreen` |
| 11 | Glitch on appear and disappear: flicker and jitter on the globe, ring panels and screen MainFrame | `LiveFeedScreen`, `ArenaScreenManager.setHologramActive` |
| 11b | The generation loading bar moves through stages with a percentage; `ArenaScreen.setGenerationProgress(fraction, stage)` is the hook for the arena generator | `ArenaScreenManager` |

## Measurements (Play)

- **Hologram (client):**
  - screen moved 12.5 studs in 1.6 s;
  - globe hover range 19.8 studs over 8 s;
  - ring tilted 18°.
- **Arena sequence:**
  - ARENA_OPEN 0 s, GENERATION 10.1 s, PREPARATION_ROOM 25.3 s.
  - GenerationCompleted line at 25.3 s, PrepGuide at 32.6 s (line plus 5 s gap).
  - Bar 0% → 93% through the stages.
- **Drones (server, IN_GAME):** all 5 have body transparency 0.5, trail 0.5, labels disabled after the fade.
- **Drone hide (client, key 4 = CombatChase):**
  - CombatChase: LTM 1, trail and light off;
  - the other 4: LTM 0, trail and light on.
- **Chase camera:** step 0.12 studs/frame average, 0.64 peak over 90 frames (no jumps).
- **Orbit bob (possessed, walking):** camera height relative to the root oscillates 0.21 studs, with 7 direction changes in 4 s (in step with the gait). Before this pass it was flat (`strideBobScale` 0).
  - A sprint sample wasn't possible: the possessed costume sat at client WalkSpeed 0 during the fight.
- **First person:** at minimum zoom, scrolling in enters it.
  - Costume LTM 1; camera 0.34 studs from the head bone.
  - Scrolling out restores LTM 0 and the orbit.
- **Regression:**
  - Arena match to IN_GAME (4v4), 0 errors;
  - P possess OK;
  - 16v16 (`team:16`): 32 Quins, 0 script errors in 45 s.

## Notes

- Drone label mode is a config switch; for always-on or always-off labels, set `ArenaConfig.DroneVisuals.LabelMode` to `"show"` or `"hide"`.
- Next: procedural crowd FX, then procedural arena generation (it drives `setGenerationProgress`).
