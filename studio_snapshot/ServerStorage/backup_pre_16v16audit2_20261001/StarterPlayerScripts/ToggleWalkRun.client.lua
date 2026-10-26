---- StarterCharacterScript: Toggle WalkSpeed with Z key

--local Players = game:GetService("Players")
--local UserInputService = game:GetService("UserInputService")

--local player = Players.LocalPlayer
--local character = player.Character or player.CharacterAdded:Wait()
--local humanoid = character:WaitForChild("Humanoid")

---- === SETTINGS ===
--local normalSpeed = 18.5 --13.5
--local boostedSpeed = 60
--local currentBoost = false

---- === INPUT HANDLER ===
--UserInputService.InputBegan:Connect(function(input, processed)
--	if processed then return end
--	if input.KeyCode == Enum.KeyCode.Z then
--		currentBoost = not currentBoost
--		humanoid.WalkSpeed = currentBoost and boostedSpeed or normalSpeed
--	end
--end)
---- === RESET SPEED WHEN CHARACTER SPAWNS ===
--humanoid.WalkSpeed = normalSpeed
