# QUIN ARCHITECTURE SPECIFICATION

## 1. Constitutional Design Philosophy: Digital Organism vs Game Puppet

Quin is engineered as a persistent artificial organism inside Roblox, not a transient animated puppet.
Every architectural layer adheres to strict separation between **Physical Reality**, **Cognitive Deliberation**, and **Visual Presentation**.

---

## 2. Core Invariants

### Invariant 1: Physics ≠ Visuals
- Physical movement, momentum, collisions, and spatial coordinates are 100% owned by the **Physical Root** (`HumanoidRootPart`).
- Skinned meshes, procedural bone rotations, flinches, gaze offsets, and animation blend trees are strictly **presentation layers**.
- A visual offset must **never** displace or apply impulse to the physical collider root.
- A physical impulse must **never** be masked or canceled by an animation track.

### Invariant 2: HRP ≠ Visual Body
- The `HumanoidRootPart` (HRP) is an invisible box collider (dimensions $8.56 \times 7.94 \times 1.60\text{ studs}$, `Alpha_Surface` collider) that handles Roblox Havok/PGS physics solver calculations.
- The visible character is a skinned mesh deformation model (`mixamorig` bone hierarchy) rendered client-side.
- The physical collider center is approximately $3.5 - 4.5\text{ studs}$ above ground level when standing. Detection of ground contact must account for half-height clearance, not center position.

### Invariant 3: Visual Ghost Replication Architecture
To eliminate server-side mesh animation overhead, replication lag, and physics jitter:
```
Server Simulation
  ├── HumanoidRootPart (Physics, Position, Velocity)
  ├── Attributes (State, Health, Target, Element, Reaction)
  └── Transparency = 1 (Server character is 100% invisible)
         │
         ▼ (Roblox standard spatial/property replication)
Client Ghost Controller (AIGhostHandler.lua)
  ├── Creates local Skinned Mesh clone inside Workspace.QuinGhost
  ├── Smoothly lerps Ghost CFrame to Server HRP CFrame at 60 Hz
  ├── Evaluates AnimationTracks via local Animator
  └── Applies procedural bone transforms (Gaze + Hit Reactions)
```

### Invariant 4: Strictly Idempotent Procedural Layering
Procedural bone modifications must **never** accumulate recursively across frames.
Roblox's animation engine evaluates authored keyframes into `Bone.Transform` every frame before `RenderStepped`.
The evaluation order per frame is strictly:
$$\text{FinalPose} = \text{EvaluatedFBX} \times \text{ReactionOffset} \times \text{LookAtOffset}$$
Because $\text{EvaluatedFBX}$ is re-evaluated anew from the authored track on each render step, multiplying by non-accumulating dynamic springs produces an idempotent, stable pose that decays naturally to baseline ($0$).

### Invariant 5: Arena Scoping
- The match lifecycle manager spawns active combatants exclusively under `Workspace.QuinServer`.
- Static reference models, editor rigs (`QuinTest`, `QuinTypeA`), and scenery live directly under `Workspace`.
- Combat targeting, perception modules, and the Spectator HUD must **never** scan raw `Workspace:GetChildren()`. They query only `Workspace.QuinServer` and require `isArenaQuin` verification (presence of `QuinId`, CollectionService tags `"Quin"` or `"AI_Fighter"`).

---

## 3. Subsystem Architecture

### 3.1 Decision Intelligence & Tactical Perception
```
Continuous World State (45-stud radius)
      │
      ▼
TacticalPerception.lua (Computes LocalBattlefieldState)
  ├── Local Allies & Enemies
  ├── Numerical Advantage Ratio
  ├── Closest Threat & Wounded Ally Proximity
  └── Ring Position & Distance to Edge
      │
      ▼
TargetingModule.lua (Continuous Utility Function)
  ├── Base Threat Scoring
  ├── Distance Penalty
  ├── Elemental Advantage / Disadvantage Weight
  ├── Vulnerability Multiplier (Low HP / Stunned)
  └── Personality Modifier (Aggressive vs Cautious)
      │
      ▼
DecisionSystem.lua & PersonalitySystem.lua
  ├── Evaluates Action Candidates (Attack, Circle, Dash, Retreat, Rescue)
  └── Commits to Combat State via ForceState / Transition
```

### 3.2 Combat State Machine
Combat states live in `ReplicatedStorage.QuinCore.States` and run authoritatively on the Server:
1. **IdleState**: Initial state, scans for targets or awaits match launch.
2. **CirclingState**: Tactical positioning, maintaining optimal engagement distance while pacing around target.
3. **DashState**: High-speed directional repositioning, burst closing or evading.
4. **ChaseState**: Forward pursuit using dynamic pathing and sprint/walk animations.
5. **FightState**: Close-quarters melee engagement, combo chains (Light/Heavy/Finisher), elemental skills.
6. **AirborneState / ProjectileJumpState**: Aerial leap and downward elemental projectile attacks.
7. **MidAirClashState**: High-velocity midair collision resolution between two airborne combatants.
8. **KnockbackState**: Authoritative physical reaction to heavy impacts, launching HRP with impulse and air flinch.
9. **RecoveryState**: Grounded get-up transition restoring combat control.
10. **ReEntryState**: Controlled descent and landing recovery following aerial maneuvers.

### 3.3 Skeletal Procedural Controller Stack
Run entirely on the client within `StarterPlayerScripts`:
- **LookController.lua**:
  - Implements biomechanical 3-zone rotation distribution:
    - Zone 1 ($0^\circ - 30^\circ$): 100% `mixamorig:Head`
    - Zone 2 ($30^\circ - 60^\circ$): $30^\circ$ `Head` + remaining on `mixamorig:Neck`
    - Zone 3 ($60^\circ - 100^\circ$): $30^\circ$ `Head` + $30^\circ$ `Neck` + remaining on `mixamorig:Spine2`
  - Targets active combat opponent or distressed nearby ally.
  - Smooth damped interpolation prevents uncanny instantaneous snapping.
- **ProceduralCombatReactionController.lua**:
  - 3-DOF damped spring for impulse recoil (pitch, yaw, roll).
  - Hips vertical and lateral stagger displacement.
  - Directional hit impact decomposition: distributes angular recoil multiplicatively along `mixamorig:Spine` $\to$ `mixamorig:Spine1` $\to$ `mixamorig:Spine2`.

---

## 4. Execution & Persistence Semantics

### Roblox Studio Edit vs Play Mode Lifecycle
- **Edit Datamodel**: Source of truth for all code assets in `ReplicatedStorage.QuinCore`, `ServerScriptService`, and `StarterPlayerScripts`. Changes made here persist into the `.rbxl` place file.
- **Play Datamodel (Server/Client)**: Ephemeral runtime. Code changes made here disappear when Play mode stops.
- **Persistent Sync Pipeline**: All code updates are written directly to disk (`scratch/`), synced into Studio's `Edit` datamodel via `Tools/Utilities/sync_and_restart.py`, and verified in a freshly initialized `Play` datamodel.
