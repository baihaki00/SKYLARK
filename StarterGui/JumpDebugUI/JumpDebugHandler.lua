local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameCommand = ReplicatedStorage:WaitForChild("GameCommand", 10)

local frame = script.Parent:WaitForChild("Frame")
local velLabel = frame:WaitForChild("VelocityLabel")

for i = 1, 7 do
    local btn = frame:FindFirstChild("Style" .. i)
    if btn then
        btn.MouseButton1Click:Connect(function()
            print("UI: Requesting Jump Style " .. i)
            if GameCommand then GameCommand:FireServer("jump_test", i) end
        end)
    end
end

local visualizerEnabled = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Two then
        visualizerEnabled = not visualizerEnabled
        if GameCommand then GameCommand:FireServer("toggle_visualizer", visualizerEnabled) end
        print("UI: Visualizer toggled: " .. tostring(visualizerEnabled))
    end
end)

-- Live Velocity Tracker
RunService.Heartbeat:Connect(function()
    local success, err = pcall(function()
        local quin = nil
        for _, model in ipairs(Workspace:GetChildren()) do
            if model.Name:find("Quin") and model:FindFirstChild("HumanoidRootPart") then
                quin = model
                break
            end
        end
        
        if quin then
            local hrp = quin:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.AssemblyLinearVelocity
                velLabel.Text = string.format("Y: %.1f | Spd: %.1f", vel.Y, vel.Magnitude)
            else
                velLabel.Text = "HRP Missing"
            end
        else
            velLabel.Text = "No Quin Found"
        end
    end)
    
    if not success then
        velLabel.Text = "ERR: " .. tostring(err):sub(1, 15)
    end
end)
