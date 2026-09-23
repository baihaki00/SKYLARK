--local Players = game:GetService("Players")
--local ReplicatedStorage = game:GetService("ReplicatedStorage")
--local GameCommand = ReplicatedStorage:WaitForChild("GameCommand")

--local player = Players.LocalPlayer
--local gui = Instance.new("ScreenGui")
--gui.Name = "DeterministicGui"
--gui.ResetOnSpawn = false
--gui.Parent = player:WaitForChild("PlayerGui")

--local frame = Instance.new("Frame")
--frame.Size = UDim2.new(0, 300, 0, 350)
--frame.Position = UDim2.new(1, -320, 0, 10)
--frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
--frame.BackgroundTransparency = 0.1
--frame.Parent = gui

--local corner = Instance.new("UICorner")
--corner.CornerRadius = UDim.new(0, 8)
--corner.Parent = frame

--local listLayout = Instance.new("UIListLayout")
--listLayout.Padding = UDim.new(0, 8)
--listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
--listLayout.SortOrder = Enum.SortOrder.LayoutOrder
--listLayout.Parent = frame

--local padding = Instance.new("UIPadding")
--padding.PaddingTop = UDim.new(0, 10)
--padding.Parent = frame

--local title = Instance.new("TextLabel")
--title.Size = UDim2.new(1, -20, 0, 30)
--title.BackgroundTransparency = 1
--title.Text = "Deterministic Tester"
--title.TextColor3 = Color3.new(1, 1, 1)
--title.Font = Enum.Font.GothamBold
--title.TextSize = 18
--title.Parent = frame

---- State
--local state = {
--	LeaderAction = 1,
--	InterceptType = 1,
--	Outcome = 1,
--	Winner = 1
--}

--local data = {
--	LeaderAction = { "Jump & Dash", "Dash" },
--	InterceptType = { "Wait_Intercept_Ground", "Intercept_MidAir" },
--	OutcomeGround = { "Brawl", "Evade", "Block", "Counter Slam Down", "Instant Slam Down" },
--	OutcomeMidAir = { "Brawl", "Instant Slam Down", "Bounce Off Each Other" },
--	Winner = { "Leader", "Follower" }
--}

--local buttons = {}

--local function createCycleButton(name, labelText)
--	local btnFrame = Instance.new("Frame")
--	btnFrame.Size = UDim2.new(1, -20, 0, 50)
--	btnFrame.BackgroundTransparency = 1
--	btnFrame.Parent = frame
	
--	local lbl = Instance.new("TextLabel")
--	lbl.Size = UDim2.new(1, 0, 0, 20)
--	lbl.BackgroundTransparency = 1
--	lbl.Text = labelText
--	lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
--	lbl.Font = Enum.Font.Gotham
--	lbl.TextSize = 12
--	lbl.Parent = btnFrame
	
--	local btn = Instance.new("TextButton")
--	btn.Size = UDim2.new(1, 0, 0, 30)
--	btn.Position = UDim2.new(0, 0, 0, 20)
--	btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
--	btn.TextColor3 = Color3.new(1, 1, 1)
--	btn.Font = Enum.Font.GothamSemibold
--	btn.TextSize = 14
--	btn.Parent = btnFrame
	
--	local cornerBtn = Instance.new("UICorner")
--	cornerBtn.CornerRadius = UDim.new(0, 4)
--	cornerBtn.Parent = btn
	
--	buttons[name] = btn
--	return btn
--end

--local btnLeader = createCycleButton("LeaderAction", "Quin A (Leader) Action")
--local btnIntercept = createCycleButton("InterceptType", "Quin B (Follower) Interception")
--local btnOutcome = createCycleButton("Outcome", "Event Outcome")
--local btnWinner = createCycleButton("Winner", "Winner")

--local function updateUI()
--	btnLeader.Text = data.LeaderAction[state.LeaderAction]
--	btnIntercept.Text = data.InterceptType[state.InterceptType]
	
--	local outcomeList = (state.InterceptType == 1) and data.OutcomeGround or data.OutcomeMidAir
--	if state.Outcome > #outcomeList then state.Outcome = 1 end
--	btnOutcome.Text = outcomeList[state.Outcome]
	
--	btnWinner.Text = data.Winner[state.Winner]
--end

--btnLeader.MouseButton1Click:Connect(function()
--	state.LeaderAction = (state.LeaderAction % #data.LeaderAction) + 1
--	updateUI()
--end)

--btnIntercept.MouseButton1Click:Connect(function()
--	state.InterceptType = (state.InterceptType % #data.InterceptType) + 1
--	state.Outcome = 1 -- Reset outcome since list changes
--	updateUI()
--end)

--btnOutcome.MouseButton1Click:Connect(function()
--	local outcomeList = (state.InterceptType == 1) and data.OutcomeGround or data.OutcomeMidAir
--	state.Outcome = (state.Outcome % #outcomeList) + 1
--	updateUI()
--end)

--btnWinner.MouseButton1Click:Connect(function()
--	state.Winner = (state.Winner % #data.Winner) + 1
--	updateUI()
--end)

--local startBtn = Instance.new("TextButton")
--startBtn.Size = UDim2.new(1, -20, 0, 40)
--startBtn.BackgroundColor3 = Color3.fromRGB(40, 150, 40)
--startBtn.TextColor3 = Color3.new(1, 1, 1)
--startBtn.Font = Enum.Font.GothamBold
--startBtn.TextSize = 16
--startBtn.Text = "START SCENARIO"
--startBtn.Parent = frame

--local startCorner = Instance.new("UICorner")
--startCorner.CornerRadius = UDim.new(0, 6)
--startCorner.Parent = startBtn

--startBtn.MouseButton1Click:Connect(function()
--	local outcomeList = (state.InterceptType == 1) and data.OutcomeGround or data.OutcomeMidAir
	
--	local config = {
--		LeaderAction = data.LeaderAction[state.LeaderAction],
--		InterceptType = data.InterceptType[state.InterceptType],
--		Outcome = outcomeList[state.Outcome],
--		Winner = data.Winner[state.Winner]
--	}
	
--	GameCommand:FireServer("deterministic_scenario", config)
--end)

--updateUI()
