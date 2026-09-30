local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local gui = script.Parent
local alphaContainer = gui.MainFrame.TeamAlpha
local betaContainer = gui.MainFrame.TeamBeta

local function getTeamHealth(teamTag)
	local currentHealth = 0
	local maxHealth = 0
	
	for _, model in ipairs(CollectionService:GetTagged(teamTag)) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			currentHealth = currentHealth + humanoid.Health
			maxHealth = maxHealth + humanoid.MaxHealth
		end
	end
	
	return currentHealth, maxHealth
end

local function updateBar(container, name, currentHealth, maxHealth)
	local fill = container.Fill
	local label = container.Label
	
	local ratio = 1
	if maxHealth > 0 then
		ratio = math.clamp(currentHealth / maxHealth, 0, 1)
	else
		ratio = 0
	end
	label.TextScaled = false
	label.TextSize = 100
	label.Text = string.format("%s: %d / %d", name, math.floor(currentHealth), math.floor(maxHealth))
	
	
	local tween = TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0)
	})
	tween:Play()
end

while true do
	task.wait(0.1)
	
	local alphaHP, alphaMax = getTeamHealth("TeamAlpha")
	local betaHP, betaMax = getTeamHealth("TeamBeta")
	
	updateBar(alphaContainer, "TEAM ALPHA", alphaHP, alphaMax)
	updateBar(betaContainer, "TEAM BETA", betaHP, betaMax)
end
