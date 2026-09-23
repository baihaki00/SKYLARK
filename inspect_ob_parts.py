from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local obs = {}
for _, p in ipairs(workspace:GetDescendants()) do
    if p:IsA("BasePart") and (p.Name == "OB" or p.Name:find("OB")) then
        table.insert(obs, string.format("%s: Pos=(%.1f, %.1f, %.1f), Size=(%.1f, %.1f, %.1f), TopY=%.1f",
            p.Name, p.Position.X, p.Position.Y, p.Position.Z, p.Size.X, p.Size.Y, p.Size.Z, p.Position.Y + p.Size.Y / 2))
    end
end
return string.format("Total OB parts: %d\n%s", #obs, table.concat(obs, "\n"))
"""
res = c.execute_luau(code, "Edit")
print("OB Parts in Workspace:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
