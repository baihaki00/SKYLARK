from Tools.Utilities.roblox_client import RobloxStudioClient
import time

c = RobloxStudioClient()
print("Starting 16v16 Team Battle to verify elemental highlights and cylinder removal...")

# Fire team 16 from client
c.execute_luau(r"""
local rs = game:GetService("ReplicatedStorage")
local cmd = rs:WaitForChild("GameCommand", 5)
if cmd then cmd:FireServer("team", 16) end
""", "Client")

# Wait for spawn
time.sleep(5)

# Verify Workspace QuinServer and QuinGhost
inspect_code = r"""
local ws = game:GetService("Workspace")
local qs = ws:FindFirstChild("QuinServer")
local qg = ws:FindFirstChild("QuinGhost")

local cylindersCount = 0
for _, d in ipairs(ws:GetDescendants()) do
    if d:IsA("BasePart") and d.Name == "TeamRing" then
        cylindersCount = cylindersCount + 1
    end
end

local elementsFound = {}
local highlightsCount = 0

if qs then
    for _, q in ipairs(qs:GetChildren()) do
        local elem = q:GetAttribute("Element") or "Unknown"
        elementsFound[elem] = (elementsFound[elem] or 0) + 1
        local hl = q:FindFirstChild("ElementHighlight")
        if hl and hl:IsA("Highlight") then
            highlightsCount = highlightsCount + 1
        end
    end
end

local ghostHighlights = 0
if qg then
    for _, g in ipairs(qg:GetChildren()) do
        local hl = g:FindFirstChild("ElementHighlight")
        if hl and hl:IsA("Highlight") then
            ghostHighlights = ghostHighlights + 1
        end
    end
end

local elemList = {}
for e, cnt in pairs(elementsFound) do
    table.insert(elemList, string.format("%s: %d", e, cnt))
end

return string.format(
    "TeamRing Cylinders: %d (MUST BE 0)\nServer Highlights: %d/%d\nGhost Highlights: %d/%d\nElement Distribution:\n  %s",
    cylindersCount, highlightsCount, qs and #qs:GetChildren() or 0,
    ghostHighlights, qg and #qg:GetChildren() or 0,
    table.concat(elemList, "\n  ")
)
"""

res = c.execute_luau(inspect_code, "Server")
print("Verification Result:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
