from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
for _, p in ipairs(workspace:GetDescendants()) do
    if p:IsA("BasePart") and p.Name == "OB" and math.abs(p.Position.X - (-124)) < 1 then
        return string.format("Found OB: CFrame=%s, Size=%s, CanCollide=%s, Transparency=%f",
            tostring(p.CFrame), tostring(p.Size), tostring(p.CanCollide), p.Transparency)
    end
end
return "Not found"
"""
res = c.execute_luau(code, "Edit")
print("OB detail:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
