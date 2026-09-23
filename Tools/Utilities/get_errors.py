import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local logs = LogService:GetLogHistory()
local errors = {}
for _, entry in ipairs(logs) do
    if entry.messageType == Enum.MessageType.MessageError or entry.messageType == Enum.MessageType.MessageWarning then
        table.insert(errors, {
            type = tostring(entry.messageType),
            msg = entry.message,
            time = entry.timestamp
        })
    end
end
return HttpService:JSONEncode(errors)
"""
res = client.execute_luau(code, datamodel_type="Server")
txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
try:
    data = json.loads(txt)
    print(f"FOUND {len(data)} ERRORS/WARNINGS:")
    for d in data[-25:]: # last 25
        print(f"  [{d['type']}] {d['msg']}")
except Exception as e:
    print(f"Error parsing: {e}, raw: {txt}")
client.close()
