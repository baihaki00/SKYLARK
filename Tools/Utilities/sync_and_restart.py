import os
import sys
import json
import time

# Ensure Tools/Utilities is on python path
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from roblox_client import RobloxStudioClient

sync_map = [
    # Core Data & Configs
    ("QuinData", "ReplicatedStorage.QuinCore.QuinData", "QuinData.lua", "ModuleScript"),
    ("ElementData", "ReplicatedStorage.QuinCore.ElementData", "ElementData.lua", "ModuleScript"),
    ("ElementVfx", "ReplicatedStorage.QuinCore.ElementVfx", "ElementVfx.lua", "ModuleScript"),
    ("CombatConfig", "ReplicatedStorage.QuinCore.CombatConfig", "CombatConfig.lua", "ModuleScript"),
    ("AnimationConfig", "ReplicatedStorage.QuinCore.AnimationConfig", "AnimationConfig.lua", "ModuleScript"),
    ("AnimationIds", "ReplicatedStorage.QuinCore.AnimationIds", "AnimationIds.lua", "ModuleScript"),

    # Modules
    ("SpatialModule", "ReplicatedStorage.QuinCore.Modules.SpatialModule", "SpatialModule.lua", "ModuleScript"),
    ("KnockbackModule", "ReplicatedStorage.QuinCore.Modules.KnockbackModule", "KnockbackModule.lua", "ModuleScript"),
    ("LocomotionModule", "ReplicatedStorage.QuinCore.Modules.LocomotionModule", "LocomotionModule.lua", "ModuleScript"),
    ("HitboxModule", "ReplicatedStorage.QuinCore.Modules.HitboxModule", "HitboxModule.lua", "ModuleScript"),
    ("DamageModule", "ReplicatedStorage.QuinCore.Modules.DamageModule", "DamageModule.lua", "ModuleScript"),
    ("ComboModule", "ReplicatedStorage.QuinCore.Modules.ComboModule", "ComboModule.lua", "ModuleScript"),
    ("TargetingModule", "ReplicatedStorage.QuinCore.Modules.TargetingModule", "TargetingModule.lua", "ModuleScript"),
    ("PersonalitySystem", "ReplicatedStorage.QuinCore.Modules.PersonalitySystem", "PersonalitySystem.lua", "ModuleScript"),
    ("QuinInstance", "ReplicatedStorage.QuinCore.Modules.QuinInstance", "QuinInstance.lua", "ModuleScript"),
    ("FXService", "ReplicatedStorage.QuinCore.Modules.FXService", "FXService.lua", "ModuleScript"),
    ("AudioModule", "ReplicatedStorage.QuinCore.Modules.AudioModule", "AudioModule.lua", "ModuleScript"),
    ("TacticalPerception", "ReplicatedStorage.QuinCore.Modules.TacticalPerception", "TacticalPerception.lua", "ModuleScript"),
    ("DecisionSystem", "ReplicatedStorage.QuinCore.Modules.DecisionSystem", "DecisionSystem.lua", "ModuleScript"),
    ("BattleEventSystem", "ReplicatedStorage.QuinCore.Modules.BattleEventSystem", "BattleEventSystem.lua", "ModuleScript"),
    ("VfxModule", "ReplicatedStorage.QuinCore.Modules.VfxModule", "VfxModule.lua", "ModuleScript"),
    ("AnimationModule", "ReplicatedStorage.QuinCore.Modules.AnimationModule", "AnimationModule.lua", "ModuleScript"),
    ("RuntimeTracer", "ReplicatedStorage.QuinCore.Modules.RuntimeTracer", "RuntimeTracer.lua", "ModuleScript"),
    ("LookController", "ReplicatedStorage.QuinCore.Modules.LookController", "LookController.lua", "ModuleScript"),
    ("ProceduralCombatReactionController", "ReplicatedStorage.QuinCore.Modules.ProceduralCombatReactionController", "ProceduralCombatReactionController.lua", "ModuleScript"),
    ("TeamCoordinationSystem", "ReplicatedStorage.QuinCore.Modules.TeamCoordinationSystem", "TeamCoordinationSystem.lua", "ModuleScript"),
    ("QuinDataStoreService", "ReplicatedStorage.QuinCore.Modules.QuinDataStoreService", "QuinDataStoreService.lua", "ModuleScript"),
    ("LeaderShowdownSystem", "ReplicatedStorage.QuinCore.Modules.LeaderShowdownSystem", "LeaderShowdownSystem.lua", "ModuleScript"),
    ("RetreatTacticsModule", "ReplicatedStorage.QuinCore.Modules.RetreatTacticsModule", "RetreatTacticsModule.lua", "ModuleScript"),

    # Combat States
    ("IdleState", "ReplicatedStorage.QuinCore.States.IdleState", "IdleState.lua", "ModuleScript"),
    ("CirclingState", "ReplicatedStorage.QuinCore.States.CirclingState", "CirclingState.lua", "ModuleScript"),
    ("RetreatState", "ReplicatedStorage.QuinCore.States.RetreatState", "RetreatState.lua", "ModuleScript"),
    ("KnockbackState", "ReplicatedStorage.QuinCore.States.KnockbackState", "KnockbackState.lua", "ModuleScript"),
    ("RecoveryState", "ReplicatedStorage.QuinCore.States.RecoveryState", "RecoveryState.lua", "ModuleScript"),
    ("ChaseState", "ReplicatedStorage.QuinCore.States.ChaseState", "ChaseState.lua", "ModuleScript"),
    ("FightState", "ReplicatedStorage.QuinCore.States.FightState", "FightState.lua", "ModuleScript"),
    ("AirborneState", "ReplicatedStorage.QuinCore.States.AirborneState", "AirborneState.lua", "ModuleScript"),
    ("ProjectileJumpState", "ReplicatedStorage.QuinCore.States.ProjectileJumpState", "ProjectileJumpState.lua", "ModuleScript"),
    ("MidAirClashState", "ReplicatedStorage.QuinCore.States.MidAirClashState", "MidAirClashState.lua", "ModuleScript"),
    ("ProjectileFightState", "ReplicatedStorage.QuinCore.States.ProjectileFightState", "ProjectileFightState.lua", "ModuleScript"),
    ("InterceptionState", "ReplicatedStorage.QuinCore.States.InterceptionState", "InterceptionState.lua", "ModuleScript"),
    ("SpecialState", "ReplicatedStorage.QuinCore.States.SpecialState", "SpecialState.lua", "ModuleScript"),
    ("DeathState", "ReplicatedStorage.QuinCore.States.DeathState", "DeathState.lua", "ModuleScript"),
    ("ReEntryState", "ReplicatedStorage.QuinCore.States.ReEntryState", "ReEntryState.lua", "ModuleScript"),
    ("WallRunState", "ReplicatedStorage.QuinCore.States.WallRunState", "WallRunState.lua", "ModuleScript"),
    ("LeaderShowdownState", "ReplicatedStorage.QuinCore.States.LeaderShowdownState", "LeaderShowdownState.lua", "ModuleScript"),
    ("BeamStruggleState", "ReplicatedStorage.QuinCore.States.BeamStruggleState", "BeamStruggleState.lua", "ModuleScript"),

    # Server Scripts
    ("Main", "ReplicatedStorage.QuinCore.Main", "Main.lua", "Script"),
    ("Server", "ServerScriptService.Server", "Server.lua", "Script"),
    ("QuinSpawner", "ServerScriptService.QuinSpawner", "QuinSpawner.lua", "ModuleScript"),
    ("QuinRosterService", "ServerScriptService.QuinRosterService", "QuinRosterService.lua", "ModuleScript"),
    ("BattleSimulationHarness", "ServerScriptService.BattleSimulationHarness", "BattleSimulationHarness.lua", "ModuleScript"),
    ("GameModeManager", "ServerScriptService.GameModeManager", "GameModeManager.lua", "Script"),
    ("AnimationLabServer", "ServerScriptService.AnimationLabServer", "AnimationLabServer.lua", "Script"),
    ("DebugManager", "ServerScriptService.DebugManager", "DebugManager.lua", "Script"),

    # Client Scripts
    ("AnimationLabController", "StarterGui.AnimationLabUI.AnimationLabController", "AnimationLabController.lua", "LocalScript"),
    ("SmoothCamera", "StarterPlayer.StarterPlayerScripts.SmoothCamera", "SmoothCamera.lua", "LocalScript"),
    ("QuinDebugHUD", "StarterPlayer.StarterPlayerScripts.QuinDebugHUD", "QuinDebugHUD.lua", "LocalScript"),
    ("AIGhostHandler", "StarterPlayer.StarterPlayerScripts.AIGhostHandler", "AIGhostHandler.lua", "LocalScript"),
    ("MasterDebugUI", "StarterPlayer.StarterPlayerScripts.MasterDebugUI", "MasterDebugUI.lua", "LocalScript"),
    ("TheArchitectCode", "StarterPlayer.StarterPlayerScripts.TheArchitectCode", "TheArchitectCode.lua", "LocalScript"),
    ("MenuController", "StarterGui.QuinMenuUI.MainFrame.MenuController", "MenuController.lua", "LocalScript"),
]

def wait_for_mode(client, target_mode, timeout=15):
    for _ in range(timeout):
        st = client.get_studio_state()
        txt = st.get("result", {}).get("content", [{}])[0].get("text", "")
        if f"Current Studio Mode: {target_mode}" in txt:
            return True
        time.sleep(1)
    return False

def sync_all_and_restart(start_play=True):
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Ensure Edit mode
    st = client.get_studio_state()
    txt = st.get("result", {}).get("content", [{}])[0].get("text", "")
    if "Current Studio Mode: Play" in txt:
        print("Stopping Play mode to access Edit datamodel...")
        client.set_play_mode(False)
        if wait_for_mode(client, "Edit"):
            print("Confirmed: In Edit mode.")
        else:
            print("Warning: Timeout waiting for Edit mode.")

    # Clean up deprecated standalone BattleSpeedHUD from Studio
    cleanup_code = """
    local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
    if sp and sp:FindFirstChild("BattleSpeedHUD") then
        sp.BattleSpeedHUD:Destroy()
    end
    local sg = game:GetService("StarterGui")
    if sg and sg:FindFirstChild("BattleSpeedGui") then
        sg.BattleSpeedGui:Destroy()
    end
    return "Cleaned up standalone BattleSpeedHUD"
    """
    client.execute_luau(cleanup_code, datamodel_type="Edit")

    scratch_dir = os.path.abspath(os.path.join(current_dir, "..", ".."))
    success_count = 0

    for name, studio_path, local_filename, inst_type in sync_map:
        file_path = os.path.join(scratch_dir, local_filename)
        if not os.path.exists(file_path):
            print(f"SKIPPING (File not found on disk): {local_filename}")
            continue

        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        payload = json.dumps(content)

        luau_code = f"""
        local HttpService = game:GetService("HttpService")
        local payload = {json.dumps(payload)}
        local content = HttpService:JSONDecode(payload)
        
        local pathSegments = string.split("{studio_path}", ".")
        local current = game
        for i = 1, #pathSegments do
            local seg = pathSegments[i]
            if i == 1 then
                current = game:GetService(seg)
            else
                local child = current:FindFirstChild(seg)
                if child and i == #pathSegments and child.ClassName ~= "{inst_type}" then
                    child:Destroy()
                    child = nil
                end
                if not child then
                    if i == #pathSegments then
                        child = Instance.new("{inst_type}")
                        child.Name = seg
                        child.Parent = current
                    else
                        local folder = Instance.new("Folder")
                        folder.Name = seg
                        folder.Parent = current
                        child = folder
                    end
                end
                current = child
            end
        end
        
        current.Source = content
        return string.format("Synced %s: %d lines, %d bytes", "{name}", #string.split(content, "\\n"), #content)
        """

        res = client.execute_luau(luau_code, datamodel_type="Edit")
        result_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
        is_err = res.get("result", {}).get("isError", False) or "error" in result_text.lower()
        if is_err:
            print(f"[FAIL] {name}: {result_text}")
        else:
            success_count += 1
            print(f"[OK] {result_text}")

    print(f"\nSync complete: {success_count}/{len(sync_map)} components synchronized into Edit datamodel.")
    if start_play:
        print("Starting fresh Play mode...")
        client.set_play_mode(True)
        if wait_for_mode(client, "Play"):
            print("Game confirmed started in Play mode.")
        else:
            print("Warning: Timeout waiting for Play mode.")
    else:
        print("Skipping Play mode start (--no-play / --edit-only).")
    client.close()

if __name__ == "__main__":
    should_play = "--no-play" not in sys.argv and "--edit-only" not in sys.argv
    sync_all_and_restart(start_play=should_play)
