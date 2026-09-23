import json
from Tools.Utilities.roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local HttpService = game:GetService("HttpService")
local pos = Vector3.new(6.1, 7.4, 9.5)
local parts = workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(30, 15, 30))
local info = {}
for _, p in ipairs(parts) do
    table.insert(info, {
        name = p.Name,
        parent = p.Parent and p.Parent.Name or "None",
        class = p.ClassName,
        size = {math.round(p.Size.X*10)/10, math.round(p.Size.Y*10)/10, math.round(p.Size.Z*10)/10},
        pos = {math.round(p.Position.X*10)/10, math.round(p.Position.Y*10)/10, math.round(p.Position.Z*10)/10},
        canCollide = p.CanCollide
    })
end
return HttpService:JSONEncode(info)
"""
res = client.execute_luau(code, datamodel_type="Server")
txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("STALL REGION PARTS:")
print(txt)
client.close()
