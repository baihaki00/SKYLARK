import os
import shutil
import sys

sys.stdout.reconfigure(encoding='utf-8')

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
pull_dir = r"C:\Users\User\.gemini\antigravity\scratch\studio_pull_20260922"
backup_dir = r"C:\Users\User\.gemini\antigravity\scratch\backup_pre_studio_adopt_20260922"

print("1. Creating backup of current local scratch files...")
os.makedirs(backup_dir, exist_ok=True)

# Copy all .lua files from scratch to backup
for f in os.listdir(scratch_dir):
    if f.endswith(".lua"):
        shutil.copy2(os.path.join(scratch_dir, f), os.path.join(backup_dir, f))
print(f"Backed up scratch .lua files to {backup_dir}")

# Map of where files from studio_pull go into scratch
# In studio_pull:
# ReplicatedStorage/QuinCore/CombatConfig.lua -> scratch/CombatConfig.lua
# ReplicatedStorage/QuinCore/ElementVfx.lua -> scratch/ElementVfx.lua
# ReplicatedStorage/QuinCore/Modules/*.lua -> scratch/*.lua
# ReplicatedStorage/QuinCore/States/*.lua -> scratch/*.lua
# ReplicatedStorage/QuinCore/Main.server.lua -> scratch/Main.lua
# ServerScriptService/Server.server.lua -> scratch/Server.lua
# ServerScriptService/QuinSpawner.lua -> scratch/QuinSpawner.lua
# ServerScriptService/QuinRosterService.lua -> scratch/QuinRosterService.lua
# ServerScriptService/BattleSimulationHarness.lua -> scratch/BattleSimulationHarness.lua
# ServerScriptService/GameModeManager.server.lua -> scratch/GameModeManager.lua
# ServerScriptService/AnimationLabServer.server.lua -> scratch/AnimationLabServer.lua
# StarterPlayer/StarterPlayerScripts/SmoothCamera.client.lua -> scratch/SmoothCamera.lua
# StarterPlayer/StarterPlayerScripts/QuinDebugHUD.client.lua -> scratch/QuinDebugHUD.lua
# StarterPlayer/StarterPlayerScripts/AIGhostHandler.client.lua -> scratch/AIGhostHandler.lua

file_mappings = [
    ("ReplicatedStorage/QuinCore/QuinData.lua", "QuinData.lua"),
    ("ReplicatedStorage/QuinCore/ElementData.lua", "ElementData.lua"),
    ("ReplicatedStorage/QuinCore/ElementVfx.lua", "ElementVfx.lua"),
    ("ReplicatedStorage/QuinCore/CombatConfig.lua", "CombatConfig.lua"),
    ("ReplicatedStorage/QuinCore/AnimationConfig.lua", "AnimationConfig.lua"),
    ("ReplicatedStorage/QuinCore/AnimationIds.lua", "AnimationIds.lua"),
    ("ReplicatedStorage/QuinCore/Main.server.lua", "Main.lua"),
]

# States
states_dir = os.path.join(pull_dir, "ReplicatedStorage", "QuinCore", "States")
if os.path.exists(states_dir):
    for f in os.listdir(states_dir):
        if f.endswith(".lua"):
            file_mappings.append((f"ReplicatedStorage/QuinCore/States/{f}", f))

# Modules
modules_dir = os.path.join(pull_dir, "ReplicatedStorage", "QuinCore", "Modules")
if os.path.exists(modules_dir):
    for f in os.listdir(modules_dir):
        if f.endswith(".lua"):
            file_mappings.append((f"ReplicatedStorage/QuinCore/Modules/{f}", f))

# ServerScriptService
file_mappings.extend([
    ("ServerScriptService/Server.server.lua", "Server.lua"),
    ("ServerScriptService/QuinSpawner.lua", "QuinSpawner.lua"),
    ("ServerScriptService/QuinRosterService.lua", "QuinRosterService.lua"),
    ("ServerScriptService/BattleSimulationHarness.lua", "BattleSimulationHarness.lua"),
    ("ServerScriptService/GameModeManager.server.lua", "GameModeManager.lua"),
    ("ServerScriptService/AnimationLabServer.server.lua", "AnimationLabServer.lua"),
    ("ServerScriptService/DeathDiagnostic.server.lua", "DeathDiagnostic.lua"),
    ("ServerScriptService/DebugManager.server.lua", "DebugManager.lua"),
    ("ServerScriptService/QuinDebugTracker.server.lua", "QuinDebugTracker.lua"),
    ("ServerScriptService/SmoothLandingAI.server.lua", "SmoothLandingAI.lua"),
])

# StarterPlayerScripts
file_mappings.extend([
    ("StarterPlayer/StarterPlayerScripts/SmoothCamera.client.lua", "SmoothCamera.lua"),
    ("StarterPlayer/StarterPlayerScripts/QuinDebugHUD.client.lua", "QuinDebugHUD.lua"),
    ("StarterPlayer/StarterPlayerScripts/AIGhostHandler.client.lua", "AIGhostHandler.lua"),
    ("StarterPlayer/StarterPlayerScripts/MasterDebugUI.client.lua", "MasterDebugUI.lua"),
    ("StarterPlayer/StarterPlayerScripts/TheArchitectCode.client.lua", "TheArchitectCode.lua"),
])

copied = 0
for src_rel, dest_filename in file_mappings:
    src_path = os.path.join(pull_dir, src_rel)
    if os.path.exists(src_path):
        dest_path = os.path.join(scratch_dir, dest_filename)
        shutil.copy2(src_path, dest_path)
        copied += 1
    else:
        print(f"Warning: {src_rel} does not exist in pull")

print(f"Adopted {copied} files from Studio into scratch directory!")
