local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Create GUI
local sg = Instance.new("ScreenGui")
sg.Name = "MasterDebugUI"
sg.ResetOnSpawn = false
sg.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(1, -40, 0, 200)
panel.Position = UDim2.new(0, 20, 1, -220)
panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
panel.BackgroundTransparency = 0.3
panel.Visible = false -- Hidden by default
panel.Parent = sg

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.Text = "Master AI Debug Panel (Press G to toggle)"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = panel

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -30)
scrollFrame.Position = UDim2.new(0, 10, 0, 25)
scrollFrame.BackgroundTransparency = 1
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
scrollFrame.ScrollBarThickness = 8
scrollFrame.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.SortOrder = Enum.SortOrder.Name
listLayout.Padding = UDim.new(0, 10)
listLayout.Parent = scrollFrame

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.G then
		panel.Visible = not panel.Visible
	end
end)

local cards = {}

local function createCard(quin)
	local card = Instance.new("Frame")
	card.Name = quin.Name
	card.Size = UDim2.new(0, 220, 1, -10)
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	card.BackgroundTransparency = 0.2
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card
	
	local uiList = Instance.new("UIListLayout")
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 2)
	uiList.Parent = card
	
	local uiPad = Instance.new("UIPadding")
	uiPad.PaddingLeft = UDim.new(0, 5)
	uiPad.PaddingRight = UDim.new(0, 5)
	uiPad.PaddingTop = UDim.new(0, 5)
	uiPad.Parent = card
	
	-- Helper to create lines
	local function makeLine(name, order)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.Size = UDim2.new(1, 0, 0, 14)
		t.BackgroundTransparency = 1
		t.TextColor3 = Color3.new(0.9, 0.9, 0.9)
		t.Font = Enum.Font.Code
		t.TextSize = 11
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.LayoutOrder = order
		t.Parent = card
		return t
	end
	
	makeLine("Header", 1).Font = Enum.Font.GothamBold
	makeLine("Header", 1).TextColor3 = Color3.new(1, 0.8, 0.2)
	makeLine("Health", 2)
	makeLine("State", 3).TextColor3 = Color3.new(0.3, 1, 0.3)
	makeLine("Substate", 4)
	makeLine("Target", 5).TextColor3 = Color3.new(1, 0.4, 0.4)
	makeLine("Physics", 6)
	makeLine("Combat", 7)
	
	card.Parent = scrollFrame
	cards[quin] = card
	return card
end

RunService.Heartbeat:Connect(function()
	if not panel.Visible then return end
	
	-- Clean up dead cards
	for quin, card in pairs(cards) do
		if not quin.Parent or not quin:IsDescendantOf(workspace) then
			card:Destroy()
			cards[quin] = nil
		end
	end
	
	-- Update cards
	local quins = CollectionService:GetTagged("Quin")
	for _, quin in ipairs(quins) do
		if string.find(quin.Name, "_Visual") then continue end

		local card = cards[quin]
		if not card then card = createCard(quin) end
		
		local hum = quin:FindFirstChildOfClass("Humanoid")
		local hrp = quin:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then continue end
		
		-- Gather Data
		local team = quin:GetAttribute("Team") or "NoTeam"
		local qType = quin:GetAttribute("QuinType") or "Unknown"
		card.Header.Text = string.format("%s [%s] (%s)", quin.Name, team, qType)
		
		local hp = hum.Health
		local maxHp = hum.MaxHealth
		local nrg = quin:GetAttribute("Energy") or 0
		card.Health.Text = string.format("HP: %.0f/%.0f | NRG: %.0f", hp, maxHp, nrg)
		
		local state = quin:GetAttribute("CurrentState") or "None"
		card.State.Text = "STATE: " .. state
		
		-- Substates
		local sub = "Idle"
		if state == "Anticipate" then
			sub = "Reaction: " .. tostring(quin:GetAttribute("AnticipatedReaction"))
		elseif state == "ProjectileJump" then
			sub = "Jump Style: " .. tostring(quin:GetAttribute("JumpStyle"))
		elseif state == "Fight" then
			sub = "Combo Step: " .. tostring(quin:GetAttribute("ComboStep") or 0)
		elseif state == "Knockback" then
			sub = "Type: " .. tostring(quin:GetAttribute("KnockbackType") or "Ground")
		end
		card.Substate.Text = "> " .. sub
		
		-- Target Info (Find nearest enemy for ruler)
		local targetDist = "None"
		local targetName = "None"
		
		-- If they have an explicit target value
		local tVal = quin:FindFirstChild("ProjectileTarget")
		if tVal and tVal.Value and tVal.Value.Parent then
			local tHrp = tVal.Value:FindFirstChild("HumanoidRootPart")
			if tHrp then
				targetDist = string.format("%.1f studs", (tHrp.Position - hrp.Position).Magnitude)
				targetName = tVal.Value.Name
			end
		else
			-- Nearest enemy
			local nearest = nil
			local minDist = math.huge
			for _, q2 in ipairs(quins) do
				if q2 ~= quin and q2:GetAttribute("Team") ~= team and q2.Parent then
					local hrp2 = q2:FindFirstChild("HumanoidRootPart")
					if hrp2 then
						local d = (hrp2.Position - hrp.Position).Magnitude
						if d < minDist then
							minDist = d
							nearest = q2
						end
					end
				end
			end
			if nearest then
				targetDist = string.format("%.1f studs", minDist)
				targetName = nearest.Name
			end
		end
		
		card.Target.Text = string.format("TGT: %s (%s)", targetName, targetDist)
		
		-- Physics
		local vel = hrp.AssemblyLinearVelocity
		local pos = hrp.Position
		card.Physics.Text = string.format("Spd: %.1f | Y: %.1f", vel.Magnitude, pos.Y)
		
		-- Combat Log
		card.Combat.Text = string.format("Hits: %d | Blocks: %d", quin:GetAttribute("TotalHits") or 0, quin:GetAttribute("TotalBlocks") or 0)
	end
end)
