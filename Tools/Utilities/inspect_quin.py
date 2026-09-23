import sys
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local q = workspace:FindFirstChild("Quin_TypeD_5E10", true)
if not q then
    -- Find any Quin that is currently in FightState with dist > 20
    for _, item in ipairs(game:GetService("CollectionService"):GetTagged("Quin")) do
        if item:GetAttribute("CurrentState") == "Fight" then
            q = item
            break
        end
    end
end
if not q then return "None found" end

local attrs = q:GetAttributes()
local hum = q:FindFirstChildOfClass("Humanoid")
attrs.Health = hum and hum.Health or 0
attrs.MaxHealth = hum and hum.MaxHealth or 0
attrs.Name = q.Name
return game:GetService("HttpService"):JSONEncode(attrs)
"""
res = client.execute_luau(code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
