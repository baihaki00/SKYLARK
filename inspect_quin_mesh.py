from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local quin = workspace:FindFirstChild("Quin_Rig") or workspace:FindFirstChild("Rig")
if not quin then
    for _, ch in ipairs(workspace:GetChildren()) do
        if ch:FindFirstChild("Humanoid") then
            quin = ch
            break
        end
    end
end

if quin then
    local parts = {}
    for _, p in ipairs(quin:GetDescendants()) do
        if p:IsA("BasePart") then
            local tid = ""
            if p:IsA("MeshPart") then
                tid = p.TextureID
            end
            table.insert(parts, p.Name .. " (" .. p.ClassName .. ", texture=" .. tid .. ", color=" .. tostring(p.Color) .. ")")
        end
    end
    return "QUIN FOUND: " .. quin.Name .. " | " .. table.concat(parts, " // ")
else
    return "No Quin found in workspace"
end
"""
res = c.execute_luau(code, "Edit")
print("Inspect result:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
