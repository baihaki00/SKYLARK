--// Cognition.Memory
-- Who a Quin knows about, and how well. Each enemy it has attended to becomes a track: where it
-- was, how it was moving, when. While the enemy stays in attention the track is live. Once it
-- drops out (out of sight, or crowded out of attention) the track ages: confidence decays, the
-- believed position is dead-reckoned for a moment, and the track is forgotten when confidence
-- runs out. Aware Quins hold tracks longer.
-- Allies within shouting distance pass on what they can see ("report"): second-hand, so held
-- with less confidence.
-- A Quin with no enemy contact at all falls back on the one thing the whole team knows - roughly
-- where the nearest enemy is ("rumour") - so a battle never stalls with everybody blind.
-- Neutral (layer off): no persistence; a Quin knows exactly what it attends to this tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Blackboard = require(script.Parent:WaitForChild("Blackboard"))

local Memory = {}

function Memory.retention(quinModel)
	local cfg = CombatConfig.Cognition
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	return cfg.MemoryRetentionMin + awareness * (cfg.MemoryRetentionMax - cfg.MemoryRetentionMin)
end

-- A contact is what the rest of the pipeline consumes: one known Quin, as believed
local function contactFromPercept(percept)
	return {
		model = percept.model,
		isAlly = percept.isAlly,
		distance = percept.distance,
		position = percept.position,
		velocity = percept.velocity,
		healthRatio = percept.healthRatio,
		energyRatio = percept.energyRatio,
		hasLineOfSight = percept.hasLineOfSight == true,
		isAuraFarming = percept.model:GetAttribute("IsAuraFarming") == true,
		channel = percept.channel,
		confidence = 1,
		visible = true,
	}
end

local function contactFromTrack(track, myPos, now, retention, cfg)
	local age = now - track.time
	local confidence = math.exp(-age / retention) * (track.reported and cfg.ReportConfidence or 1)
	local drift = Vector3.new(track.velocity.X, 0, track.velocity.Z) * math.min(age, cfg.MemoryPredictionHorizon)
	local believed = track.position + drift
	return {
		model = track.model,
		isAlly = false,
		distance = (believed - myPos).Magnitude,
		position = believed,
		velocity = track.velocity,
		healthRatio = track.healthRatio,
		energyRatio = track.energyRatio,
		hasLineOfSight = false,
		isAuraFarming = false,
		channel = track.reported and "report" or "memory",
		confidence = confidence,
		visible = false,
		age = age,
	}
end

local function remember(tracks, percept, now, reported)
	tracks[percept.model] = {
		model = percept.model,
		position = percept.position,
		velocity = percept.velocity,
		healthRatio = percept.healthRatio,
		energyRatio = percept.energyRatio,
		time = now,
		visible = not reported,
		reported = reported or nil,
	}
end

-- Take over what allies within shouting distance are looking at right now and this Quin is not
local function takeReports(tracks, percepts, now, range)
	for _, percept in ipairs(percepts) do
		if percept.isAlly and percept.distance <= range then
			local allyBoard = Blackboard.peek(percept.model)
			if allyBoard then
				for model, allyTrack in pairs(allyBoard.tracks) do
					local mine = tracks[model]
					if allyTrack.visible and not (mine and mine.visible) then
						remember(tracks, allyTrack, now, true)
					end
				end
			end
		end
	end
end

-- Returns { allies = { contact }, enemies = { contact } }
function Memory.update(board, quinModel, rootPart, percepts, now, enabled)
	local cfg = CombatConfig.Cognition
	local myPos = rootPart.Position
	local contacts = { allies = {}, enemies = {} }
	local tracks = board.tracks

	local alive = {}
	local nearestEnemyPercept = nil
	for _, percept in ipairs(percepts) do
		alive[percept.model] = true
		if percept.isAlly then
			table.insert(contacts.allies, contactFromPercept(percept))
		elseif not nearestEnemyPercept or percept.distance < nearestEnemyPercept.distance then
			nearestEnemyPercept = percept
		end
	end

	if not enabled then
		table.clear(tracks)
		for _, percept in ipairs(percepts) do
			if not percept.isAlly and percept.channel and percept.attended ~= false then
				table.insert(contacts.enemies, contactFromPercept(percept))
			end
		end
	else
		for _, track in pairs(tracks) do
			track.visible = false
		end
		local live = {}
		for _, percept in ipairs(percepts) do
			if not percept.isAlly and percept.channel and percept.attended ~= false then
				remember(tracks, percept, now)
				live[percept.model] = percept
			end
		end
		if now - (board.lastReportTime or 0) >= cfg.ReportInterval then
			board.lastReportTime = now
			takeReports(tracks, percepts, now, cfg.ReportRange)
		end

		local retention = Memory.retention(quinModel)
		for model, track in pairs(tracks) do
			if not alive[model] then
				tracks[model] = nil
			elseif live[model] then
				table.insert(contacts.enemies, contactFromPercept(live[model]))
			else
				local contact = contactFromTrack(track, myPos, now, retention, cfg)
				if contact.confidence < cfg.MemoryForgetConfidence then
					tracks[model] = nil
				else
					table.insert(contacts.enemies, contact)
				end
			end
		end
	end

	if #contacts.enemies == 0 and nearestEnemyPercept and cfg.RumourFallback then
		local rumour = contactFromPercept(nearestEnemyPercept)
		rumour.channel = "rumour"
		rumour.confidence = cfg.RumourConfidence
		rumour.hasLineOfSight = nearestEnemyPercept.hasLineOfSight == true
		rumour.visible = false
		table.insert(contacts.enemies, rumour)
	end

	return contacts
end

return Memory
