import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities")))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
luau = """
local p = game.Players.LocalPlayer
if p and p:FindFirstChild("PlayerGui") then
    local list = {}
    for _, g in ipairs(p.PlayerGui:GetChildren()) do
        table.insert(list, g.ClassName .. ": " .. g.Name .. " (Enabled=" .. tostring(g.Enabled) .. ")")
    end
    return table.concat(list, "\\n")
end
return "No PlayerGui"
"""
res = client.execute_luau(luau, datamodel_type="Client")
if "not available" in str(res):
    res = client.execute_luau(luau, datamodel_type="Server")
print("Found in Studio:")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
