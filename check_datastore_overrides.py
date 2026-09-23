import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("KibaAnimationLabOverrides_v1")
local HttpService = game:GetService("HttpService")

local success, data = pcall(function()
    return store:GetAsync("Overrides")
end)

return HttpService:JSONEncode({success = success, data = data})
"""

res = client.execute_luau(code, datamodel_type="Server")
print("KibaAnimationLabOverrides_v1 Overrides:")
print(res)
