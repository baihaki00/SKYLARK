# SKYLARK ISLES — CORE ARCHITECTURAL CONSTITUTION & REPOSITORY GUIDE

> **MANDATORY NOTICE FOR ALL AGENTIC AI ASSISTANTS & DEVELOPERS:**  
> Read this document completely before proposing or implementing changes. This document defines the non-negotiable architectural contracts, physics separation rules, and design philosophies of **Skylark Isles**. Do NOT drift from this plan. Do NOT re-introduce legacy bugs or hacky shortcuts.

---

## 1. Core Philosophy: Emerging Spectacle Over Scripted Scenes

Skylark Isles is a large-scale, anime-inspired fantasy world built on emergent physicality, competition, and living characters (Quins).
- **The Central Rule:** Build the rules, physical state, awareness, and consequences; **let the interactions create the spectacle**. 
- Never attempt to hardcode "cool anime moments" by faking physical state or freezing the character.
- Quins are persistent living combat entities with distinct personalities, classes, and elements. They are NOT generic Roblox NPCs.

---

## 2. The 6 Non-Negotiable Ground Rules

### RULE 1: PHYSICS ≠ VISUALS (The HRP is NOT the Quin)
- The `HumanoidRootPart` (HRP) is an **invisible physical simulation root**. It owns mass, velocity, acceleration, gravity, collision, and authoritative spatial position.
- The visible Quin is the **skinned mesh, skeleton, and procedural posing system**.
- **Physics ≠ Visuals. Position ≠ Pose. Velocity ≠ Animation. Ground Contact ≠ Standing Pose. Physical Rotation ≠ Visual Rotation.**
- Never force the visual mesh to rigidly mimic every instantaneous twitch of the HRP, and never distort HRP physics to fix an animation flaw.

### RULE 2: STATE = INTENT, LOCOMOTION = PHYSICS
- The **FSM State Machine** (`ChaseState`, `RetreatState`, `FightState`, `CirclingState`) is responsible ONLY for **Behavioral Intent**:
  - *"What does the Quin want to do?"* $\to$ Emits `DesiredDirection`, `DesiredSpeed`, `WantsJump`, `WantsBrake`, `HeadingDirection`.
- The **Locomotion Controller** (`LocomotionController.lua`) is responsible for **Physical Execution**:
  - *"How does the body physically achieve that?"* $\to$ Computes momentum, traction, acceleration, braking skids, centripetal steering arcs, and ground normal adaptation.
- **FORBIDDEN:** No FSM state may directly overwrite `AssemblyLinearVelocity`, create velocity constraints, or set `humanoid.WalkSpeed = 0` to halt movement.

### RULE 3: CONTINUITY OF MOMENTUM
- State transitions must **NEVER** arbitrarily destroy momentum.
- Transitioning from `Chase` $\to$ `Fight` must **NOT** snap velocity to zero. The Quin must visibly brake, slide slightly along the ground plane, and carry physical follow-through into its combat stance or opening strike.
- Touching the floor after a jump must **NOT** zero velocity. Forward momentum must be conserved across the landing.

### RULE 4: DEPRECATED BODY MOVERS ARE PERMANENTLY BANNED
- Legacy body movers (`BodyVelocity`, `BodyGyro`, `BodyPosition`, `BodyAngularVelocity`) are **strictly prohibited**.
- Use native `AssemblyLinearVelocity` and modern constraints (`LinearVelocity`, `AlignOrientation`).

### RULE 5: SINGLE SOURCE OF TRUTH (DRY CONFIGURATION)
- **Animations:** Single Source of Truth is `ReplicatedStorage.QuinCore.AnimationConfig`. All asset IDs, playback speeds, fade times, and priorities live here.
- **Combat & Locomotion Tuning:** Single Source of Truth is `ReplicatedStorage.QuinCore.CombatConfig`. No hardcoded magic numbers in state files.
- **Entity Stats:** Single Source of Truth is `ReplicatedStorage.QuinCore.QuinData`.

### RULE 6: BALLISTIC JUMP INTEGRITY (NO "FLYING PAPERS")
- Normal jumps must follow a coherent, single-impulse ballistic trajectory:
  $$\text{Grounded} \longrightarrow \text{Launch Impulse} \longrightarrow \text{Ascent} \longrightarrow \text{Apex} \longrightarrow \text{Descent} \longrightarrow \text{Landing Compression} \longrightarrow \text{Grounded}$$
- Multi-frame upward force stacking is forbidden.
- Start-of-match projectile jumps must never trigger automatically during basic locomotion. Normal jumps first.

---

## 3. Architecture & Dependency Flow

```text
┌─────────────────────────────────────────────────────────────┐
│                 BEHAVIORAL AI / STATE MACHINE               │
│        (Idle, Chase, Retreat, Circling, Fight, Special)     │
└──────────────────────────────┬──────────────────────────────┘
                               │ Emits LocomotionIntent each frame:
                               │ { DesiredDirection, DesiredSpeed, Heading, WantsJump, WantsBrake }
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     LOCOMOTION CONTROLLER                   │
│                    (Single Source of Movement)              │
├─────────────────────────────────────────────────────────────┤
│ - Momentum & Inertia Integration                            │
│ - Floor Traction & Dynamic Skids (180° Reversals)           │
│ - Centripetal Steering Radius (Prevents 2D cursor snapping) │
│ - Single-Impulse Ballistic Jumps                            │
│ - Landing Momentum Conservation                             │
└──────────────────────────────┬──────────────────────────────┘
                               │ Writes Authoritative Physics:
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     PHYSICAL ROOT (HRP)                     │
│  - Mass, AssemblyLinearVelocity, Ground Contact, Raycasts   │
└──────────────────────────────┬──────────────────────────────┘
                               │ Feeds Real Physical Vectors:
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                   VISUAL LAYER / GHOST SKELETON             │
│  - Torso Acceleration Lean & Braking Drag                   │
│  - Pelvis Counterbalance on Sharp Turns                     │
│  - Knee/Spine Landing Impact Compression                    │
│  - LookController Gaze & Procedural Combat Reactions        │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Development Workflow & Safe Iteration

1. **Always Backup Before Refactoring**:
   Create a timestamped directory `backup_pre_<task>_<date>` before touching structural components.
2. **In-Place Testing Over MCP Toggling**:
   Do not repeatedly toggle Play/Edit modes via StudioMCP (which triggers session locks). Use in-place match resets (`GameModeManager` and `QuinSpawner.cleanAll()`) inside the running session.
3. **Debug With Physics Telemetry, Never Guess**:
   Always inspect actual physical velocity vectors, traction ratios, and state handoffs before tuning animation or gameplay logic.

---

## 5. Domain-Driven Design (DDD) & Bounded Contexts

All systems in **Skylark Isles** must strictly respect their bounded contexts. Cross-domain circumvention is permanently forbidden:
1. **Behavioral Domain (`QuinCore.States`)**:
   - Owns intent, tactical decisions, target selection, and pacing strategies.
   - Must **NEVER** directly mutate physics (`AssemblyLinearVelocity`), manipulate raw motor joint C0s, or hardcode animation IDs.
2. **Locomotion & Physics Domain (`QuinCore.Modules.LocomotionModule`, `SpatialModule`, `KnockbackModule`)**:
   - Owns authoritative physics translation, momentum conservation, collision detection, and raycasting.
   - Executes the physical translation cleanly regardless of which visual animation is playing.
3. **Animation Domain (`QuinCore.Modules.AnimationModule`, `AnimationConfig`)**:
   - Owns playback layering, track priority tiers, crossfading, dynamic speed scaling, and overlay stopping.
   - Single Source of Truth for all animation assets, speeds, and priorities.
4. **Visual & Procedural Reaction Domain (`AIGhostHandler`, `ProceduralCombatReactionController`, `LookController`)**:
   - Owns the client visual skeleton (`QuinGhost`), bone transforms, secondary motion, head tracking, and impact flinches.
   - Physics strictly drives the visual layer; the visual layer never contaminates physical state.
5. **Telemetry & Sensory Domain (`AudioModule`, `VfxModule`, `BattleEventSystem`, `RuntimeTracer`)**:
   - Observes combat and emits audio-visual feedback and telemetry without dictating gameplay logic.

---

## 6. Anti-Bandaid Engineering Standard (Root Cause Over Symptoms)

> **MANDATORY NOTICE FOR ALL AGENTIC AI ASSISTANTS & DEVELOPERS:**  
> Never implement a shallow "immediate remedy" that treats a visible symptom by slapping on ad-hoc flags, hacky delays, or brittle state checks. 

1. **Trace the Pipeline**: When an entity slides, freezes, clips, or jitters, identify the exact handoff across **State Intent $\to$ Physics Execution $\to$ Animation Blending $\to$ Bone Transform**.
2. **Passing a Single Test ≠ Correct Solution**: If a code change makes a test pass but violates modular decoupling or introduces brittle state coupling, it is rejected.
3. **Preserve System History**: Understand why an existing architectural rule was established before modifying it. Do not rewrite foundational systems to fix a local edge case.

---

## 7. Tiered Animation Lifetime Contracts (Banned: Rigid State Whitelisting)

Never use rigid state-level track whitelisting (e.g. "only ChaseState can play Run, only FightState can play Punches"). Rigid whitelisting destroys cross-state momentum and causes abrupt visual snaps upon state transitions.

Instead, animations strictly follow **Tiered Lifetime Contracts**:
- **Tier 1: Base Locomotion (State-Governed, Priority `Movement` [1000])**:
  - `Idle`, `WalkConfident`, `Run`. Exactly one base locomotion track plays on loop. When a state requests a new base locomotion, the previous one fades smoothly.
- **Tier 2: Locomotion Modifiers (Cadence-Governed, Priority `Movement` or `Action` [1000–2000])**:
  - `ArcRun30`, `RunTurn180`, `IdleToRun1/2`, `BrakingStop`. Temporary overlays phase-locked to gait cadence. They automatically release bone control back to Tier 1 upon completion or when their active timer expires.
- **Tier 3: Physical Action Impulses (Momentum-Governed, Priority `Action` [2000])**:
  - `Dash`, `Slide`, `VaultObstacle`. These belong to the physical impulse. Their lifetime is bound to the duration of the physical propulsion. State machine transitions (e.g. Chase $\to$ Fight) do not prematurely abort these tracks mid-flight.
- **Tier 4: Reactions & Impacts (Event-Governed, Priority `Action4` [4000])**:
  - `HitLight`, `HitHeavy`, `KnockdownBehind`, `FallAirKnockback`. High-priority overlays that blend over the upper body while preserving lower-body physical momentum.

---

## 8. Active Spectacle Ragdoll & Impact Reaction Rules

1. **Strict Anatomical Joint Limits**:
   - Knees and elbows must have strict angular limits with zero twist and single-axis hinge motion (knees only flex backward 0° to 135°; elbows only flex forward). Inverted "spaghetti" limbs are prohibited.
   - Shoulders and hips use bounded cones (`UpperAngle = 45°`, `TwistUpperAngle = 25°`).
2. **Active Muscle Spring Damping**:
   - Bones must retain active muscle spring stiffness. Fighters blown through the air tense their core and trail their limbs aerodynamically; they do not flop like limp corpses.
3. **No Artificial Upright Snap**:
   - Never use rigid 400,000-torque `AlignOrientation` stabilizers to freeze the physical root upright during knockbacks. Tumble angular velocity must follow physical impact momentum.
4. **Pose-Aware Recovery Continuity**:
   - Recovery get-up animations must dynamically inspect the Quin's actual resting orientation on the ground (Prone vs Supine) and smoothly lerp Motor6Ds back into drive without 1-frame snaps.

---

## 9. The Master Locomotion & Spectacle Roadmap

- **Step 1: The Inspection & Tuning Tool (Hands in the Engine)**: In-Studio inspection panel with playback scrubbers, stride/banking knobs, and automated multi-frame diagnostic capture pipeline.
- **Step 2: Continuous Locomotion Synthesis**: Centripetal torso roll banking and phase-locked running $\leftrightarrow$ arc transitions.
- **Step 3: Procedural Foot IK & Ledge Gripping**: `IKControl` surface conforming on inclines, stairs, and ledge lips.
- **Step 4: Active Ragdoll & Heavy Impact Spectacle**: Anatomically constrained physical joint reactions, aerodynamic mid-air tumbling, and pose-aware ground recoveries.

