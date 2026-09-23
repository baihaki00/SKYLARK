import os
import sys
import time
import base64
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities")))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

brain_dir = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

# Helper for capture
def capture_and_save(capture_id, filename):
    print(f"Capturing {capture_id}...")
    cap_res = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": capture_id,
        "camera_position": [0, 10, 20],
        "look_at_position": [0, 8, 0]
    })
    filepath = os.path.join(brain_dir, filename)
    if cap_res and not cap_res.get("isError", False):
        content = cap_res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(filepath, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved screenshot to {filepath} ({len(img_data)} bytes)")
                return filepath
    print(f"[FAIL] Could not capture {capture_id}:", cap_res)
    return None

# 1. UI Diagnostic: Speed controls, categories
diag_script = """
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pGui = player and player:WaitForChild("PlayerGui", 5)
if not pGui then return { error = "No PlayerGui" } end

local labUI = pGui:WaitForChild("AnimationLabUI", 5)
local mainFrame = labUI and labUI:FindFirstChild("MainFrame")
if not mainFrame then return { error = "No MainFrame" } end

mainFrame.Visible = true

local titleBar = mainFrame:FindFirstChild("TitleBar")
local speedContainer = titleBar and titleBar:FindFirstChild("SpeedControllerContainer")

local speedItems = {}
if speedContainer then
    local children = speedContainer:GetChildren()
    local guiChildren = {}
    for _, ch in ipairs(children) do
        if ch:IsA("GuiObject") then table.insert(guiChildren, ch) end
    end
    table.sort(guiChildren, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
    for _, ch in ipairs(guiChildren) do
        table.insert(speedItems, { name = ch.Name, text = ch.Text, order = ch.LayoutOrder })
    end
end

local powerhouse = mainFrame:FindFirstChild("PowerhouseView")
local catTabBar = powerhouse and powerhouse:FindFirstChildWhichIsA("ScrollingFrame")

local categoriesFound = {}
if catTabBar then
    for _, b in ipairs(catTabBar:GetChildren()) do
        if b:IsA("TextButton") then table.insert(categoriesFound, b.Text) end
    end
end

return {
    success = true,
    mainFrameSize = string.format("%dx%d", mainFrame.AbsoluteSize.X, mainFrame.AbsoluteSize.Y),
    speedButtons = speedItems,
    categories = categoriesFound
}
"""
res = client.execute_luau(diag_script, datamodel_type="Client")
print("=== 1. UI DIAGNOSTIC ===")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))

# 2. Select Idles Category
idles_script = """
local Players = game:GetService("Players")
local labUI = Players.LocalPlayer.PlayerGui.AnimationLabUI
local mainFrame = labUI.MainFrame
mainFrame:SetAttribute("SelectedCategory", "Idles")
task.wait(0.2)

local listFrame = nil
for _, d in ipairs(mainFrame:GetDescendants()) do
    if d:IsA("ScrollingFrame") and d.Position.Y.Offset > 30 and d.Size.X.Offset <= 260 then
        listFrame = d
        break
    end
end
local items = {}
if listFrame then
    for _, b in ipairs(listFrame:GetChildren()) do
        if b:IsA("TextButton") then table.insert(items, b.Text) end
    end
end
return { selected = "Idles", count = #items, items = items }
"""
idles_res = client.execute_luau(idles_script, datamodel_type="Client")
print("=== 2. IDLES CATEGORY SELECTION ===")
print(idles_res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Capture Powerhouse with Idles
capture_and_save("QuinManager_IdlesCategory", "screen_capture_quin_manager_idles.png")

# 3. Test Search 'idle'
search_script = """
local Players = game:GetService("Players")
local labUI = Players.LocalPlayer.PlayerGui.AnimationLabUI
local mainFrame = labUI.MainFrame
mainFrame:SetAttribute("SearchQuery", "idle")
task.wait(0.2)

local listFrame = nil
for _, d in ipairs(mainFrame:GetDescendants()) do
    if d:IsA("ScrollingFrame") and d.Position.Y.Offset > 30 and d.Size.X.Offset <= 260 then
        listFrame = d
        break
    end
end
local items = {}
if listFrame then
    for _, b in ipairs(listFrame:GetChildren()) do
        if b:IsA("TextButton") then table.insert(items, b.Text) end
    end
end
return { query = "idle", count = #items, items = items }
"""
search_res = client.execute_luau(search_script, datamodel_type="Client")
print("=== 3. SEARCH 'idle' RESULTS ===")
print(search_res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Capture Search results
capture_and_save("QuinManager_SearchIdle", "screen_capture_quin_manager_search_idle.png")

# Reset Search
reset_script = """
local Players = game:GetService("Players")
local labUI = Players.LocalPlayer.PlayerGui.AnimationLabUI
local mainFrame = labUI.MainFrame
mainFrame:SetAttribute("SearchQuery", "")
mainFrame:SetAttribute("SelectedCategory", "All")
return "Reset"
"""
client.execute_luau(reset_script, datamodel_type="Client")
time.sleep(0.2)

# Capture Main Powerhouse
capture_and_save("QuinManager_Powerhouse_Final", "screen_capture_quin_manager_powerhouse.png")

# 4. Switch to TestModes Tab & Verify Cards
tm_script = """
local Players = game:GetService("Players")
local labUI = Players.LocalPlayer.PlayerGui.AnimationLabUI
local mainFrame = labUI.MainFrame
mainFrame:SetAttribute("ActiveTab", "TestModes")
task.wait(0.3)

local testModesView = mainFrame:FindFirstChild("TestModesView")
local tmGrid = testModesView and testModesView:FindFirstChildWhichIsA("ScrollingFrame")

local cards = {}
if tmGrid then
    for _, card in ipairs(tmGrid:GetChildren()) do
        if card:IsA("Frame") then
            local titles = {}
            for _, ch in ipairs(card:GetChildren()) do
                if ch:IsA("TextLabel") and ch.Text ~= "" then
                    table.insert(titles, ch.Text)
                end
            end
            table.insert(cards, { x = card.Position.X.Offset, titles = titles })
        end
    end
    table.sort(cards, function(a, b) return a.x < b.x end)
end
return {
    success = true,
    testModesVisible = (testModesView ~= nil and testModesView.Visible),
    isScrollingFrame = (tmGrid ~= nil),
    cardCount = #cards,
    cards = cards
}
"""
tm_res = client.execute_luau(tm_script, datamodel_type="Client")
print("=== 4. TEST MODES SUITE VERIFICATION ===")
print(tm_res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Capture Test Modes View
capture_and_save("QuinManager_TestModes_Final", "screen_capture_quin_manager_test_modes.png")
