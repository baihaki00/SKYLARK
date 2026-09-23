# ARCHITECTURAL DECISION LOG (ADR)

This document records the foundational architectural decisions made during the evolution of the Quin project, including context, alternatives considered, chosen solutions, and invariant rationale.

---

## ADR 001: Physical Root vs Visual Skinned Mesh Decoupling
- **Date**: Early Architecture Milestone
- **Context**: Rigging skinned mesh humanoid models directly to Roblox physics caused ragdoll-like instability, animation collision snagging, and unpredictable PGS solver jitter during high-speed combat and knockbacks.
- **Decision**: Decouple the physical collider (`HumanoidRootPart`) from the visual body. Make the HRP an invisible, rigid box collider that dictates all spatial movement and collisions. Skinned meshes deform purely inside client presentation space.
- **Consequences**: Physical calculations never suffer from bone animation bounds; visual animations can be layered with procedural springs without destabilizing physics.

---

## ADR 002: Client-Side Ghost Replication (`Workspace.QuinGhost`)
- **Date**: Visual Performance & Animation Overhaul
- **Context**: Replicating 60fps procedural bone transforms (`mixamorig:Spine`, `mixamorig:Head`) across the server network boundary introduced noticeable latency, network saturation, and client stutter.
- **Decision**: Server characters are rendered 100% transparent (`Transparency = 1`). `AIGhostHandler.lua` creates local skinned mesh clones inside `Workspace.QuinGhost` on each client, lerping root positions at 60 Hz and evaluating procedural bone transforms locally.
- **Consequences**: Zero server CPU spent on bone deformation; smooth 60fps procedural gaze and combat reactions; zero network overhead for skeletal flinches.

---

## ADR 003: Continuous Explainable Target Utility vs State Trees
- **Date**: Tactical Combat Overhaul
- **Context**: Hardcoded `if/else` targeting logic caused target flip-flopping, blind tunnel-vision, and inability to handle dynamic tactical changes (e.g. retreating from a 3v1 or assisting a dying ally).
- **Decision**: Implement `TargetingModule.lua` as a continuous utility scoring function:
  $$U(\text{target}) = W_{\text{threat}} \cdot T + W_{\text{dist}} \cdot D + W_{\text{elem}} \cdot E + W_{\text{vuln}} \cdot V$$
  Personalities (`PersonalitySystem.lua`) tune the weights $W$ dynamically.
- **Consequences**: Emergent, explainable targeting decisions. The simulation harness can deterministically test target selection by injecting mock perception states.

---

## ADR 004: Non-Accumulating Procedural Skeletal Layering Contract
- **Date**: Procedural Combat Reaction Milestone
- **Context**: Naive procedural offsets applied via `Bone.Transform = Bone.Transform * CFrame` recursively compounded every frame, causing necks and spines to distort, twist into knots, or drift permanently from the animated pose.
- **Decision**: Codify the strictly idempotent evaluation contract:
  $$\text{FinalPose} = \text{EvaluatedFBX} \times \text{ReactionOffset} \times \text{LookAtOffset}$$
  Because Roblox evaluates the authored animation track into `Bone.Transform` fresh each frame before `RenderStepped`, multiplying by a zero-decaying spring is mathematically idempotent and automatically returns to baseline.
- **Consequences**: Perfectly stable skeletal deformations with zero drift over infinite match runtimes.

---

## ADR 005: Arena-Scoped Entity Isolation & World Model Filtering
- **Date**: Baseline Stability Milestone
- **Context**: The spectator HUD and camera were scanning `Workspace:GetChildren()`, erroneously detecting distant static editor test rigs (`QuinTest`, `QuinTypeA`) and rendering blank or corrupted cards on game start.
- **Decision**: 
  1. All arena combatants are strictly spawned under `Workspace.QuinServer`.
  2. Every arena fighter is tagged with CollectionService `"Quin"` and assigned a `QuinInstance` UUID.
  3. `QuinDebugHUD.lua` and `SmoothCamera.lua` query only `Workspace.QuinServer` and explicitly reject models lacking arena verification.
- **Consequences**: Spectator HUD and camera display exactly 0 cards in idle mode, exactly 2 cards in 1v1, and exactly 8 cards in 2v2. Complete isolation from editor/world test rigs.

---

## ADR 006: Preservation of Frozen Canonical Baselines
- **Date**: Persistent Engineering Milestone
- **Context**: Unverified exploratory changes risked regressions across established combat milestones.
- **Decision**: Before beginning any new milestone, freeze the exact verified state into:
  1. Studio Edit DataModel: `ServerStorage.QuinCore_Frozen_Stable_<TIMESTAMP>_<TAG>`
  2. Local Disk Backup: `scratch/backup_frozen_stable_<TIMESTAMP>_<TAG>/`
- **Consequences**: Instant, lossless rollback capability. Architectural continuity is preserved across all development sessions.

---

## ADR 007: Lightweight Execution Checkpoint Tracing vs Line Debugging
- **Date**: 2026-09-20
- **Context**: Diagnosing complex state machine, physics, and animation transitions required stepping through code in Studio or manual print statements. Tracing every line every frame is computationally prohibitive and creates visual noise.
- **Decision**: Implement `RuntimeTracer.lua` using `debug.info(2, "sln")` at discrete, meaningful checkpoints (state entries/exits, ground contacts, attack combos, track plays). Replicate via compact `TraceBreadcrumb` and `TraceLog` string attributes.
- **Consequences**: Instant code-attribution (`KnockbackState.lua:142 → RecoveryState.lua:27 → AnimationModule.lua:291`) visible directly on the spectator HUD with negligible overhead.

---

## ADR 008: Authoritative AnimationTrack Inspection vs Inferred State Names
- **Date**: 2026-09-20
- **Context**: Displaying animation state based on FSM state name was inaccurate because underlying tracks have blending fade times, priorities, looping behaviors, or delays.
- **Decision**: Query the `Animator` directly on the Client (`Animator:GetPlayingAnimationTracks()`), resolve canonical names via `AnimationConfig.Registry`, and display the true authoritative track metadata (Name, Asset ID, Priority, Looped, Time, Speed).
- **Consequences**: Complete visual transparency. The developer can verify whether the character is truly playing `FallAirKnockback` or `GetUpGround` in real time.

---

## ADR 009: Dynamic Spectator HUD Text Wrapping & Unified Drag Camera State Machine
- **Date**: 2026-09-20
- **Context**:
  1. Long animation asset IDs and multi-line runtime execution traces clipped horizontally because `outerFrame` was only 360px wide and `TextWrapped` was false. Fixed card heights risked vertical truncation when lines wrapped.
  2. Freefly spectator camera locked the mouse permanently on first click without an `InputEnded` release handler. On subsequent clicks or when Studio/Roblox reset `MouseBehavior` to `Default`, a stale `cameraLocked = true` flag prevented `lockMouse()` from running again, locking the user out of mouse rotation while WASD continued to function. Furthermore, a 920x600 developer frame from `AnimationLabUI` was visible by default in the screen center, intercepting clicks.
- **Decision**:
  1. Increase `outerFrame.Size` width from 360px to 440px. Set `TextWrapped = true` and `AutomaticSize = Enum.AutomaticSize.Y` on both `textLabel` and `cardBtn`. Remove fixed height overrides in `Heartbeat`, letting the card resize automatically to fit wrapped trace text and logs.
  2. Implement a unified `updateMouseBehavior()` state machine in `SmoothCamera.lua` that responds to `isLeftMouseDown`, `isRightMouseDown`, and `isToggleLocked`. Add `InputEnded` to restore default mouse cursor immediately upon release.
  3. Implement `isClickOnGui` using `GetGuiObjectsAtPosition` filtered to interactive objects (`GuiButton`, `TextBox`, active `ScrollingFrame`) to isolate HUD clicks from camera drags.
  4. Sync mouse behavior changes and focus loss (`WindowFocusReleased`) to prevent desync.
  5. Default `AnimationLabUI.MainFrame` to `Visible = false` on startup with floating pill `⚔️ Quin Manager [M]` visible.
- **Consequences**:
  - Cards never clip text horizontally or vertically; breadcrumbs and trace logs wrap cleanly onto new lines.
  - Left Mouse click-and-drag camera look works reliably on the 1st, 2nd, and 100th attempt without lockouts.
  - Clicking on HUD cards selects Quins cleanly without moving the camera.
  - The 3D viewport is completely unobstructed on startup.

---

## ADR 010: GUI Hierarchy Matching for Window Drag Handles vs Camera Drag
- **Date**: 2026-09-20
- **Context**:
  - In ADR 009, `isClickOnGui` only checked if an object was a `GuiButton`, `TextBox`, or active `ScrollingFrame`.
  - When dragging the Quin Manager Menu (`MainFrame`), the user clicks on the `TitleBar` or `TitleLabel`, which are `Frame` and `TextLabel` instances. Because they are not buttons or textboxes, `isClickOnGui` returned `false`.
  - Consequently, clicking the menu drag handle was misclassified as clicking the 3D viewport, triggering `updateMouseBehavior()`, locking the mouse to center, and rotating the 3D camera instead of dragging the window.
- **Decision**:
  1. In `SmoothCamera.lua`, expand `isClickOnGui` to use `isTrulyVisible` and check if any object under the cursor belongs to `AnimationLabUI` or `QuinDebugGui`, or is explicitly marked `Active`.
  2. In `AnimationLabController.lua`, mark `MainFrame` and `TitleBar` as `Active = true` and bind both `TitleBar` and `TitleLabel` to the drag handler.
- **Consequences**:
  - The Quin Manager Menu is smoothly draggable by clicking anywhere on its title bar or title text without interfering with camera controls.
  - 3D camera navigation remains completely responsive when clicking outside open GUI windows.
