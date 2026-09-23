import sys
import json
import os
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local logService = game:GetService("LogService")
local logs = logService:GetLogHistory()
local ghostLogs = {}
for _, entry in ipairs(logs) do
    if entry.messageType.Name == "MessageError" then
        table.insert(ghostLogs, entry.message)
    end
end
local lastErrors = {}
for i = math.max(1, #ghostLogs - 10), #ghostLogs do
    table.insert(lastErrors, ghostLogs[i])
end
return game:GetService("HttpService"):JSONEncode(lastErrors)
"""
res = client.execute_luau(code, datamodel_type="Client")
raw_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Client Log History:", raw_text)

# Also check Workspace.QuinGhost
check_ghost = """
local qg = workspace:FindFirstChild("QuinGhost")
local count = qg and #qg:GetChildren() or 0
local names = {}
if qg then
    for _, c in ipairs(qg:GetChildren()) do
        table.insert(names, c.Name)
    end
end
return game:GetService("HttpService"):JSONEncode({
    ghostCount = count,
    ghostNames = names
})
"""
res2 = client.execute_luau(check_ghost, datamodel_type="Client")
print("QuinGhost folder:", res2.get("result", {}).get("content", [{}])[0].get("text", ""))

client.close()
