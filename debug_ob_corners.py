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

local corners = {}
local s = ob.Size / 2
for _, sx in ipairs({-1, 1}) do
    for _, sy in ipairs({-1, 1}) do
        for _, sz in ipairs({-1, 1}) do
            local pt = ob.CFrame:PointToWorldSpace(Vector3.new(sx * s.X, sy * s.Y, sz * s.Z))
            table.insert(corners, string.format("(%.1f, %.1f, %.1f)", pt.X, pt.Y, pt.Z))
        end
    end
end
return "Corners of OB:\n" .. table.concat(corners, "\n")
"""
res = c.execute_luau(code, "Edit")
print("OB Corners:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
