import os
import sys
import difflib

sys.stdout.reconfigure(encoding='utf-8')

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
pull_dir = r"C:\Users\User\.gemini\antigravity\scratch\studio_pull_20260922"

sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from sync_and_restart import sync_map

key_files = [
    ("CombatConfig.lua", "ReplicatedStorage/QuinCore/CombatConfig.lua"),
    ("SpatialModule.lua", "ReplicatedStorage/QuinCore/Modules/SpatialModule.lua"),
    ("ChaseState.lua", "ReplicatedStorage/QuinCore/States/ChaseState.lua"),
    ("VfxModule.lua", "ReplicatedStorage/QuinCore/Modules/VfxModule.lua"),
    ("Main.lua", "ReplicatedStorage/QuinCore/Main.server.lua"),
    ("ProjectileJumpState.lua", "ReplicatedStorage/QuinCore/States/ProjectileJumpState.lua"),
    ("DecisionSystem.lua", "ReplicatedStorage/QuinCore/Modules/DecisionSystem.lua"),
    ("TacticalPerception.lua", "ReplicatedStorage/QuinCore/Modules/TacticalPerception.lua"),
    ("CirclingState.lua", "ReplicatedStorage/QuinCore/States/CirclingState.lua"),
    ("DamageModule.lua", "ReplicatedStorage/QuinCore/Modules/DamageModule.lua"),
]

print("=" * 80)
print("ANALYSIS OF USER CHANGES IN STUDIO")
print("=" * 80)

for local_name, studio_rel in key_files:
    local_path = os.path.join(scratch_dir, local_name)
    studio_path = os.path.join(pull_dir, studio_rel)
    if not os.path.exists(studio_path):
        print(f"MISSING IN PULL: {studio_rel}")
        continue
    with open(local_path, "r", encoding="utf-8", errors="replace") as f:
        local_lines = f.readlines()
    with open(studio_path, "r", encoding="utf-8", errors="replace") as f:
        studio_lines = f.readlines()

    diff = list(difflib.unified_diff(
        local_lines, studio_lines,
        fromfile=f"scratch/{local_name}",
        tofile=f"studio/{studio_rel}",
        n=2
    ))

    added = sum(1 for l in diff if l.startswith('+') and not l.startswith('+++'))
    removed = sum(1 for l in diff if l.startswith('-') and not l.startswith('---'))

    print(f"\n>>> {local_name} vs Studio ({studio_rel}): +{added} lines, -{removed} lines <<<")
    # Show first 40 lines of diff
    for line in diff[:60]:
        print(line, end='')
    if len(diff) > 60:
        print(f"\n... [{len(diff) - 60} more diff lines truncated] ...")
