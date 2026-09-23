import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
pull_dir = r"C:\Users\User\.gemini\antigravity\scratch\studio_pull_20260922"

new_files_to_check = [
    "ReplicatedStorage/QuinCore/States/RetreatState.lua",
    "ReplicatedStorage/QuinCore/States/ProjectileJumpRecoveryState.lua",
    "ReplicatedStorage/QuinCore/States/PositioningJumpState.lua",
    "ReplicatedStorage/QuinCore/States/SpecialState.lua",
    "ReplicatedStorage/QuinCore/States/ProjectileFightState.lua",
    "ReplicatedStorage/QuinCore/States/InterceptionState.lua",
    "ReplicatedStorage/QuinCore/States/DeathState.lua",
]

for rel in new_files_to_check:
    path = os.path.join(pull_dir, rel)
    print("=" * 80)
    print(f"FILE: {rel}")
    print("=" * 80)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        print(f"Total lines: {len(lines)}")
        for i, line in enumerate(lines[:60]):
            print(f"{i+1:3d}: {line}", end='')
        if len(lines) > 60:
            print(f"\n... [{len(lines) - 60} more lines omitted] ...")
    else:
        print("DOES NOT EXIST")
