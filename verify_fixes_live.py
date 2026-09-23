import sys
import json
import time
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Launch a 4v4 team match
launch_code = """
local labEvent = game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Events"):WaitForChild("AnimationLabEvent")
labEvent:FireServer("SetGameMode", { mode = "team", count = 4 })
return "Launched 4v4"
"""

print(client.execute_luau(launch_code, datamodel_type="Client"))

# Wait 5 seconds into the match and inspect state distribution & Highlights
time.sleep(5.0)

check_code = """
local Workspace = game:GetService("Workspace")
local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
local HttpService = game:GetService("HttpService")

local quins = {}
local totalHighlights = 0
local testEndCount = 0

for _, model in ipairs(quinServer:GetDescendants()) do
    if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and model.Name:find("Quin") then
        local state = model:GetAttribute("CurrentState") or "None"
        if state == "TestEnd" then
            testEndCount = testEndCount + 1
        end
        local hl = model:FindFirstChildOfClass("Highlight")
        if hl then totalHighlights = totalHighlights + 1 end

        local surf = model:FindFirstChild("Alpha_Surface", true)
        table.insert(quins, {
            name = model.Name,
            state = state,
            element = model:GetAttribute("Element") or "None",
            surfColor = surf and tostring(surf.Color) or "NoSurf",
            hasHighlight = (hl ~= nil),
        })
    end
end

return HttpService:JSONEncode({
    totalQuins = #quins,
    testEndCount = testEndCount,
    totalHighlights = totalHighlights,
    sampleQuins = { quins[1], quins[2], quins[3] }
})
"""

res = client.execute_luau(check_code, datamodel_type="Server")
print("Live Combat & Visual Telemetry:")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
