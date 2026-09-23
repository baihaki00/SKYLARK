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

# 1. Trigger Team Battle 4v4 via Server
trigger_luau = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local labEvent = ReplicatedStorage:WaitForChild("AnimationLabRemote", 5)
if labEvent then
    -- Simulate client calling SetGameMode team with 4
    local GMM = _G.GameModeManager
    if GMM and GMM.startTeamBattle then
        GMM.startTeamBattle(4)
        return { success = true, mode = "startTeamBattle(4)" }
    else
        return { error = "No GameModeManager or startTeamBattle" }
    end
else
    return { error = "No AnimationLabRemote" }
end
"""

res_trigger = client.execute_luau(trigger_luau, datamodel_type="Server")
print("Trigger result:", res_trigger.get("result", {}).get("content", [{}])[0].get("text", ""))

print("Waiting 5 seconds for Quins to spawn and enter combat loops...")
time.sleep(5)

# 2. Poll Quins in Server
poll_luau = """
local Workspace = game:GetService("Workspace")
local LogService = game:GetService("LogService")

local quins = {}
local qServer = Workspace:FindFirstChild("QuinServer")
if qServer then
    for _, ch in ipairs(qServer:GetChildren()) do
        local hum = ch:FindFirstChildOfClass("Humanoid")
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        local main = ch:FindFirstChild("Main")
        table.insert(quins, {
            name = ch.Name,
            team = ch:GetAttribute("Team"),
            state = ch:GetAttribute("CurrentState"),
            tactical = ch:GetAttribute("TacticalState"),
            target = ch:GetAttribute("TargetQuin"),
            health = hum and hum.Health or nil,
            speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0,
            hasMain = (main ~= nil),
            breadcrumb = ch:GetAttribute("TraceBreadcrumb")
        })
    end
end

-- Check logs for any errors
local logs = LogService:GetLogHistory()
local errors = {}
for _, entry in ipairs(logs) do
    if tostring(entry.messageType):find("Error") then
        table.insert(errors, entry.message)
    end
end

return {
    quinCount = #quins,
    quins = quins,
    matchStarted = Workspace:GetAttribute("MatchStarted"),
    errors = errors
}
"""

res_poll = client.execute_luau(poll_luau, datamodel_type="Server")
content = res_poll.get("result", {}).get("content", [{}])[0].get("text", "")
poll_data = json.loads(content)

print(f"\nActive Quins: {poll_data.get('quinCount')}")
print(f"MatchStarted: {poll_data.get('matchStarted')}")
print(f"Server Errors Count: {len(poll_data.get('errors', []))}")
for err in poll_data.get("errors", []):
    print(f"  [ERROR] {err}")

quin_items = poll_data.get("quins", [])
if isinstance(quin_items, dict):
    quin_items = list(quin_items.values())

for q in quin_items:
    print(f"  {q.get('name')} | Team: {q.get('team')} | State: {q.get('state')} | Tact: {q.get('tactical')} | Target: {q.get('target')} | Spd: {q.get('speed'):.1f} | Breadcrumb: {q.get('breadcrumb')}")

# 3. Screen capture to verify visually
print("\nTaking screencapture...")
cap_res = client.call_tool("screen_capture", {
    "studio_id": client.studio_id,
    "capture_id": "screen_capture_match_active_verified",
    "camera_position": [0, 25, 40],
    "look_at_position": [0, 5, 0]
})

filepath = os.path.join(brain_dir, "screen_capture_match_active_verified.png")
if cap_res and not cap_res.get("isError", False):
    c_list = cap_res.get("result", {}).get("content", [])
    for item in c_list:
        if item.get("type") == "image":
            with open(filepath, "wb") as f:
                f.write(base64.b64decode(item.get("data", "")))
            print(f"[OK] Saved screenshot to {filepath}")
else:
    print("[WARN] Screencapture response:", cap_res)
