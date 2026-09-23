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

local info = {
    ClassName = ob.ClassName,
    Parent = ob.Parent:GetFullName(),
    Position = tostring(ob.Position),
    Size = tostring(ob.Size),
    Shape = ob:IsA("Part") and tostring(ob.Shape) or "N/A"
}
local out = {}
for k, v in pairs(info) do table.insert(out, k .. ": " .. v) end
return table.concat(out, "\n")
"""
res = c.execute_luau(code, "Edit")
print("OB Class info:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
