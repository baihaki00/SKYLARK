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
if not ok or type(data) ~= "table" then return "Error or not table: " .. tostring(data) end

local removed = {}
if data["Movement.WalkConfident"] then
    table.insert(removed, "Movement.WalkConfident")
    data["Movement.WalkConfident"] = nil
end
if data["Movement.WalkThug"] then
    table.insert(removed, "Movement.WalkThug")
    data["Movement.WalkThug"] = nil
end

local saveOk, saveErr = pcall(function()
    store:SetAsync("Overrides", data)
end)

return HttpService:JSONEncode({success = saveOk, removed = removed, error = tostring(saveErr)})
"""

print("Clearing walk overrides from DataStore...")
res = client.execute_luau(code, datamodel_type="Edit")
print("Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
