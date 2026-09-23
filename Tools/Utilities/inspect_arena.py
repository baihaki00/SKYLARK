import sys
import json
import os
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local arena = workspace:FindFirstChild("MovementTestArena")
if not arena then return "NO MovementTestArena" end

local info = {}
local ck = arena:FindFirstChild("Checkpoint")
if ck then
    table.insert(info, "CHECKPOINTS:")
    for _, c in ipairs(ck:GetChildren()) do
        if c:IsA("BasePart") then
            table.insert(info, string.format("  %s pos=%s size=%s", c.Name, tostring(c.Position), tostring(c.Size)))
        else
            table.insert(info, string.format("  %s [%s]", c.Name, c.ClassName))
        end
    end
end

local obs = arena:FindFirstChild("Obstacles")
if obs then
    table.insert(info, "OBSTACLES:")
    for _, o in ipairs(obs:GetChildren()) do
        if o:IsA("BasePart") then
            table.insert(info, string.format("  %s pos=%s size=%s", o.Name, tostring(o.Position), tostring(o.Size)))
        else
            table.insert(info, string.format("  %s [%s]", o.Name, o.ClassName))
        end
    end
end

return table.concat(info, "\\n")
"""

res = client.execute_luau(code, datamodel_type="Edit")
raw_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
print(raw_text)
client.close()
