import sys
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.append(r'C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities')
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

diag_luau = """
local LogService = game:GetService("LogService")
local logs = LogService:GetLogHistory()
local errs = {}
for _, entry in ipairs(logs) do
    local mType = tostring(entry.messageType)
    if mType:find("Error") or mType:find("Warning") or entry.message:find("error") or entry.message:find("Error") or entry.message:find("Main") or entry.message:find("Quin") then
        table.insert(errs, {
            time = entry.timestamp,
            type = mType,
            msg = entry.message
        })
    end
end
return errs
"""

res = client.execute_luau(diag_luau, datamodel_type="Server")
content = res.get("result", {}).get("content", [{}])[0].get("text", "")
data = json.loads(content)

items = []
if isinstance(data, dict):
    for k in sorted(data.keys(), key=lambda x: int(x) if x.isdigit() else str(x)):
        items.append(data[k])
else:
    items = data

print(f"Total matching log entries: {len(items)}")
for item in items[-40:]:
    print(f"[{item.get('type')}] {item.get('msg')}")
