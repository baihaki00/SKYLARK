import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local Workspace = game:GetService("Workspace")
local ghostFolder = Workspace:FindFirstChild("QuinGhost")
local g = ghostFolder and ghostFolder:FindFirstChild("QuinA_Runner_Visual")
if not g then return "No QuinA_Runner_Visual found" end

local alpha = g:FindFirstChild("Alpha_Surface")
if not alpha then return "No Alpha_Surface" end

local props = {}
table.insert(props, "ClassName: " .. alpha.ClassName)
table.insert(props, "Transparency: " .. alpha.Transparency)
table.insert(props, "Color: " .. tostring(alpha.Color))
table.insert(props, "Material: " .. tostring(alpha.Material))
if alpha:IsA("MeshPart") then
    table.insert(props, "MeshId: " .. tostring(alpha.MeshId))
    table.insert(props, "TextureID: " .. tostring(alpha.TextureID))
end

-- Also check all other children of g
local other = {}
for _, ch in ipairs(g:GetChildren()) do
    table.insert(other, ch.Name .. " (" .. ch.ClassName .. ")")
end
table.insert(props, "Children: " .. table.concat(other, ", "))

return table.concat(props, "\\n")
"""
res = client.execute_luau(code, datamodel_type="Client")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
