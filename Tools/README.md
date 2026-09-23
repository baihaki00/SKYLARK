# QUIN TOOLS DIRECTORY

This directory contains the reusable engineering toolchain for inspecting, benchmarking, and synchronizing the Quin project.
**Do not create throwaway scripts in `scratch/`. Extend or invoke these tools.**

---

## Directory Structure

```
Tools/
├── Utilities/
│   ├── roblox_client.py         # Robust Studio MCP client (auto-discovers StudioMCP.exe)
│   └── sync_and_restart.py      # Synchronizes local scratch files to Edit datamodel & restarts Play
├── Diagnostics/
│   ├── inspect_character.py     # Inspects active Quins, HRP spatial coordinates, attributes, and ghost state
│   ├── inspect_physics.py       # Audits velocity, bottom clearance, physical constraints, and mass
│   └── inspect_animation.py     # Inspects active animation tracks, priorities, IDs, and procedural bone angles
└── Benchmarks/
    ├── SimulationHarnessBenchmark.py  # Automated verification of the 11 deterministic scenarios
    └── CombatBenchmark.py             # Live match execution (1v1, 2v2) auditing states, damage, and procedural reactions
```

---

## Usage Guide

### 1. Synchronizing Code to Studio
When you modify any `.lua` file in `scratch/`, sync it to the persistent Edit datamodel:
```powershell
python Tools/Utilities/sync_and_restart.py
```

### 2. Inspecting Live State
To inspect characters currently in the arena:
```powershell
python Tools/Diagnostics/inspect_character.py
```

To audit physical collider clearance, mass, and velocity vectors:
```powershell
python Tools/Diagnostics/inspect_physics.py
```

To inspect client-side animation tracks and procedural bone rotations:
```powershell
python Tools/Diagnostics/inspect_animation.py
```

### 3. Running Benchmarks
To run all 11 deterministic test scenarios:
```powershell
python Tools/Benchmarks/SimulationHarnessBenchmark.py
```

To run an automated live combat test:
```powershell
python Tools/Benchmarks/CombatBenchmark.py 1v1
python Tools/Benchmarks/CombatBenchmark.py 2v2
```
