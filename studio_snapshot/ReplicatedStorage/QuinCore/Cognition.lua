--// Cognition
-- The Quin's perception-to-understanding pipeline, run once per reasoning tick:
--
--   WORLD -> Gaze -> Senses -> Attention -> Memory -> SelfAwareness -> EnvironmentAwareness
--         -> SituationAwareness -> (TargetingModule, DecisionSystem, states)
--
-- Each layer is its own module under this one and returns a plain table; the results are kept
-- on the Quin's Blackboard. Senses, Attention and Memory can be switched off (Cognition.Layers)
-- to see what each contributes; a switched-off layer returns its neutral result.
-- Tuning: CombatConfig.Cognition.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local DebugDraw = require(QuinCore:WaitForChild("Modules"):WaitForChild("DebugDraw"))
local PlatformCatalogue = require(QuinCore:WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))

local Layers = require(script:WaitForChild("Layers"))
local Blackboard = require(script:WaitForChild("Blackboard"))
local Senses = require(script:WaitForChild("Senses"))
local Gaze = require(script:WaitForChild("Gaze"))
local Attention = require(script:WaitForChild("Attention"))
local Memory = require(script:WaitForChild("Memory"))
local SelfAwareness = require(script:WaitForChild("SelfAwareness"))
local EnvironmentAwareness = require(script:WaitForChild("EnvironmentAwareness"))
local SituationAwareness = require(script:WaitForChild("SituationAwareness"))

local Cognition = {
	Layers = Layers,
	Blackboard = Blackboard,
}

local CHANNEL_COLOR = {
	sight = Color3.fromRGB(240, 240, 255),
	hearing = Color3.fromRGB(255, 220, 90),
	touch = Color3.fromRGB(255, 90, 90),
	memory = Color3.fromRGB(255, 160, 40),
	report = Color3.fromRGB(120, 200, 255),
	rumour = Color3.fromRGB(170, 170, 170),
}

local PLATFORM_COLOR = {
	Level = Color3.fromRGB(200, 200, 200),
	Below = Color3.fromRGB(150, 150, 150),
	Step = Color3.fromRGB(140, 255, 160),
	Vault = Color3.fromRGB(90, 230, 255),
	Jump = Color3.fromRGB(255, 225, 60),
	ProjectileJump = Color3.fromRGB(255, 110, 60),
}

-- Every other living Quin this one may deal with (a showdown duelist only deals with duelists;
-- showdown spectators are nobody's business)
local function livingOthers(quinModel)
	local all = CollectionService:GetTagged("Quin")
	if #all == 0 then
		all = (workspace:FindFirstChild("QuinServer") or workspace):GetChildren()
	end
	local myRole = quinModel:GetAttribute("LeaderShowdownRole")
	local others = {}
	for _, other in ipairs(all) do
		if other ~= quinModel and other:IsA("Model") and other.Parent then
			local humanoid = other:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and other:FindFirstChild("HumanoidRootPart") then
				local otherRole = other:GetAttribute("LeaderShowdownRole")
				local excluded = (myRole == "Duelist" and otherRole ~= "Duelist")
					or otherRole == "PerimeterGuard" or otherRole == "Transition"
				if not excluded then
					table.insert(others, other)
				end
			end
		end
	end
	return others
end

-- A summary of what the Quin knows, for the HUD and for measuring what the layers do
local function publish(quinModel, board)
	local seen = 0
	local targetChannel = "none"
	local targetName = board.self.targetName
	for _, contact in ipairs(board.contacts.enemies) do
		if contact.visible then seen += 1 end
		if contact.model.Name == targetName then targetChannel = contact.channel end
	end
	quinModel:SetAttribute("KnownEnemies", #board.contacts.enemies)
	quinModel:SetAttribute("NoticedEnemies", seen)
	quinModel:SetAttribute("AttentionCapacity", board.attention.capacity)
	quinModel:SetAttribute("TargetContact", targetName and targetName ~= "" and (targetChannel == "none" and "unknown" or targetChannel) or "none")
end

local function drawDebug(quinModel, rootPart, board, sensesOn)
	local eye = SpatialModule.getEyePosition(rootPart)

	if DebugDraw.isActive("Vision", quinModel) then
		local cfg = CombatConfig.Cognition
		if sensesOn then
			-- The cone edges, drawn short of the full range so they stay readable
			local reach = math.min(cfg.VisionRange, 60)
			for _, side in ipairs({ -1, 1 }) do
				local edge = (rootPart.CFrame * CFrame.Angles(0, math.rad(cfg.VisionHalfAngle) * side, 0)).LookVector
				DebugDraw.line("Vision", quinModel, eye, eye + Vector3.new(edge.X, 0, edge.Z).Unit * reach, Color3.fromRGB(90, 160, 255))
			end
			-- Where the eyes point (up / level / down)
			if board.gaze then
				local look = rootPart.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z).Unit
				local pitch = math.rad(board.gaze.pitch)
				DebugDraw.line("Vision", quinModel, eye, eye + (flat * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)) * 30, Color3.fromRGB(255, 255, 120))
				DebugDraw.text("Vision", quinModel, eye + Vector3.new(0, 3, 0), string.format("gaze %s %+.0f", board.gaze.mode, board.gaze.pitch), Color3.fromRGB(255, 255, 120))
			end
		end
		for _, percept in ipairs(board.percepts) do
			if not percept.isAlly and percept.channel then
				DebugDraw.line("Vision", quinModel, eye, percept.position, CHANNEL_COLOR[percept.channel])
				DebugDraw.text("Vision", quinModel, percept.position + Vector3.new(0, 6.5, 0), percept.channel, CHANNEL_COLOR[percept.channel])
			end
		end
	end

	if DebugDraw.isActive("Attention", quinModel) then
		local lines = { string.format("attention %d/%d", math.min(board.attention.capacity, #board.attention.ranked), #board.attention.ranked) }
		for index, percept in ipairs(board.attention.ranked) do
			if index <= 6 then
				table.insert(lines, string.format("%s%d %s %.0f %s", percept.attended and "> " or "  ", index, percept.model.Name, percept.salience, table.concat(percept.salienceReasons, ", ")))
			end
			if percept.attended then
				DebugDraw.line("Attention", quinModel, eye, percept.position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 80, 220))
			end
		end
		DebugDraw.text("Attention", quinModel, rootPart.Position + Vector3.new(0, 11.5, 0), table.concat(lines, "\n"), Color3.fromRGB(255, 150, 235))
	end

	if DebugDraw.isActive("Platforms", quinModel) then
		-- Every platform within reach of a run, with how this Quin would get onto it from
		-- where it stands and how far up it is
		local humanoid = quinModel:FindFirstChildOfClass("Humanoid")
		local floorY = rootPart.Position.Y - ((humanoid and humanoid.HipHeight or 4) + rootPart.Size.Y / 2)
		for _, found in ipairs(PlatformCatalogue.near(rootPart.Position, 150)) do
			local access = PlatformCatalogue.accessFrom(found.platform, floorY)
			local color = PLATFORM_COLOR[access]
			DebugDraw.sphere("Platforms", quinModel, found.point, 0.8, color)
			DebugDraw.text("Platforms", quinModel, found.point + Vector3.new(0, 3, 0),
				string.format("%s %+.0f%s", access, found.platform.topY - floorY, found.platform.isFloating and " (floating)" or ""), color)
		end
	end

	if DebugDraw.isActive("Tracks", quinModel) then
		for _, contact in ipairs(board.contacts.enemies) do
			if not contact.visible then
				local color = CHANNEL_COLOR[contact.channel]
				DebugDraw.sphere("Tracks", quinModel, contact.position, 0.6 + contact.confidence, color)
				DebugDraw.line("Tracks", quinModel, rootPart.Position, contact.position, color)
				DebugDraw.text("Tracks", quinModel, contact.position + Vector3.new(0, 3, 0),
					string.format("%s: %s %.0f%%", contact.channel, contact.model.Name, contact.confidence * 100), color)
			end
		end
	end
end

-- Run the pipeline for one Quin. Returns its tactical context (SituationAwareness), or nil
-- when the Quin is not in a state to perceive anything.
function Cognition.update(quinModel, targetModel)
	if not quinModel or not quinModel.Parent then return nil end
	local rootPart = quinModel:FindFirstChild("HumanoidRootPart")
	local humanoid = quinModel:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then return nil end

	local now = os.clock()
	local board = Blackboard.get(quinModel)
	local others = livingOthers(quinModel)
	local sensesOn = Layers.isEnabled("Senses")

	local gaze = Gaze.update(board, quinModel, rootPart, targetModel, now)
	board.percepts = Senses.sense(quinModel, rootPart, others, sensesOn, gaze.pitch)
	board.attention = Attention.rank(quinModel, board.percepts, Layers.isEnabled("Attention"))
	board.contacts = Memory.update(board, quinModel, rootPart, board.percepts, now, Layers.isEnabled("Memory"))
	board.self = SelfAwareness.assess(board, quinModel, rootPart, humanoid, now)

	local nearbyAllies, nearbyEnemies = SituationAwareness.nearby(board.contacts)
	board.environment = EnvironmentAwareness.survey(quinModel, rootPart, nearbyEnemies, nearbyAllies)

	-- The team always knows the score, whatever this Quin can see
	local census = { totalLivingAllies = #board.contacts.allies, totalLivingEnemies = 0 }
	for _, percept in ipairs(board.percepts) do
		if not percept.isAlly then census.totalLivingEnemies += 1 end
	end

	board.situation = SituationAwareness.assess(quinModel, rootPart, board.self, board.contacts,
		nearbyAllies, nearbyEnemies, board.environment, census, targetModel)

	publish(quinModel, board)
	drawDebug(quinModel, rootPart, board, sensesOn)
	return board.situation
end

-- What this Quin believes about one enemy (position, velocity, confidence, channel), or nil
-- when it does not know about it
function Cognition.contactFor(quinModel, enemyModel)
	local board = Blackboard.peek(quinModel)
	if not board then return nil end
	for _, contact in ipairs(board.contacts.enemies) do
		if contact.model == enemyModel then return contact end
	end
	return nil
end

-- The enemies this Quin currently knows about (contacts), or nil before its first update
function Cognition.knownEnemies(quinModel)
	local board = Blackboard.peek(quinModel)
	return board and board.contacts.enemies or nil
end

return Cognition
