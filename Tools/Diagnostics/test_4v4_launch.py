import sys
import os
import json
import time
import base64

sys.stdout.reconfigure(encoding='utf-8')
sys.path.append(r'C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities')
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

brain_dir = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

# 1. Switch to GameModes tab and find & click the Launch 4 vs 4 button
client_luau = """
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pGui = player and player:WaitForChild("PlayerGui", 5)
if not pGui then return { error = "No PlayerGui" } end

local labUI = pGui:WaitForChild("AnimationLabUI", 5)
local mainFrame = labUI and labUI:FindFirstChild("MainFrame")
if not mainFrame then return { error = "No MainFrame" } end

-- Ensure open
mainFrame.Visible = true

-- Switch to GameModes tab
mainFrame:SetAttribute("ActiveTab", "GameModes")

local targetBtn = nil
for _, desc in ipairs(mainFrame:GetDescendants()) do
    if desc:IsA("TextButton") and desc.Text:find("4 vs 4") then
        targetBtn = desc
        break
    end
end

if not targetBtn then
    return { error = "No 4 vs 4 button found in mainFrame descendants" }
end

-- Fire the exact remote event that the button triggers
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Events = QuinCore:WaitForChild("Events")
local labEvent = Events:WaitForChild("AnimationLabEvent")

labEvent:FireServer("SetGameMode", { mode = "team", count = 4 })

return {
    success = true,
    foundButtonText = targetBtn.Text,
    parentName = targetBtn.Parent.Name,
    tabSwitched = mainFrame:GetAttribute("ActiveTab")
}
"""

res_click = client.execute_luau(client_luau, datamodel_type="Client")
print("Client action result:", res_click.get("result", {}).get("content", [{}])[0].get("text", ""))

print("\nWaiting 6 seconds for 4v4 team spawn, scatter, countdown, and combat...")
time.sleep(6)

# 2. Inspect Quins on Server
poll_server = """
local Workspace = game:GetService("Workspace")
local LogService = game:GetService("LogService")

local quins = {}
local qServer = Workspace:FindFirstChild("QuinServer")
if qServer then
    for _, ch in ipairs(qServer:GetChildren()) do
        local hum = ch:FindFirstChildOfClass("Humanoid")
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        table.insert(quins, {
            name = ch.Name,
            team = ch:GetAttribute("Team"),
            state = ch:GetAttribute("CurrentState"),
            tactical = ch:GetAttribute("TacticalState"),
            target = ch:GetAttribute("TargetQuin"),
            health = hum and hum.Health or nil,
            speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0,
            pos = hrp and tostring(hrp.Position) or "none",
            breadcrumb = ch:GetAttribute("TraceBreadcrumb")
        })
    end
end

local logs = LogService:GetLogHistory()
local errors = {}
for _, entry in ipairs(logs) do
    if tostring(entry.messageType):find("Error") then
        table.insert(errors, entry.message)
    end
end

return {
    quinCount = #quins,
    matchStarted = Workspace:GetAttribute("MatchStarted"),
    currentMode = Workspace:GetAttribute("CurrentMode"),
    quins = quins,
    errors = errors
}
"""

res_poll = client.execute_luau(poll_server, datamodel_type="Server")
content = res_poll.get("result", {}).get("content", [{}])[0].get("text", "")
data = json.loads(content)

print(f"\nActive Quins: {data.get('quinCount')}")
print(f"MatchStarted: {data.get('matchStarted')}")
print(f"Errors count: {len(data.get('errors', []))}")
for err in data.get("errors", []):
    print(f"  [ERROR] {err}")

q_list = data.get("quins", [])
if isinstance(q_list, dict):
    q_list = list(q_list.values())

for q in q_list:
    print(f"  {q.get('name')} [{q.get('team')}] -> State: {q.get('state')} | Tact: {q.get('tactical')} | Target: {q.get('target')} | Spd: {q.get('speed'):.1f} | HP: {q.get('health')}")

# 3. Screencapture of the active 4v4 battle with UI open on Game Modes tab
print("\nCapturing live 4v4 battle screenshot...")
cap_res = client.call_tool("screen_capture", {
    "studio_id": client.studio_id,
    "capture_id": "screen_capture_4v4_battle_verified",
    "camera_position": [0, 30, 45],
    "look_at_position": [0, 5, 0]
})

filepath = os.path.join(brain_dir, "screen_capture_4v4_battle_verified.png")
if cap_res and not cap_res.get("isError", False):
    for item in cap_res.get("result", {}).get("content", []):
        if item.get("type") == "image":
            with open(filepath, "wb") as f:
                f.write(base64.b64decode(item.get("data", "")))
            print(f"[OK] Saved screenshot to {filepath}")
