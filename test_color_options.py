import sys
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local template = ReplicatedStorage.QuinType:FindFirstChild("QuinTypeA")

if not template then return "Template not found" end

-- Clean old test models
local oldA = Workspace:FindFirstChild("TestQuin_PureColor")
if oldA then oldA:Destroy() end
local oldB = Workspace:FindFirstChild("TestQuin_CleanTint")
if oldB then oldB:Destroy() end

-- Test 1: Pure MeshPart Color (TextureID cleared)
local q1 = template:Clone()
q1.Name = "TestQuin_PureColor"
q1.Parent = Workspace
q1:PivotTo(CFrame.new(0, 10, -10))
local surf1 = q1:FindFirstChild("Alpha_Surface", true)
if surf1 then
    surf1.TextureID = ""
    surf1.Color = Color3.fromRGB(255, 60, 40) -- Vibrant Fire Red
    surf1.Material = Enum.Material.SmoothPlastic
end

-- Test 2: Clean Fill Tint Highlight (OutlineTransparency = 1.0, NO OUTLINE)
local q2 = template:Clone()
q2.Name = "TestQuin_CleanTint"
q2.Parent = Workspace
q2:PivotTo(CFrame.new(0, 10, 10))
local hl = Instance.new("Highlight")
hl.Name = "ElementHighlight"
hl.FillColor = Color3.fromRGB(40, 160, 255) -- Vibrant Water Blue
hl.FillTransparency = 0.50
hl.OutlineColor = Color3.fromRGB(40, 160, 255)
hl.OutlineTransparency = 1.0 -- COMPLETELY INVISIBLE OUTLINE
hl.Adornee = q2
hl.Parent = q2

return "Spawned TestQuin_PureColor (red solid) and TestQuin_CleanTint (blue wash with texture)"
"""

res = client.execute_luau(code, datamodel_type="Edit")
print("Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
