import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local Workspace = game:GetService("Workspace")
local spawnJump = Workspace:FindFirstChild("QuinSpawnJump", true) or Workspace:FindFirstChild("QuinSpawn", true)
local dummy = Workspace:FindFirstChild("TrainingDummy", true) or Workspace:FindFirstChild("Dummy", true)
return string.format("QuinSpawn: %s | Dummy: %s",
    spawnJump and spawnJump:GetFullName() or "NIL",
    dummy and dummy:GetFullName() or "NIL")
"""
res = client.execute_luau(code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
