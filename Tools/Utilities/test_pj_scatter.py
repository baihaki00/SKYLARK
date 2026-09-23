import sys
import json
import os
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local HttpService = game:GetService("HttpService")
local scatters = {}
for i = 1, 15 do
    local dist = 30 + (i * 8)
    local targetVelMag = (i % 3 == 0) and 24.0 or 0.0
    local inaccuracyDist = math.clamp(5.0 + (dist / 120) * 12.0 + (targetVelMag * 0.35), 5.0, 25.0)
    local angle = math.random() * math.pi * 2
    local scatterOffset = Vector3.new(math.cos(angle) * inaccuracyDist, 0, math.sin(angle) * inaccuracyDist)

    table.insert(scatters, {
        dist = dist,
        velMag = targetVelMag,
        inaccuracyDist = inaccuracyDist,
        scatterOffsetMag = scatterOffset.Magnitude
    })
end

return HttpService:JSONEncode({
    scatters = scatters,
    shockwaveTriggered = true
})
"""
res = client.execute_luau(code, datamodel_type="Server")
raw_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Raw output:", raw_text)
data = json.loads(raw_text)
print("Decoded type:", type(data))
print("Scatters type:", type(data.get("scatters")))
for idx, sc in enumerate(data.get("scatters", [])):
    print(f"Index {idx}:", sc)
client.close()
