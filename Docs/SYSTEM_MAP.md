# QUIN SYSTEM MAP & SUBSYSTEM INDEX

This document provides an exhaustive map of all production modules and scripts in the Quin codebase, their execution contexts, dependencies, and state ownership.

---

## 1. Core Data & Configuration Layer (`ReplicatedStorage.QuinCore`)

| Component | Path | Context | Responsibilities & Invariants |
| :--- | :--- | :--- | :--- |
| **QuinData** | `ReplicatedStorage.QuinCore.QuinData` | Shared | Base stat formulas, chassis stats (TypeA, TypeB, TypeC, TypeD), default health/speed curves. |
| **ElementData** | `ReplicatedStorage.QuinCore.ElementData` | Shared | Elemental matrix (Fire, Water, Wind, Earth, Lightning), affinity bonuses, damage multipliers. |
| **CombatConfig** | `ReplicatedStorage.QuinCore.CombatConfig` | Shared | Combat tuning constants: attack ranges, combo cadence, stamina/energy rates, recovery timeouts. |
| **AnimationConfig** | `ReplicatedStorage.QuinCore.AnimationConfig` | Shared | Animation playback speeds, fade times, looping flags, priority assignments. |
| **AnimationIds** | `ReplicatedStorage.QuinCore.AnimationIds` | Shared | Canonical asset IDs for all authored FBX animations (locomotion, attacks, reactions, get-up). |

---

## 2. Server Combat & Decision Intelligence Layer (`ReplicatedStorage.QuinCore.Modules`)

| Component | Path | Context | Responsibilities & Invariants |
| :--- | :--- | :--- | :--- |
| **TacticalPerception** | `ReplicatedStorage.QuinCore.Modules.TacticalPerception` | Server | Constructs 45-stud `LocalBattlefieldState`. Evaluates local friend/foe ratios, nearest threats, and wounded allies. |
| **TargetingModule** | `ReplicatedStorage.QuinCore.Modules.TargetingModule` | Server | Continuous explainable utility function evaluating target priority based on distance, HP, element, and tactical threat. |
| **DecisionSystem** | `ReplicatedStorage.QuinCore.Modules.DecisionSystem` | Server | High-level tactical evaluator selecting strategic actions (engage, flank, circle, rescue, disengage). |
| **PersonalitySystem** | `ReplicatedStorage.QuinCore.Modules.PersonalitySystem` | Server | Generates distinct behavioral profiles (Aggressive, Tactician, Guardian, Opportunist) modifying utility weights. |
| **QuinInstance** | `ReplicatedStorage.QuinCore.Modules.QuinInstance` | Server | Encapsulates persistent fighter state: UUID, Chassis Type, Attuned Element, personality traits, and match stats. |
| **SpatialModule** | `ReplicatedStorage.QuinCore.Modules.SpatialModule` | Shared | Spatial raycasting, ground clearance checks, ring boundary containment calculations. |
| **KnockbackModule** | `ReplicatedStorage.QuinCore.Modules.KnockbackModule` | Server | Calculates physical launch vectors, horizontal impulse, vertical loft, and wall bounce telemetry. |
| **HitboxModule** | `ReplicatedStorage.QuinCore.Modules.HitboxModule` | Server | Spatial queries for melee attacks, hit confirmation, and damage zone intersection. |
| **DamageModule** | `ReplicatedStorage.QuinCore.Modules.DamageModule` | Server | Damage calculations, armor reduction, elemental affinity adjustments, health deduction. |
| **ComboModule** | `ReplicatedStorage.QuinCore.Modules.ComboModule` | Server | Multi-hit combo branching logic, input buffer timing, finisher trigger conditions. |
| **BattleEventSystem** | `ReplicatedStorage.QuinCore.Modules.BattleEventSystem` | Server | Global battle event dispatcher: emits match start, hit confirm, knockback launch, defeat events. |
| **BenchmarkQuin** | `ReplicatedStorage.QuinCore.Modules.BenchmarkQuin` | Server | Automated telemetry recorder attached during benchmark scenarios for statistical logging. |
| **RuntimeTracer** | `ReplicatedStorage.QuinCore.Modules.RuntimeTracer` | Shared | Lightweight reflection-based execution tracer. Captures `debug.info` caller file/line checkpoints, replicating breadcrumbs and event logs to model attributes. |

---

## 3. Authoritative Combat States (`ReplicatedStorage.QuinCore.States`)

| State | Script | Context | Entry Conditions & Responsibilities |
| :--- | :--- | :--- | :--- |
| **IdleState** | `IdleState.lua` | Server | Default state awaiting targets, match start, or recovery completion. |
| **CirclingState** | `CirclingState.lua` | Server | Tactical pacing around target within $12 - 20\text{ studs}$. Manages flank angles and dash triggers. |
| **DashState** | `DashState.lua` | Server | High-speed directional impulse for gap closing or evasion. Applies body velocity with friction decay. |
| **ChaseState** | `ChaseState.lua` | Server | Linear target pursuit when distance $> 20\text{ studs}$. Drives Boss Walk / Sprint animations. |
| **FightState** | `FightState.lua` | Server | Melee strike execution, combo chaining, attack hitboxes, and elemental skill delivery. |
| **AirborneState** | `AirborneState.lua` | Server | Vertical launch into air for aerial combat. Disables ground friction, tracks apex trajectory. |
| **ProjectileJumpState**| `ProjectileJumpState.lua`| Server | Upward arc leap followed by aimed downward elemental projectile barrage. |
| **MidAirClashState** | `MidAirClashState.lua` | Server | Triggered when two airborne combatants collide. Calculates clash winner via elemental and velocity vectors. |
| **KnockbackState** | `KnockbackState.lua` | Server | Authoritative reaction to heavy hits: applies launch impulse, sets `PlatformStand`, monitors flight. |
| **RecoveryState** | `RecoveryState.lua` | Server | Landed state: clears `PlatformStand`, plays get-up animation, restores combat autonomy. |
| **ReEntryState** | `ReEntryState.lua` | Server | Controlled descent to ground after aerial jump attack, executing landing impact. |

---

## 4. Client Visuals & Procedural Skeletal Stack (`StarterPlayerScripts`)

| Component | Path | Context | Responsibilities & Invariants |
| :--- | :--- | :--- | :--- |
| **AIGhostHandler** | `StarterPlayerScripts.AIGhostHandler` | Client | Replicates server invisible Quins as smooth client-side skinned mesh ghosts in `Workspace.QuinGhost`. Owns the 60fps render loop. |
| **LookController** | `StarterPlayerScripts.LookController` | Client | Procedural gaze tracking. Decomposes gaze vector into 3 biomechanical zones across `Head`, `Neck`, and `Spine2`. |
| **ProceduralCombatReactionController**| `StarterPlayerScripts.ProceduralCombatReactionController`| Client | Directional hit recoil. Layers dynamic 3-DOF spring rotations onto spine chain and stagger offset onto hips. |
| **SmoothCamera** | `StarterPlayerScripts.SmoothCamera` | Client | Match spectator camera. Smooth lerp to focus centroid or selected fighter. Elevated arena view. |
| **QuinDebugHUD** | `StarterPlayerScripts.QuinDebugHUD` | Client | Left-side spectator overlay. Renders fighter cards (Type, Element, State, Health, Energy, Anim Track) for arena Quins only. |
| **VfxModule / FXService**| `ReplicatedStorage.QuinCore.Modules` | Client/Server | Spawns particle emitters, hit sparks, elemental trails, and slash effects. |

---

## 5. Server Lifecycle & Orchestration (`ServerScriptService`)

| Component | Path | Context | Responsibilities & Invariants |
| :--- | :--- | :--- | :--- |
| **Server** | `ServerScriptService.Server` | Server | Server root initialization. Loads core dependencies, initializes match services. |
| **QuinSpawner** | `ServerScriptService.QuinSpawner` | Server | Factory for arena Quins. Spawns character rigs under `Workspace.QuinServer`, tags with CollectionService, initializes attributes. |
| **QuinRosterService** | `ServerScriptService.QuinRosterService` | Server | Tracks active arena combatants, matches, win/loss records, and party structures. |
| **GameModeManager** | `ServerScriptService.GameModeManager` | Server | Manages game mode lifecycles: 1v1 Sparring, 2v2 Team Battle, 4v4 Skirmish, 16v16 Battle. |
| **BattleSimulationHarness**| `ServerScriptService.BattleSimulationHarness`| Server | 11 deterministic automated test scenarios covering tactical AI edge cases and stress scenarios. |
| **AnimationLabServer** | `ServerScriptService.AnimationLabServer` | Server | Debug lab interface for triggering animations, poses, and stress tests via remote events. |
