import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local LogService = game:GetService("LogService")
local history = LogService:GetLogHistory()
local errors = {}
local warnings = {}

for _, entry in ipairs(history) do
    if entry.messageType == Enum.MessageType.MessageError then
        table.insert(errors, entry.message)
    elseif entry.messageType == Enum.MessageType.MessageWarning then
        if entry.message:find("Quin") or entry.message:find("State") or entry.message:find("Locomotion") then
            table.insert(warnings, entry.message)
        end
    end
end

return string.format("Log History Count: %d | Errors: %d | Relevant Warnings: %d\\nErrors:\\n%s\\nWarnings:\\n%s",
    #history, #errors, #warnings,
    table.concat(errors, "\\n"),
    table.concat(warnings, "\\n"))
"""
res = client.execute_luau(code, datamodel_type="Server")
if res.get("isError"):
    print("ERROR:", res)
else:
    print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
