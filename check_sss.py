from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local sss = game:GetService("ServerScriptService")
local list = {}
for _, ch in ipairs(sss:GetChildren()) do
    table.insert(list, ch.Name .. " (" .. ch.ClassName .. ")")
end

local g = _G.GameModeManager or shared.GameModeManager
local gmmFound = g ~= nil

return "SSS children: " .. table.concat(list, ", ") .. " | GMM found: " .. tostring(gmmFound)
"""
res = c.execute_luau(code, "Server")
print("Check SSS:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
