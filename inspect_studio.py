from Tools.Utilities.roblox_client import RobloxStudioClient
import json

c = RobloxStudioClient()
code = """
local ss = game:GetService("ServerStorage")
local names = {}
for _, ch in ipairs(ss:GetChildren()) do
    table.insert(names, ch.Name)
end
return table.concat(names, ", ")
"""
res = c.execute_luau(code, "Edit")
print("ServerStorage children:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
