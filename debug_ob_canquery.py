from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local ob = nil
for _, p in ipairs(workspace:GetDescendants()) do
    if p:IsA("BasePart") and p.Name == "OB" and math.abs(p.Position.X - (-124)) < 1 then
        ob = p
        break
    end
end
if not ob then return "No OB" end

local origin = Vector3.new(-124, 4.5, 20)
local dir = Vector3.new(0, 0, 15)

local hit = workspace:Raycast(origin, dir)
if hit then
    return "Hit: " .. hit.Instance:GetFullName() .. " at " .. tostring(hit.Position)
else
    -- Let's check part properties
    return string.format("No hit! OB CanCollide=%s, CanQuery=%s, CanTouch=%s, CollisionGroup=%s",
        tostring(ob.CanCollide), tostring(ob.CanQuery), tostring(ob.CanTouch), ob.CollisionGroup)
end
"""
res = c.execute_luau(code, "Edit")
print("Raycast test 2:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
