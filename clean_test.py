from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local quin = workspace:FindFirstChild("QuinTest")
if quin then
    local r = quin:FindFirstChild("TeamRing")
    if r then r:Destroy() end
    local hl = quin:FindFirstChild("ElementHighlight")
    if hl then hl:Destroy() end
end
return "Cleaned QuinTest complete"
"""
res = c.execute_luau(code, "Edit")
print("Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
