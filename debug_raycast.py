from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local rs = game:GetService("ReplicatedStorage")

local origin = Vector3.new(-124, 4.5, 15)
local dir = Vector3.new(0, 0, 1) * 25

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local hit = workspace:Raycast(origin, dir, params)
if hit then
    return string.format("Hit: %s at pos (%.1f, %.1f, %.1f), CanCollide=%s",
        hit.Instance:GetFullName(), hit.Position.X, hit.Position.Y, hit.Position.Z, tostring(hit.Instance.CanCollide))
else
    return "No hit at all!"
end
"""
res = c.execute_luau(code, "Edit")
print("Raycast debug:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
