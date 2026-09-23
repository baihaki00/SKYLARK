import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:FindFirstChild("QuinCore")
local AnimationConfig = require(QuinCore:FindFirstChild("AnimationConfig"))
local HttpService = game:GetService("HttpService")

local allPaths = AnimationConfig.getAllPaths()
local strafePaths = {}
for _, item in ipairs(allPaths) do
    if item.category:find("Strafe") or item.path:find("Strafe") then
        table.insert(strafePaths, {
            path = item.path,
            name = item.name,
            id = item.entry and item.entry.id
        })
    end
end

return HttpService:JSONEncode(strafePaths)
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res)
