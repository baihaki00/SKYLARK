import sys
import json
import os
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local targetPos = Vector3.new(-1, 7.3, 17.2)
local parts = {}
for _, p in ipairs(workspace:GetDescendants()) do
    if p:IsA("BasePart") and p.CanCollide then
        local minP = p.Position - p.Size/2
        local maxP = p.Position + p.Size/2
        if targetPos.X >= minP.X - 2 and targetPos.X <= maxP.X + 2 and
           targetPos.Z >= minP.Z - 2 and targetPos.Z <= maxP.Z + 2 then
            table.insert(parts, p:GetFullName() .. " size=" .. tostring(p.Size) .. " pos=" .. tostring(p.Position))
        end
    end
end
return game:GetService("HttpService"):JSONEncode(parts)
"""
res = client.execute_luau(code, datamodel_type="Server")
raw_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Parts near (-1, 7.3, 17.2):", raw_text)
client.close()
