from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local rs = game:GetService("ReplicatedStorage")
local idle = rs.QuinCore.States:FindFirstChild("IdleState")
if not idle then return "No IdleState in RS" end
local lines = string.split(idle.Source, "\n")
local out = {}
for i = 1, math.min(#lines, 60) do
    table.insert(out, string.format("%2d: %s", i, lines[i]))
end
return table.concat(out, "\n")
"""
res = c.execute_luau(code, "Edit")
print("Studio IdleState lines 1-60:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
