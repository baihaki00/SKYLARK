import os
import shutil
import json
import time

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
util_dir = os.path.join(scratch_dir, "Tools", "Utilities")
import sys
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

TAG = sys.argv[1] if len(sys.argv) > 1 else "20260920_SpectatorHUD_Wrapping_LeftMouseCameraFix_Verified"
backup_name = f"QuinCore_Frozen_Stable_{TAG}"
backup_disk_dir = os.path.join(scratch_dir, f"backup_frozen_stable_{TAG}")

# 1. Local Disk Backup
os.makedirs(backup_disk_dir, exist_ok=True)
copied_count = 0
for f in os.listdir(scratch_dir):
    if f.endswith(".lua"):
        src = os.path.join(scratch_dir, f)
        dst = os.path.join(backup_disk_dir, f)
        shutil.copy2(src, dst)
        copied_count += 1

print(f"Local Disk Backup created: {copied_count} Lua files saved to {backup_disk_dir}")

# 2. Studio ServerStorage Backup (in Edit datamodel)
client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

st = client.get_studio_state()
txt = st.get("result", {}).get("content", [{}])[0].get("text", "")
if "Current Studio Mode: Play" in txt:
    print("Stopping Play mode to access Edit datamodel...")
    client.set_play_mode(False)
    time.sleep(2)

code = f"""
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerScriptService = game:GetService("ServerScriptService")

local existing = ServerStorage:FindFirstChild("{backup_name}")
if existing then
    existing:Destroy()
end

local backupFolder = Instance.new("Folder")
backupFolder.Name = "{backup_name}"
backupFolder.Parent = ServerStorage

local qc = ReplicatedStorage:FindFirstChild("QuinCore")
if qc then
    local qcClone = qc:Clone()
    qcClone.Name = "QuinCore"
    qcClone.Parent = backupFolder
end

local sssScripts = {{ "Server", "QuinSpawner", "QuinRosterService", "GameModeManager", "BattleSimulationHarness", "AnimationLabServer" }}
local sssFolder = Instance.new("Folder")
sssFolder.Name = "ServerScriptService"
sssFolder.Parent = backupFolder
for _, name in ipairs(sssScripts) do
    local s = ServerScriptService:FindFirstChild(name)
    if s then s:Clone().Parent = sssFolder end
end

local spsScripts = {{ "SmoothCamera", "QuinDebugHUD", "AIGhostHandler" }}
local spsFolder = Instance.new("Folder")
spsFolder.Name = "StarterPlayerScripts"
spsFolder.Parent = backupFolder
for _, name in ipairs(spsScripts) do
    local s = StarterPlayer.StarterPlayerScripts:FindFirstChild(name)
    if s then s:Clone().Parent = spsFolder end
end

local totalDesc = #backupFolder:GetDescendants()
return string.format("Frozen backup %s created successfully with %d descendants in ServerStorage.", "{backup_name}", totalDesc)
"""

res = client.execute_luau(code, "Edit")
print("Studio Backup Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))

print("Restarting Play mode...")
client.set_play_mode(True)
time.sleep(2)
client.close()
print("Freeze and backup complete.")
