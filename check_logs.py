from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
code = """
local LogService = game:GetService("LogService")
local logs = LogService:GetLogHistory()
local recent = {}
for i = math.max(1, #logs - 40), #logs do
    table.insert(recent, logs[i].message)
end
return table.concat(recent, "\\n")
"""

res = client.execute_luau(code, "Server")
content = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("=== SERVER LOGS ===")
print(content)
client.close()
