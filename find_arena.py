from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
code = """
local results = {}
for _, child in ipairs(workspace:GetChildren()) do
    if child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart") then
        local posStr = ""
        if child:IsA("BasePart") then
            posStr = string.format(" Pos: (%.1f, %.1f, %.1f)", child.Position.X, child.Position.Y, child.Position.Z)
        elseif child:IsA("Model") and child.PrimaryPart then
            posStr = string.format(" Pos: (%.1f, %.1f, %.1f)", child.PrimaryPart.Position.X, child.PrimaryPart.Position.Y, child.PrimaryPart.Position.Z)
        end
        table.insert(results, string.format("%s [%s]%s", child.Name, child.ClassName, posStr))
    end
end
return table.concat(results, "\\n")
"""

res = client.execute_luau(code, "Edit")
print("=== WORKSPACE CHILDREN ===")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
client.close()
