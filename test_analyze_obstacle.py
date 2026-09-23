from Tools.Utilities.roblox_client import RobloxStudioClient
import json

c = RobloxStudioClient()
code = r"""
local rs = game:GetService("ReplicatedStorage")
local SpatialModule = require(rs.QuinCore.Modules.SpatialModule)

-- Create a mock rootPart at (-124, 4.5, 15) facing (0, 0, 1) towards OB at (-124, 3, 31)
local part = Instance.new("Part")
part.Size = Vector3.new(2, 2, 1)
part.CFrame = CFrame.new(-124, 4.5, 15)
part.Parent = workspace

local targetPos = Vector3.new(-124, 4.5, 35)

local info = SpatialModule.analyzeObstacleAhead(part, targetPos, 22)
part:Destroy()

local res = {}
for k, v in pairs(info) do
    table.insert(res, k .. "=" .. tostring(v))
end
return "analyzeObstacleAhead result: " .. table.concat(res, ", ")
"""
# Note: Studio has not synced SpatialModule yet, let's sync just SpatialModule or test via raw code
res = c.execute_luau(code, "Edit")
print("Test Result before sync:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
