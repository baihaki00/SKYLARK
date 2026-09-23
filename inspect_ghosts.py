from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local ws = game:GetService("Workspace")
local qg = ws:FindFirstChild("QuinGhost")
if not qg then return "No QuinGhost folder" end

local ghosts = qg:GetChildren()
local visibleRings = 0
local outlineFreeHl = 0

for _, g in ipairs(ghosts) do
    local r = g:FindFirstChild("TeamRing")
    if r and r.Transparency < 0.5 then
        visibleRings = visibleRings + 1
    end
    local hl = g:FindFirstChild("ElementHighlight")
    if hl and hl.OutlineTransparency >= 0.99 then
        outlineFreeHl = outlineFreeHl + 1
    end
end

return string.format("Total Visual Ghosts: %d\nVisible TeamRings on Ghosts: %d/%d\nOutline-Free Highlights on Ghosts: %d/%d",
    #ghosts, visibleRings, #ghosts, outlineFreeHl, #ghosts)
"""
res = c.execute_luau(code, "Client")
print("Client Ghost Inspection:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
