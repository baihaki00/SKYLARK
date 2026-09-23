import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local StarterGui = game:GetService("StarterGui")
local lines = { "StarterGui Children:" }
for _, ch in ipairs(StarterGui:GetChildren()) do
    table.insert(lines, "  " .. ch.Name .. " (" .. ch.ClassName .. ")")
end
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
table.insert(lines, "StarterPlayerScripts Children:")
if sps then
    for _, ch in ipairs(sps:GetChildren()) do
        table.insert(lines, "  " .. ch.Name .. " (" .. ch.ClassName .. ")")
    end
end
return table.concat(lines, "\\n")
"""
res = client.execute_luau(code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
