--// QuinInstance.lua
-- Canonical representation of an individual, persistent Quin entity
-- Bridges Type (combat chassis), Element (power identity), Personality (behavioral bias),
-- Ownership (player ownership, trading, selling, retirement), Battle Record, Rivalries, and Titles across time.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local ElementData = require(QuinCore:WaitForChild("ElementData"))
local PersonalitySystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("PersonalitySystem"))

local QuinInstance = {
	QuinInstanceVersion = 2,
}

-- Generate a permanent, unique Quin ID (e.g. "Q_A1B2C3D4")
local function generateQuinId()
	local guid = HttpService:GenerateGUID(false)
	local short = string.gsub(guid, "-", ""):sub(1, 8):upper()
	return "Q_" .. short
end

-- Factory: Create a new QuinInstance
function QuinInstance.create(spec)
	spec = spec or {}

	local qType = spec.Type or "TypeA"
	local qElement = spec.Element or ElementData.getRandomElement()
	local qOwnerId = spec.OwnerId or "SERVER"
	local qQuinClass = spec.QuinClass or "Normal"     -- "Normal" or "Admin"
	local qArchetype = spec.Archetype or "Standard"   -- "Standard" or "Benchmark"

	-- Personality is generated once upon birth and permanently owned
	local personality = spec.Personality
	if not personality then
		personality = PersonalitySystem.generate(qType, spec.PersonalityOverrides)
	else
		local valid, err = PersonalitySystem.validate(personality)
		if not valid then
			warn("[QuinInstance] Provided personality invalid (" .. tostring(err) .. "), regenerating.")
			personality = PersonalitySystem.generate(qType)
		end
	end

	-- Titles structure
	local titles = spec.Titles or { Current = "Rookie", Earned = { "Rookie" } }
	if type(titles) == "table" and not titles.Earned then
		-- Backwards compatibility with plain array
		local rawList = titles
		titles = { Current = rawList[1] or "Rookie", Earned = rawList }
	end

	-- Ownership tracking (accounts for player owning, buying, selling, transferring, retiring)
	local ownership = spec.Ownership or {
		OriginalOwnerId = tostring(qOwnerId),
		PreviousOwners = {},
		Status = "Active", -- "Active", "Retired", "Deceased"
		AcquiredAt = os.time(),
	}

	local instance = {
		QuinId = spec.QuinId or generateQuinId(),
		OwnerId = tostring(qOwnerId),
		Type = qType,
		Element = qElement,
		QuinClass = qQuinClass,
		Archetype = qArchetype,
		Ownership = ownership,

		PersonalityVersion = PersonalitySystem.PersonalityVersion,
		Personality = personality,

		BattleRecord = {
			Battles       = spec.BattleRecord and spec.BattleRecord.Battles or 0,
			Wins          = spec.BattleRecord and spec.BattleRecord.Wins or 0,
			Losses        = spec.BattleRecord and spec.BattleRecord.Losses or 0,
			Draws         = spec.BattleRecord and spec.BattleRecord.Draws or 0,
			CurrentStreak = spec.BattleRecord and spec.BattleRecord.CurrentStreak or 0,
			BestStreak    = spec.BattleRecord and spec.BattleRecord.BestStreak or 0,
			TotalKills    = spec.BattleRecord and spec.BattleRecord.TotalKills or 0,
			TotalDeaths   = spec.BattleRecord and spec.BattleRecord.TotalDeaths or 0,
			DamageDealt   = spec.BattleRecord and spec.BattleRecord.DamageDealt or 0,
		},

		Rivalries = spec.Rivalries or {}, -- [OpponentQuinId] = { Encounters, Wins, Losses, GrudgeScore, LastMet }
		Titles = titles,
		Experience = spec.Experience or nil,

		CreatedAt = spec.CreatedAt or os.time(),
	}

	return instance
end

-- ============================================================
-- OWNERSHIP, SELLING, TRADING, AND RETIREMENT
-- ============================================================

-- Transfer Quin to a new player (Selling, Trading, Gifting)
-- Preserves complete combat history, rivalries, titles, and personality!
function QuinInstance.transferOwnership(instance, newOwnerId, transferReason)
	if not instance then return false, "No instance" end
	newOwnerId = tostring(newOwnerId)
	if instance.OwnerId == newOwnerId then return false, "Already owner" end

	instance.Ownership = instance.Ownership or {
		OriginalOwnerId = instance.OwnerId,
		PreviousOwners = {},
		Status = "Active",
		AcquiredAt = os.time(),
	}

	table.insert(instance.Ownership.PreviousOwners, {
		OwnerId = instance.OwnerId,
		TransferredAt = os.time(),
		Reason = transferReason or "Transfer",
	})

	instance.OwnerId = newOwnerId
	instance.Ownership.AcquiredAt = os.time()
	print(string.format("[QuinInstance] Ownership of %s transferred to %s (Reason: %s)", 
		instance.QuinId, newOwnerId, transferReason or "Transfer"))
	return true
end

-- Retire or release a Quin (Memorial / Graveyard archiving)
function QuinInstance.retire(instance, reason)
	if not instance then return end
	instance.Ownership = instance.Ownership or {}
	instance.Ownership.Status = reason or "Retired"
	instance.Ownership.RetiredAt = os.time()
	print(string.format("[QuinInstance] Quin %s retired. Final Record: %dW-%dL", 
		instance.QuinId, instance.BattleRecord.Wins, instance.BattleRecord.Losses))
end

-- ============================================================
-- BATTLE & RIVALRY RECORDING
-- ============================================================

-- Record battle outcome with optional match telemetry (kills, damage, rival encounters)
function QuinInstance.recordBattle(instance, result, stats)
	if not instance or not instance.BattleRecord then return end
	local br = instance.BattleRecord
	br.Battles = (br.Battles or 0) + 1

	stats = stats or {}
	local kills = stats.kills or 0
	local damage = stats.damage or 0
	br.TotalKills = (br.TotalKills or 0) + kills
	br.DamageDealt = (br.DamageDealt or 0) + damage

	if result == "Win" or result == "win" then
		br.Wins = (br.Wins or 0) + 1
		br.CurrentStreak = (br.CurrentStreak or 0) + 1
		if br.CurrentStreak > (br.BestStreak or 0) then
			br.BestStreak = br.CurrentStreak
		end
	elseif result == "Loss" or result == "loss" then
		br.Losses = (br.Losses or 0) + 1
		br.TotalDeaths = (br.TotalDeaths or 0) + 1
		br.CurrentStreak = 0
	else
		br.Draws = (br.Draws or 0) + 1
		br.CurrentStreak = 0
	end

	-- Check for Title unlocks upon match completion
	QuinInstance.checkAndAwardTitles(instance, stats)
end

-- Record encounter with a specific opponent Quin ID for Rivalry tracking
function QuinInstance.recordRivalry(instance, opponentId, outcome, damageDealt)
	if not instance or not opponentId or opponentId == "" or opponentId == instance.QuinId then return end
	instance.Rivalries = instance.Rivalries or {}

	local riv = instance.Rivalries[opponentId]
	if not riv then
		riv = {
			Encounters = 0,
			Wins = 0,
			Losses = 0,
			GrudgeScore = 0,
			LastMet = os.time(),
		}
		instance.Rivalries[opponentId] = riv
	end

	riv.Encounters = riv.Encounters + 1
	riv.LastMet = os.time()

	if outcome == "Win" or outcome == "win" then
		riv.Wins = riv.Wins + 1
		riv.GrudgeScore = math.max(0, riv.GrudgeScore - 10)
	elseif outcome == "Loss" or outcome == "loss" then
		riv.Losses = riv.Losses + 1
		-- Losing builds grudge
		riv.GrudgeScore = riv.GrudgeScore + 25
	end

	if damageDealt and damageDealt > 50 then
		riv.GrudgeScore = riv.GrudgeScore + math.floor(damageDealt * 0.1)
	end
end

-- Get primary rival (opponent with highest grudge or most encounters)
function QuinInstance.getPrimaryRival(instance)
	if not instance or not instance.Rivalries then return nil end
	local primaryRivalId = nil
	local highestScore = -1

	for oppId, data in pairs(instance.Rivalries) do
		-- Combined weight of grudge and encounters
		local score = (data.GrudgeScore or 0) + (data.Encounters or 0) * 5
		if score > highestScore and score >= 15 then
			highestScore = score
			primaryRivalId = oppId
		end
	end

	return primaryRivalId, instance.Rivalries[primaryRivalId]
end

-- ============================================================
-- TITLES & MILESTONES
-- ============================================================

function QuinInstance.addTitle(instance, titleName)
	if not instance or not titleName then return end
	instance.Titles = instance.Titles or { Current = titleName, Earned = {} }
	instance.Titles.Earned = instance.Titles.Earned or {}

	for _, t in ipairs(instance.Titles.Earned) do
		if t == titleName then return end
	end
	table.insert(instance.Titles.Earned, titleName)
	print(string.format("[QuinInstance] %s unlocked title: '%s'!", instance.QuinId, titleName))
end

function QuinInstance.setEquippedTitle(instance, titleName)
	if not instance or not titleName then return end
	instance.Titles = instance.Titles or { Current = titleName, Earned = { titleName } }
	instance.Titles.Current = titleName
end

-- Evaluate milestone conditions to award competitive titles
function QuinInstance.checkAndAwardTitles(instance, matchStats)
	if not instance or not instance.BattleRecord then return end
	local br = instance.BattleRecord

	-- Streak Titles
	if br.CurrentStreak >= 3 then
		QuinInstance.addTitle(instance, "Duelist")
	end
	if br.CurrentStreak >= 5 then
		QuinInstance.addTitle(instance, "Arena Master")
	end
	if br.CurrentStreak >= 10 then
		QuinInstance.addTitle(instance, "Untouchable")
	end

	-- Total Victory Titles
	if br.Wins >= 5 then
		QuinInstance.addTitle(instance, "Veteran")
	end
	if br.Wins >= 15 then
		QuinInstance.addTitle(instance, "Centurion")
	end

	-- Elemental Mastery Titles (Water as primary, Ice as byproduct)
	if br.Wins >= 8 then
		if instance.Element == "Water" then
			QuinInstance.addTitle(instance, "Glacial Sovereign")
		elseif instance.Element == "Fire" then
			QuinInstance.addTitle(instance, "Pyre Vanguard")
		elseif instance.Element == "Stone" then
			QuinInstance.addTitle(instance, "Seismic Colossus")
		elseif instance.Element == "Lightning" then
			QuinInstance.addTitle(instance, "Volt Phantom")
		elseif instance.Element == "Wind" then
			QuinInstance.addTitle(instance, "Tempest Blade")
		end
	end

	-- Match specific heroism
	if matchStats then
		if matchStats.kills and matchStats.kills >= 3 then
			QuinInstance.addTitle(instance, "Berserker")
		end
		if matchStats.clutchSurvival then
			QuinInstance.addTitle(instance, "Unbroken")
		end
	end
end

-- ============================================================
-- SERIALIZATION & MODEL ATTACHMENT
-- ============================================================

-- Serialize for persistent storage (DataStore / Network)
function QuinInstance.serialize(instance)
	return {
		QuinId = instance.QuinId,
		OwnerId = instance.OwnerId,
		Type = instance.Type,
		Element = instance.Element,
		QuinClass = instance.QuinClass,
		Archetype = instance.Archetype,
		Ownership = instance.Ownership,
		PersonalityVersion = instance.PersonalityVersion,
		Personality = instance.Personality,
		BattleRecord = instance.BattleRecord,
		Rivalries = instance.Rivalries,
		Titles = instance.Titles,
		Experience = instance.Experience,
		CreatedAt = instance.CreatedAt,
	}
end

-- Deserialize and migrate from raw data
function QuinInstance.deserialize(data)
	if type(data) ~= "table" then return nil end
	return QuinInstance.create(data)
end

-- Attach identity attributes to the physical Roblox model
function QuinInstance.attachToModel(instance, model)
	if not model then return end

	model:SetAttribute("QuinId", instance.QuinId)
	model:SetAttribute("OwnerId", instance.OwnerId)
	model:SetAttribute("QuinType", instance.Type)
	model:SetAttribute("Element", instance.Element)
	model:SetAttribute("QuinClass", instance.QuinClass)
	model:SetAttribute("Archetype", instance.Archetype)

	-- Personality attributes for live perception and HUD display
	if instance.Personality then
		for dim, val in pairs(instance.Personality) do
			model:SetAttribute("Pers_" .. dim, val)
		end
		model:SetAttribute("CurrentConfidence", instance.Personality.Confidence or 0.5)
		PersonalitySystem.assignInitialQuirky(model, instance.Type, instance.Personality)
	end

	-- Titles and Battles summaries
	local br = instance.BattleRecord
	model:SetAttribute("BattlesTotal", br and br.Battles or 0)
	model:SetAttribute("BattlesWins", br and br.Wins or 0)
	model:SetAttribute("WinStreak", br and br.CurrentStreak or 0)

	-- Equipped Title
	local titleName = (instance.Titles and instance.Titles.Current) or "Rookie"
	model:SetAttribute("EquippedTitle", titleName)
	model:SetAttribute("TitlesCount", (instance.Titles and instance.Titles.Earned and #instance.Titles.Earned) or 1)

	-- Primary Rival
	local primaryRivalId, rivData = QuinInstance.getPrimaryRival(instance)
	if primaryRivalId then
		model:SetAttribute("PrimaryRivalId", primaryRivalId)
		model:SetAttribute("PrimaryRivalScore", string.format("%dW-%dL", rivData.Wins or 0, rivData.Losses or 0))
	end
end

return QuinInstance
