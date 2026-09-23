import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Step 1: Clear the stale Strafe overrides from the DataStore
clear_code = """
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local store = DataStoreService:GetDataStore("KibaAnimationLabOverrides_v1")

local success, data = pcall(function()
    return store:GetAsync("Overrides")
end)
if not success or type(data) ~= "table" then
    return "No overrides found or error: " .. tostring(data)
end

-- Remove ALL stale Strafe entries from the DataStore overrides
local staleKeys = {
    "Strafe.StrafeLeftRun",
    "Strafe.StrafeLeftWalk",
    "Strafe.StrafeLeftTired",
    "Strafe.StrafeRightRun",
    "Strafe.StrafeRightWalk",
    "Strafe.StrafeRightTired",
}

local removed = {}
for _, key in ipairs(staleKeys) do
    if data[key] then
        table.insert(removed, {key = key, oldId = data[key].id})
        data[key] = nil
    end
end

-- Save the cleaned overrides back
local saveOk, saveErr = pcall(function()
    store:SetAsync("Overrides", data)
end)

if not saveOk then
    return HttpService:JSONEncode({success = false, error = tostring(saveErr)})
end

return HttpService:JSONEncode({
    success = true,
    removed = removed,
    remainingKeys = (function()
        local keys = {}
        for k in pairs(data) do table.insert(keys, k) end
        return keys
    end)()
})
"""

print("Step 1: Clearing stale Strafe overrides from DataStore...")
res = client.execute_luau(clear_code, datamodel_type="Server")
content = res.get("result", {}).get("content", [{}])[0].get("text", "")
print(content)

# Step 2: Now fix the in-memory persistentOverrides and AnimationConfig on Server
fix_server_code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:FindFirstChild("QuinCore")
local AnimationConfig = require(QuinCore:FindFirstChild("AnimationConfig"))
local HttpService = game:GetService("HttpService")

-- The correct new IDs (from AnimationConfig.lua source)
local corrections = {
    ["Strafe.StrafeLeftRun"] = "rbxassetid://123318024844911",
    ["Strafe.StrafeLeftWalk"] = "rbxassetid://71421932655009",
    ["Strafe.StrafeLeftTired"] = "rbxassetid://91032818959845",
    ["Strafe.StrafeRightRun"] = "rbxassetid://107962284182266",
    ["Strafe.StrafeRightWalk"] = "rbxassetid://82291519563301",
    ["Strafe.StrafeRightTired"] = "rbxassetid://110691224052109",
}

local fixed = {}
for path, correctId in pairs(corrections) do
    local entry = AnimationConfig.get(path)
    if entry then
        local oldId = entry.id
        if oldId ~= correctId then
            AnimationConfig.update(path, {id = correctId})
            table.insert(fixed, {path = path, wasWrong = oldId, nowCorrect = correctId})
        else
            table.insert(fixed, {path = path, alreadyCorrect = true})
        end
    end
end

return HttpService:JSONEncode(fixed)
"""

print("\nStep 2: Restoring correct IDs in Server AnimationConfig...")
res2 = client.execute_luau(fix_server_code, datamodel_type="Server")
content2 = res2.get("result", {}).get("content", [{}])[0].get("text", "")
print(content2)

# Step 3: Fix Client AnimationConfig too
print("\nStep 3: Restoring correct IDs in Client AnimationConfig...")
res3 = client.execute_luau(fix_server_code, datamodel_type="Client")
content3 = res3.get("result", {}).get("content", [{}])[0].get("text", "")
print(content3)

# Step 4: Verify
verify_code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:FindFirstChild("QuinCore")
local AnimationConfig = require(QuinCore:FindFirstChild("AnimationConfig"))
local HttpService = game:GetService("HttpService")

local strafePaths = {
    "Strafe.StrafeLeftRun", "Strafe.StrafeLeftWalk", "Strafe.StrafeLeftTired",
    "Strafe.StrafeRightRun", "Strafe.StrafeRightWalk", "Strafe.StrafeRightTired"
}
local result = {}
for _, p in ipairs(strafePaths) do
    local e = AnimationConfig.get(p)
    result[p] = e and e.id or "NOT FOUND"
end
return HttpService:JSONEncode(result)
"""

print("\nStep 4: Verifying Server...")
res4 = client.execute_luau(verify_code, datamodel_type="Server")
print(res4.get("result", {}).get("content", [{}])[0].get("text", ""))

print("\nVerifying Client...")
res5 = client.execute_luau(verify_code, datamodel_type="Client")
print(res5.get("result", {}).get("content", [{}])[0].get("text", ""))
