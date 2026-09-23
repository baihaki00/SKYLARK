# CURRENT_STATE.md

## Current Milestone
**Draggable Quin Manager Menu, GUI Click Hierarchy Isolation & Full Spectator HUD Trace**

## Canonical Baseline
- **Studio Frozen Artifact**: `ServerStorage.QuinCore_Frozen_Stable_20260920_QuinManagerMenu_Draggable_And_CameraIsolated_Verified` (83 descendants)
- **Local Frozen Artifact**: `scratch/backup_frozen_stable_20260920_QuinManagerMenu_Draggable_And_CameraIsolated_Verified` (57 `.lua` source files)
- **Studio Runtime**: Active Play mode running verified baseline.

## Working Subsystems
- **Draggable Quin Manager Menu & Camera Input Isolation (`AnimationLabController.lua`, `SmoothCamera.lua`)**:
  - `MainFrame` and `TitleBar` are explicitly marked `Active = true`. Both `TitleBar` and `TitleLabel` trigger `handleDragStart`, allowing seamless window dragging across the screen.
  - `SmoothCamera.lua` uses `isTrulyVisible` and hierarchy matching (`AnimationLabUI`, `QuinDebugGui`, interactive controls, active frames) so clicking or dragging the Quin Manager Menu never hijacks the mouse or triggers 3D camera rotation.
  - Viewport dragging works reliably across empty 3D space on subsequent clicks while all UI windows remain fully interactive and movable.
- **Dynamic Spectator Card Layout (`QuinDebugHUD.lua`)**:
  - Full execution trace (`TraceBreadcrumb`), multi-line timestamped checkpoint history (`TraceLog`), and authoritative animation metadata (`Id`, `Time`, `Speed`, `Priority`, `Loop`) are **open by default for all combatant cards** without requiring selection or key toggling.
  - `outerFrame` widened to `440px` (from `360px`).
  - `textLabel.TextWrapped = true` with `AutomaticSize = Enum.AutomaticSize.Y`.
  - `cardBtn` utilizes `AutomaticSize = Enum.AutomaticSize.Y` with `UIPadding` (left=8, right=8, top=6, bottom=8).
  - Cards dynamically and automatically resize according to text volume; long trace breadcrumbs, asset IDs, and multi-line logs wrap to new lines with zero clipping or text truncation.
- **Robust Spectator Camera Drag & Input Handling (`SmoothCamera.lua`)**:
  - Unified `updateMouseBehavior()` state machine tracking `isLeftMouseDown`, `isRightMouseDown`, and `isToggleLocked`.
  - Left Mouse Button (and Right Mouse Button) supports seamless hold-and-drag camera look on the 3D viewport, restoring default cursor on release without permanent desync.
  - Subsequent left-click drags ("the second time", third time, etc.) work reliably across all match states.
  - Focus loss (`WindowFocusReleased`) and `MouseBehavior` property change synchronization prevent hidden lockouts or stuck mouse states.
- **Unobstructed Viewport Startup (`AnimationLabController.lua`)**:
  - `MainFrame` (920x600 menu) is hidden by default (`Visible = false`); floating pill `⚔️ Quin Manager [M]` is visible.
  - Prevents the center of the battlefield from being occluded or having clicks intercepted by the developer menu.
- **Runtime Execution Tracer (`RuntimeTracer.lua`)**: Reusable reflection-based tracer capturing exact script source, line numbers, and timestamps via `debug.info(2, "sln")`. Replicates compact breadcrumbs (`TraceBreadcrumb`) and checkpoint event logs (`TraceLog`) across state boundaries, combat triggers, and physical events with zero per-frame line flooding.
- **Authoritative Animation Inspector (`QuinDebugHUD.lua`)**: Directly inspects active `AnimationTrack`s from the `Animator` (Name, Asset ID, Priority, Looped, Playback Time, Speed) with dynamic friendly-name reverse lookup via `AnimationConfig` registry.
- **Persistent Quin Identity**: `QuinInstance` schema separates chassis `Type` (TypeA/B/C/D) from elemental attunement (`Element`), with UUID, personality, and records.
- **Personality-Driven Decision Intelligence**: `TacticalPerception` creates 45-stud `LocalBattlefieldState`; `TargetingModule` computes continuous explainable target utility; `DecisionSystem` evaluates tactical candidates (attacks, rescues, retreats).
- **Procedural Gaze Tracking (`LookController.lua`)**: Biomechanical 3-zone distribution (Head 0-30°, Head+Neck 30-60°, Head+Neck+Spine2 60-100°) dynamically tracking active opponent or distressed ally.
- **Procedural Combat Reactions (`ProceduralCombatReactionController.lua`)**: Directional impulse recoil spring (pitch/roll/yaw) + hips stagger + dynamic impact compression distributed multiplicatively across spine chain.
- **Visual Ghost Architecture (`AIGhostHandler.lua`)**: Server models have `Transparency = 1`; client-side skinned mesh ghosts smoothly interpolate root CFrame and layer procedural bone transforms.
- **Spectator Camera & Arena Scoping (`SmoothCamera.lua`, `QuinDebugHUD.lua`)**: Elevated overview at `(0, 140, 160)` angled -38°; Left HUD tracks **only** arena Quins inside `Workspace.QuinServer`, strictly filtering static world rigs (`QuinTest`, `QuinTypeA`).
- **Deterministic 11-Scenario Simulation Harness (`BattleSimulationHarness.lua`)**: Automated test harness covering 1v1 through 16v16 and benchmark profiles with 100% invariant satisfaction.

## Known Subsystem Boundaries & Open Areas
- **Knockback Physics Pipeline**: Stable baseline preserved. Future work will diagnose true physical landing trajectories before modifying flight curves.
- **Airborne / Wall Collisions**: Wall bounce telemetry exists in `KnockbackModule` but requires continuous normal deflection polish.

## Invariant Hard Contracts (DO NOT MODIFY WITHOUT ARCHITECTURAL APPROVAL)
1. `PHYSICS ≠ VISUALS`: Root movement is owned by `HumanoidRootPart`; posture, flinch, and gaze are owned by skeletal `Bone.Transform`.
2. Layering Contract: $\text{FinalPose} = \text{EvaluatedFBX} \times \text{ReactionOffset} \times \text{LookAtOffset}$ (strictly idempotent per frame).
3. Arena Scoping: Spectator HUD and targeting must only query `Workspace.QuinServer` and models tagged `"Quin"`.
4. Execution Tracing: Never trace every Lua line every frame. Tracing is strictly event- and checkpoint-driven via `RuntimeTracer.checkpoint`.
5. Camera Ergonomics: Viewport dragging must never get locked out on subsequent interactions; GUI clicks must never bleed into camera rotation.
