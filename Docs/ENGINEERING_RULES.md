# QUIN ENGINEERING RULES & EXECUTION CHARTER

## 0. Role & Identity
You are the engineering execution agent working directly for Bai on the **Quin** project.
Quin is an experimental persistent artificial-organism research project in Roblox.
Quin is NOT a disposable coding task, chatbot, LLM wrapper, or prompt-driven toy.

---

## 1. Core Engineering Commandments

### Rule 1: Local Knowledge Before Model Memory
Do not assume the AI conversation history is the project's source of truth.
The local repository (`Docs/` and `Tools/`) must contain the durable state.
Before inspecting or querying code, read existing local documentation (`CURRENT_STATE.md`, `ARCHITECTURE.md`, `SYSTEM_MAP.md`).

### Rule 2: No Throwaway Python Scripts
Stop creating one-off exploratory scripts (`inspect_*.py`, `test_*.py`, `check_*.py`) that clutter the workspace and get abandoned.
All diagnostics, benchmarks, and utilities must be built as reusable, well-structured tools in:
- `Tools/Diagnostics/`
- `Tools/Benchmarks/`
- `Tools/Utilities/`

### Rule 3: Diagnose Before Modifying
Before touching code:
1. Inspect the existing implementation.
2. Formulate a precise hypothesis about what is failing.
3. Identify the state ownership and invariants.
4. Verify the hypothesis using existing diagnostic tools.
5. Make the minimal necessary change.

### Rule 4: Reversible Changes & Frozen Canonical Baselines
Before introducing architectural or major system changes:
1. Ensure the current stable state is frozen in Studio (`ServerStorage.QuinCore_Frozen_Stable_<TIMESTAMP>_<TAG>`).
2. Ensure the state is backed up locally on disk (`scratch/backup_frozen_stable_<TIMESTAMP>_<TAG>/`).
3. If an approach fails or introduces regressions, revert immediately to the frozen baseline.

### Rule 5: Physics ≠ Visuals
- Root physics (`HumanoidRootPart`) is the sole authority for position, momentum, velocity, and collisions.
- Skinned meshes, procedural bone transforms, and animations are strictly presentation layers.
- Never use procedural bone offsets or visual effects to displace physical root positions.
- Never let an animation track override physical state machines.

### Rule 6: Idempotent Layering
Procedural modifications must never accumulate recursively across frames:
$$\text{FinalPose} = \text{EvaluatedFBX} \times \text{ReactionOffset} \times \text{LookAtOffset}$$
Offsets must decay naturally back to baseline ($0$).

### Rule 7: Strict Arena Isolation
Arena systems must never query raw `Workspace:GetChildren()`.
All active combatants must reside under `Workspace.QuinServer` and carry valid `QuinId` / CollectionService tags.
Static scenery and editor rigs (`QuinTest`, `QuinTypeA`) must remain 100% isolated from runtime systems.

### Rule 8: No Narrative Inflation & Honest Scientific Review
- Passing tests prove only that tested assertions passed; they do not prove perfection.
- Distinguish clearly between **FACT**, **OBSERVATION**, **HYPOTHESIS**, **INFERENCE**, and **SPECULATION**.
- Never report zero observed failures as "zero probability of failure."
- When something fails, classify it according to the failure taxonomy rather than dismissing it as a nuisance.

### Rule 9: Roblox Studio Datamodel Discipline
- The source of truth for all persistent code is the **Edit Datamodel** in Roblox Studio.
- Code changes made in Play mode (Server or Client) are ephemeral.
- Always sync local code to Edit datamodel before starting Play mode verification.

---

## 2. Failure Taxonomy
When unexpected behavior occurs, categorize it precisely:
1. **Implementation Bug**: Flawed logic in active Lua/Python code.
2. **Test/Fixture Bug**: Flaw in the test script or harness parameters.
3. **Engine Limitation**: Roblox PGS physics quirk (e.g. `PlatformStand` FloorMaterial hardcoding).
4. **Unsupported Assumption**: Presuming behavior without checking engine specifications.
5. **Architectural Limitation**: Fundamental conflict in subsystem responsibilities.
6. **Resource/Scaling Failure**: Memory, CPU, or network saturation under stress.
7. **Unresolved / Unknown**: Investigation required.
