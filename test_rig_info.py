from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local quin = workspace:FindFirstChild("QuinTest") or workspace:FindFirstChild("Quin_Rig")
if not quin then
    for _, ch in ipairs(workspace:GetChildren()) do
        if ch:FindFirstChild("Humanoid") then
            quin = ch
            break
        end
    end
end

if not quin then
    return "No Quin found in workspace to test"
end

local alpha = quin:FindFirstChild("Alpha_Surface")
if not alpha then
    return "No Alpha_Surface found"
end

-- Test 1: What is the exact ClassName and properties of Alpha_Surface?
local info = {
    ClassName = alpha.ClassName,
    Color = tostring(alpha.Color),
    TextureID = alpha.TextureID,
    Material = alpha.Material.Name
}

-- Let's check if there are attachments or bones in Alpha_Surface
local bones = 0
local attachments = 0
for _, d in ipairs(quin:GetDescendants()) do
    if d:IsA("Bone") then bones = bones + 1 end
    if d:IsA("Attachment") then attachments = attachments + 1 end
end
info.Bones = bones
info.Attachments = attachments

local res = {}
for k, v in pairs(info) do
    table.insert(res, k .. ": " .. tostring(v))
end
return table.concat(res, " | ")
"""
res = c.execute_luau(code, "Edit")
print("Quin Rig Info:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
