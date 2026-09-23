import os
import sys
import difflib

sys.stdout.reconfigure(encoding='utf-8')

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
pull_dir = r"C:\Users\User\.gemini\antigravity\scratch\studio_pull_20260922"

def print_full_diff(local_file, studio_rel):
    local_path = os.path.join(scratch_dir, local_file)
    studio_path = os.path.join(pull_dir, studio_rel)
    if not os.path.exists(studio_path):
        print(f"MISSING: {studio_rel}")
        return
    with open(local_path, "r", encoding="utf-8", errors="replace") as f:
        local_lines = f.readlines()
    with open(studio_path, "r", encoding="utf-8", errors="replace") as f:
        studio_lines = f.readlines()
    diff = list(difflib.unified_diff(
        local_lines, studio_lines,
        fromfile=f"scratch/{local_file}",
        tofile=f"studio/{studio_rel}",
        n=2
    ))
    print(f"\n=======================================================")
    print(f"DIFF: {local_file} -> {studio_rel}")
    print(f"=======================================================")
    for line in diff:
        print(line, end='')

# Print full diff for CombatConfig, SpatialModule, ChaseState, Main
for lf, sf in [
    ("CombatConfig.lua", "ReplicatedStorage/QuinCore/CombatConfig.lua"),
    ("SpatialModule.lua", "ReplicatedStorage/QuinCore/Modules/SpatialModule.lua"),
    ("ChaseState.lua", "ReplicatedStorage/QuinCore/States/ChaseState.lua"),
    ("Main.lua", "ReplicatedStorage/QuinCore/Main.server.lua")
]:
    print_full_diff(lf, sf)
