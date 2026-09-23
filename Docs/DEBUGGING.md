# FORENSIC DEBUGGING RECORD & ENGINE LESSONS LEARNED

This document records subtle engine traps, failure modes discovered in previous milestones, and established debugging protocols for the Quin codebase.

---

## 1. Engine Traps & Subtle Gotchas

### 1.1 `Humanoid.FloorMaterial` in `PlatformStand`
- **Symptom**: Relying on `Humanoid.FloorMaterial ~= Enum.Material.Air` to detect landing during knockback or air maneuvers caused characters to never land or get stuck indefinitely in air states.
- **Root Cause**: In Roblox's PGS physics engine, the moment `Humanoid.PlatformStand = true` is set, the internal humanoid controller disables its floor probe. `Humanoid.FloorMaterial` is **permanently hardcoded to `Enum.Material.Air`** until `PlatformStand` is cleared.
- **Rule**: Never query `Humanoid.FloorMaterial` while a fighter is in `PlatformStand`. Use explicit `Workspace:Raycast` or spatial clearance probes.

### 1.2 Premature Ground Detection from HRP Center
- **Symptom**: During airborne knockbacks, Quins would suddenly freeze in midair and snap into `RecoveryState` while visually $3 - 4\text{ studs}$ above the floor.
- **Root Cause**: `SpatialModule.isGrounded()` measured from the center of the HRP using:
  $$\text{checkDistance} = \text{halfHeight} + \text{hipHeight} + 0.3$$
  While horizontal or tumbling, the center of the HRP is within $\sim 5\text{ studs}$ of the floor, causing the raycast to report "grounded" while the physical collider was still high in the air. The state machine immediately zeroed linear velocity.
- **Rule**: Distinguish between *standing distance from center* and *actual physical collider contact*. A landing check must measure distance from the *bottom surface* of the collider or detect physical impact velocity.

### 1.3 Polling Latency & Instant Velocity Zeroing
- **Symptom**: Landings looked robotic and "snappy" rather than physically satisfying.
- **Root Cause**: Polling state transitions at $10\text{ Hz}$ ($0.1\text{s}$ intervals) and instantly setting `rootPart.AssemblyLinearVelocity = Vector3.zero` obliterated horizontal inertia.
- **Rule**: Apply continuous exponential ground friction ($v(t) = v_0 e^{-k t}$) rather than instant zeroing. Decelerate smoothly to preserve physical weight.

### 1.4 Ghost Collider & CollisionGroup Snags
- **Symptom**: Client-side ghosts in `Workspace.QuinGhost` would collide with the arena or push the server HRP off course.
- **Root Cause**: Newly cloned ghost parts defaulted to `CanCollide = true`, causing physics conflicts with the server model.
- **Rule**: When creating client ghosts in `AIGhostHandler.lua`, iterate all base parts and enforce `CanCollide = false`, `CanTouch = false`, and `CanQuery = false`. Only the server `HumanoidRootPart` interacts with the physical world.

### 1.5 World Rig Leakage into Arena Queries
- **Symptom**: Extra cards showing up on the spectator HUD on game start; AI Quins attempting to target faraway animation dummies.
- **Root Cause**: Code scanning `Workspace:GetChildren()` picked up static editor rigs (`QuinTest`, `QuinTypeA`).
- **Rule**: All arena queries must be scoped to `Workspace.QuinServer` and check `isArenaQuin` attributes or CollectionService tags.

---

## 2. Standard Debugging Protocols

### Protocol A: Inspecting Physical vs Visual Disconnects
When a character looks out of place:
1. Run `Tools/Diagnostics/inspect_physics.py` to check the actual HRP CFrame and AssemblyLinearVelocity on the server.
2. Run `Tools/Diagnostics/inspect_animation.py` to check what tracks are playing on the client and what bone angles are applied.
3. If HRP is in the correct place but the mesh is twisted, the issue is in the client bone spring calculation (`ProceduralCombatReactionController` or `LookController`).
4. If the mesh is in the correct place but floating, the issue is server physics / state transition logic.

### Protocol B: Code Synchronization Verification
Remember the two-tier datamodel in Roblox Studio:
1. **Never edit code only in Play mode.** Changes to `datamodel_type="Server"` or `"Client"` are ephemeral and disappear on restart.
2. Edit local files in `scratch/`.
3. Run `Tools/Utilities/sync_and_restart.py` to sync local code into Studio's `Edit` datamodel and restart Play mode.
4. Verify that the changes exist in `StarterPlayerScripts`, `ServerScriptService`, or `ReplicatedStorage.QuinCore`.
