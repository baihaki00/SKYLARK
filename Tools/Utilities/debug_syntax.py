import sys
import os
sys.path.append(os.path.abspath("Tools/Utilities"))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
test_code = """
local RS = game:GetService("ReplicatedStorage")
local QuinCore = RS:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")

local out = {}

local lss = Modules:FindFirstChild("LeaderShowdownSystem")
if lss then
    local fn, err = loadstring(lss.Source)
    table.insert(out, "LSS syntax: " .. (fn and "OK" or tostring(err)))
    if fn then
        local ok, rerr = pcall(fn)
        table.insert(out, "LSS runtime: " .. (ok and "OK" or tostring(rerr)))
    end
end

local ds = Modules:FindFirstChild("DecisionSystem")
if ds then
    local fn, err = loadstring(ds.Source)
    table.insert(out, "DS syntax: " .. (fn and "OK" or tostring(err)))
    if fn then
        local ok, rerr = pcall(fn)
        table.insert(out, "DS runtime: " .. (ok and "OK" or tostring(rerr)))
    end
end

return table.concat(out, "\\n")
"""

res = client.execute_luau(test_code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
