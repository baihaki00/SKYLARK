local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local camera = workspace.CurrentCamera
local localPlayer = Players.LocalPlayer

local shakeEvent = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Events"):WaitForChild("CameraShakeEvent")

local currentShake = 0

shakeEvent.OnClientEvent:Connect(function(position, radius, intensity)
    local char = localPlayer.Character
    if not char or not char.PrimaryPart then return end
    
    local dist = (char.PrimaryPart.Position - position).Magnitude
    if dist <= radius then
        -- Linear falloff based on distance
        local falloff = 1 - (dist / radius)
        local appliedIntensity = intensity * falloff
        
        currentShake = math.max(currentShake, appliedIntensity)
    end
end)

-- Bind to RenderStep AFTER camera update so we don't permanently offset it
RunService:BindToRenderStep("ClientVfxShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if currentShake > 0.1 then
        -- Random rotational spikes instead of a smooth math.noise wave
        local rx = (math.random() * 2 - 1) * currentShake
        local ry = (math.random() * 2 - 1) * currentShake
        local rz = (math.random() * 2 - 1) * currentShake
        
        -- Multiply on top of the already-calculated camera CFrame
        camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
        
        -- Decay rapidly for a crisp, punchy hit
        currentShake = currentShake * 0.2
    else
        currentShake = 0
    end
end)
