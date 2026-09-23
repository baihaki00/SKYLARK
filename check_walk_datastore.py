import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("KibaAnimationLabOverrides_v1")
local HttpService = game:GetService("HttpService")

local ok, data = pcall(function() return store:GetAsync("Overrides") end)
if not ok or type(data) ~= "table" then return "Error or nil" end

local walkKeys = {}
for k, v in pairs(data) do
    if k:find("Walk") then
        walkKeys[k] = v
    end
end

return HttpService:JSONEncode(walkKeys)
"""

print("Checking DataStore for Walk overrides...")
res = client.execute_luau(code, datamodel_type="Edit")
print("Walk overrides in DataStore:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
