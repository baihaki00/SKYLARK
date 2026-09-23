import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local pg = lp:FindFirstChild("PlayerGui")
local anim_ui = pg:FindFirstChild("AnimationLabUI")
if not anim_ui then return "No AnimationLabUI" end

-- Let's find the category buttons
local catButtons = {}
local strafeCatBtn = nil
for _, desc in ipairs(anim_ui:GetDescendants()) do
    if desc:IsA("TextButton") and desc.Text == "Strafe" then
        strafeCatBtn = desc
    end
end

if not strafeCatBtn then return "No Strafe category button" end

-- Let's inspect listFrame children right now
local listFrame = nil
for _, desc in ipairs(anim_ui:GetDescendants()) do
    if desc:IsA("ScrollingFrame") and desc.Parent.Name == "Frame" and desc.Parent:FindFirstChild("TextLabel") then
        -- listFrame or comboScroll
        if desc.Size.X.Offset == 240 then
            listFrame = desc
        end
    end
end

-- Let's click the Strafe category button by firing its event if possible or checking how populateList is called
-- Note: In Roblox Lua, buttons have MouseButton1Click, but scripts can't simulate .Click() on RBXScriptSignal without VirtualInputManager or calling the connection if exposed.
-- Wait, let's see what buttons currently exist in listFrame:
local items = {}
if listFrame then
    for _, b in ipairs(listFrame:GetChildren()) do
        if b:IsA("TextButton") then
            table.insert(items, b.Text)
        end
    end
end

return {
    strafeCatBtn = strafeCatBtn:GetFullName(),
    listFrameFound = listFrame ~= nil,
    itemsInList = items
}
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res)
