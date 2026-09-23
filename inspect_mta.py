from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
code = """
local mta = workspace:FindFirstChild("MovementTestArena")
if not mta then return "MovementTestArena folder not found" end

local items = {}
for _, desc in ipairs(mta:GetDescendants()) do
    if desc:IsA("BasePart") or desc:IsA("Model") or desc:IsA("SpawnLocation") then
        local p = desc:IsA("BasePart") and desc.Position or (desc.PrimaryPart and desc.PrimaryPart.Position or Vector3.zero)
        table.insert(items, string.format("%s [%s] at (%.1f, %.1f, %.1f) Size: (%.1f, %.1f, %.1f)", 
            desc.Name, desc.ClassName, p.X, p.Y, p.Z, 
            desc:IsA("BasePart") and desc.Size.X or 0, 
            desc:IsA("BasePart") and desc.Size.Y or 0, 
            desc:IsA("BasePart") and desc.Size.Z or 0))
    end
end
return table.concat(items, "\\n")
"""

res = client.execute_luau(code, "Edit")
print("=== MOVEMENT TEST ARENA CONTENTS ===")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
client.close()
