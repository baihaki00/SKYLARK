-- Hidden by default as requested. Toggle with 'J' if needed for manual debugging.
local ui = script.Parent
local frame = ui:FindFirstChild("Frame")
ui.Enabled = false
if frame then frame.Visible = false end

local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gp)
    if gp or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.J then
        ui.Enabled = not ui.Enabled
        if frame then frame.Visible = ui.Enabled end
    end
end)
