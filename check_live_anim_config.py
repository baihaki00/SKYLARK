import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Check Client AnimationConfig
client_code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:FindFirstChild("QuinCore")
if not QuinCore then return "No QuinCore" end
local AnimationConfig = require(QuinCore:FindFirstChild("AnimationConfig"))
local HttpService = game:GetService("HttpService")

local strafe = AnimationConfig.Registry and AnimationConfig.Registry.Strafe
return HttpService:JSONEncode(strafe)
"""

res_client = client.execute_luau(client_code, datamodel_type="Client")
print("Client AnimationConfig.Registry.Strafe:")
print(res_client)

# Check Server AnimationConfig
res_server = client.execute_luau(client_code, datamodel_type="Server")
print("Server AnimationConfig.Registry.Strafe:")
print(res_server)
