import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities")))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local q = game:GetService("CollectionService"):GetTagged("Quin")
local dashed = 0
local pjed = 0
for _, v in ipairs(q) do
    if (v:GetAttribute("LastDashTime") or 0) > 0 then
        dashed = dashed + 1
    end
    if (v:GetAttribute("LastProjectileJumpTime") or 0) > 0 then
        pjed = pjed + 1
    end
end
return string.format("Total: %d | Quins dashed: %d | Quins PJ'd: %d", #q, dashed, pjed)
"""
res = client.execute_luau(code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
