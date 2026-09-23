import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Simulate what happens when user clicks Strafe category then StrafeRightRun:
# selectAnimation calls AnimationConfig.get(path) — let's verify what it returns
code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:FindFirstChild("QuinCore")
local AnimationConfig = require(QuinCore:FindFirstChild("AnimationConfig"))
local HttpService = game:GetService("HttpService")

local entry = AnimationConfig.get("Strafe.StrafeRightRun")
return HttpService:JSONEncode({
    path = "Strafe.StrafeRightRun",
    id = entry and entry.id,
    name = entry and entry.name,
    speed = entry and entry.speed,
})
"""

print("Client AnimationConfig.get('Strafe.StrafeRightRun'):")
res = client.execute_luau(code, datamodel_type="Client")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Also verify DataStore is clean now
ds_code = """
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local store = DataStoreService:GetDataStore("KibaAnimationLabOverrides_v1")
local ok, data = pcall(function() return store:GetAsync("Overrides") end)
if not ok or type(data) ~= "table" then return "Error or nil" end

local strafeKeys = {}
for k, v in pairs(data) do
    if k:find("Strafe") then
        strafeKeys[k] = v.id
    end
end
return HttpService:JSONEncode({strafeKeysInDataStore = strafeKeys, totalOverrides = (function() local c=0; for _ in pairs(data) do c=c+1 end; return c end)()})
"""

print("\nDataStore verification (should have zero Strafe keys):")
res2 = client.execute_luau(ds_code, datamodel_type="Server")
print(res2.get("result", {}).get("content", [{}])[0].get("text", ""))
