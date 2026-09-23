import sys
import json
import time
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Launch a 4v4 team match to observe long-range chase behavior across the 600x600 arena
launch_code = """
local labEvent = game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Events"):WaitForChild("AnimationLabEvent")
labEvent:FireServer("SetGameMode", { mode = "team", count = 4 })
return "Launched 4v4"
"""

res = client.execute_luau(launch_code, datamodel_type="Client")
print(res)

time.sleep(3.0)

# Query live states and positions of all active Quins
inspect_code = """
local Workspace = game:GetService("Workspace")
local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
local HttpService = game:GetService("HttpService")

local quins = {}
for _, model in ipairs(quinServer:GetDescendants()) do
    if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and model.Name:find("Quin") then
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local hum = model:FindFirstChildOfClass("Humanoid")
        table.insert(quins, {
            name = model.Name,
            state = model:GetAttribute("CurrentState") or "None",
            action = model:GetAttribute("RecommendedAction") or "None",
            tactical = model:GetAttribute("TacticalState") or "None",
            speed = hum and math.floor(hum.WalkSpeed) or 0,
            pos = hrp and string.format("(%.1f, %.1f)", hrp.Position.X, hrp.Position.Z) or "(0,0)"
        })
    end
end

return HttpService:JSONEncode(quins)
"""

res2 = client.execute_luau(inspect_code, datamodel_type="Server")
print("Live Quins State in Arena:")
print(res2.get("result", {}).get("content", [{}])[0].get("text", ""))
