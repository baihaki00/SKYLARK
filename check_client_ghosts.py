from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local ws = game:GetService("Workspace")
local qg = ws:FindFirstChild("QuinGhost")
if not qg then return "No QuinGhost on Client" end

local ghosts = qg:GetChildren()
local hlCount = 0
local elements = {}

for _, g in ipairs(ghosts) do
    local hl = g:FindFirstChild("ElementHighlight")
    if hl and hl:IsA("Highlight") then
        hlCount = hlCount + 1
    end
end

return string.format("Client Ghosts: %d, Ghosts with ElementHighlight: %d", #ghosts, hlCount)
"""
res = c.execute_luau(code, "Client")
print("Client Check:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
