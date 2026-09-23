import os
import shutil

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
archive_dir = os.path.join(scratch_dir, "Archive", "legacy_exploratory_scripts")

os.makedirs(archive_dir, exist_ok=True)

# Files that belong to the core production codebase or persistent infrastructure
preserved_files = {
    # Core Production Lua modules and states
    "AIGhostHandler.lua", "AirborneState.lua", "AnimationConfig.lua", "AnimationIds.lua",
    "AnimationLabController.lua", "AnimationLabServer.lua", "AnimationModule.lua", "AudioModule.lua",
    "BattleEventSystem.lua", "BattleSimulationHarness.lua", "BenchmarkQuin.lua", "ChaseState.lua",
    "CirclingState.lua", "CombatConfig.lua", "ComboModule.lua", "DamageModule.lua", "DashState.lua",
    "DebugInput.lua", "DebugManager.lua", "DecisionSystem.lua", "DeterministicMenuUI.lua",
    "ElementData.lua", "FXService.lua", "FightState.lua", "GameModeManager.lua", "HitboxModule.lua",
    "IdleState.lua", "InterceptionState.lua", "JumpDebugHandler.lua", "KnockbackModule.lua",
    "KnockbackState.lua", "LookController.lua", "Main.lua", "MasterDebugUI.lua", "MenuController.lua",
    "MidAirClashState.lua", "PersonalitySystem.lua", "ProceduralCombatReactionController.lua",
    "ProjectileFightState.lua", "ProjectileJumpState.lua", "QuinData.lua", "QuinDebugHUD.lua",
    "QuinDebugTracker.lua", "QuinDebugUI.lua", "QuinInstance.lua", "QuinRosterService.lua",
    "QuinSpawner.lua", "ReEntryState.lua", "RecoveryState.lua", "SecurityCameraController.lua",
    "Server.lua", "SmoothCamera.lua", "SpatialModule.lua", "TacticalPerception.lua",
    "TargetingModule.lua", "VfxModule.lua",
}

# Directories to keep at root
preserved_dirs = {
    "Docs", "Tools", "Archive", "git_backups"
}

moved_count = 0
for item in os.listdir(scratch_dir):
    item_path = os.path.join(scratch_dir, item)
    if os.path.isdir(item_path):
        # Keep preserved dirs and frozen backup dirs
        if item in preserved_dirs or item.startswith("backup_frozen_stable") or item.startswith("backup_pre_"):
            continue
        # If it's __pycache__, remove it
        if item == "__pycache__":
            shutil.rmtree(item_path, ignore_errors=True)
            continue
    else:
        # File: check if it is preserved
        if item in preserved_files:
            continue
        # Otherwise move to archive
        dest_path = os.path.join(archive_dir, item)
        shutil.move(item_path, dest_path)
        moved_count += 1

print(f"Cleaned up scratch root: Moved {moved_count} legacy/exploratory files to {archive_dir}")
