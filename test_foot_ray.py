from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local origin = Vector3.new(-124, 3.0, 10)
local dir = Vector3.new(0, 0, 1) * 25

local hit = workspace:Raycast(origin, dir)
if hit then
    return string.format("Foot ray hit: %s at pos (%.1f, %.1f, %.1f), Part Name=%s",
        hit.Instance:GetFullName(), hit.Position.X, hit.Position.Y, hit.Position.Z, hit.Instance.Name)
else
    return "Foot ray: no hit"
end
"""
res = c.execute_luau(code, "Edit")
print("Foot Raycast Result:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
