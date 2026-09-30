--// QuinDataStoreService.lua
-- Server-Authoritative Persistent Storage Service for Quins
-- Manages Player Rosters, Ownership Transfers (Buying/Selling/Trading), Retirement,
-- Lifetime Battle History, Rivalries, and Titles via DataStoreService with seamless in-memory fallback.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))

local QuinDataStoreService = {
	DATA_STORE_NAME = "Skylark_QuinRoster_v2",
	MAX_SLOTS = 4,
	DEFAULT_SLOTS = 2,
}

-- In-memory cache of player rosters on the server: [UserId] = rosterTable
local sessionCache = {}
local dirtyRosters = {} -- [UserId] = true

-- Safely get DataStore with pcall (in Studio, API access might be disabled)
local quinDataStore = nil
local dataStoreAvailable = false

local success, ds = pcall(function()
	return DataStoreService:GetDataStore(QuinDataStoreService.DATA_STORE_NAME)
end)
if success and ds then
	quinDataStore = ds
	dataStoreAvailable = true
	print("[QuinDataStoreService] DataStoreService connected: " .. QuinDataStoreService.DATA_STORE_NAME)
else
	warn("[QuinDataStoreService] DataStoreService unavailable (Studio Offline/API Access Disabled). Utilizing in-memory session persistence.")
end

-- Generate a starter roster for a new player
local function createDefaultRoster(userId)
	userId = tostring(userId)
	local roster = {
		OwnerId = userId,
		UnlockedSlots = QuinDataStoreService.DEFAULT_SLOTS,
		Slots = {},
		Graveyard = {}, -- Retired/memorialized Quins
		LastSaved = os.time(),
	}

	-- Starter 1: Balanced Striker (Fire)
	local starter1 = QuinInstance.create({
		OwnerId = userId,
		Type = "TypeA",
		Element = "Fire",
	})
	starter1.Titles = { Current = "Rookie", Earned = { "Rookie" } }

	-- Starter 2: Swift Water Assassin with Frostbite Byproduct
	local starter2 = QuinInstance.create({
		OwnerId = userId,
		Type = "TypeC",
		Element = "Water",
	})
	starter2.Titles = { Current = "Apprentice", Earned = { "Apprentice" } }

	roster.Slots[1] = starter1
	roster.Slots[2] = starter2
	roster.Slots[3] = nil
	roster.Slots[4] = nil

	return roster
end

-- ============================================================
-- LOAD & SAVE PIPELINE
-- ============================================================

-- Load player roster from DataStore (or memory cache)
function QuinDataStoreService.loadRoster(userId)
	userId = tostring(userId)
	if sessionCache[userId] then
		return sessionCache[userId]
	end

	local rawData = nil
	if dataStoreAvailable and quinDataStore then
		local ok, result = pcall(function()
			return quinDataStore:GetAsync("Roster_" .. userId)
		end)
		if ok and result then
			rawData = result
			print(string.format("[QuinDataStoreService] Loaded roster from DataStore for %s", userId))
		elseif not ok then
			warn(string.format("[QuinDataStoreService] Failed to load DataStore for %s: %s", userId, tostring(result)))
		end
	end

	local roster = nil
	if rawData and type(rawData) == "table" then
		roster = {
			OwnerId = userId,
			UnlockedSlots = rawData.UnlockedSlots or QuinDataStoreService.DEFAULT_SLOTS,
			Slots = {},
			Graveyard = {},
			LastSaved = rawData.LastSaved or os.time(),
		}

		if rawData.Slots then
			for slotIdx, sData in pairs(rawData.Slots) do
				local idx = tonumber(slotIdx)
				if idx and sData then
					roster.Slots[idx] = QuinInstance.deserialize(sData)
				end
			end
		end

		if rawData.Graveyard then
			for _, gData in ipairs(rawData.Graveyard) do
				table.insert(roster.Graveyard, QuinInstance.deserialize(gData))
			end
		end
	else
		-- Provision new starter roster
		roster = createDefaultRoster(userId)
		dirtyRosters[userId] = true
	end

	sessionCache[userId] = roster
	return roster
end

-- Save player roster to DataStore
function QuinDataStoreService.saveRoster(userId, force)
	userId = tostring(userId)
	local roster = sessionCache[userId]
	if not roster then return false, "No roster in cache" end
	if not force and not dirtyRosters[userId] then return true, "Not dirty" end

	roster.LastSaved = os.time()

	-- Serialize active slots
	local serializedSlots = {}
	for idx = 1, QuinDataStoreService.MAX_SLOTS do
		local q = roster.Slots[idx]
		if q then
			serializedSlots[tostring(idx)] = QuinInstance.serialize(q)
		end
	end

	-- Serialize graveyard
	local serializedGraveyard = {}
	if roster.Graveyard then
		for _, q in ipairs(roster.Graveyard) do
			table.insert(serializedGraveyard, QuinInstance.serialize(q))
		end
	end

	local payload = {
		OwnerId = userId,
		UnlockedSlots = roster.UnlockedSlots,
		Slots = serializedSlots,
		Graveyard = serializedGraveyard,
		LastSaved = roster.LastSaved,
	}

	if dataStoreAvailable and quinDataStore then
		local ok, err = pcall(function()
			quinDataStore:SetAsync("Roster_" .. userId, payload)
		end)
		if ok then
			dirtyRosters[userId] = nil
			print(string.format("[QuinDataStoreService] Saved roster for %s to DataStore", userId))
			return true
		else
			warn(string.format("[QuinDataStoreService] Failed to save roster for %s: %s", userId, tostring(err)))
			return false, err
		end
	else
		-- In-memory only mode
		dirtyRosters[userId] = nil
		return true, "Saved to memory cache"
	end
end

-- ============================================================
-- OWNERSHIP TRANSFERS & LIFECYCLE (Selling, Trading, Retiring)
-- ============================================================

-- Transfer a Quin from seller to buyer (Sold / Traded)
-- Preserves full combat record, rivalries, titles, and Quirkies!
function QuinDataStoreService.transferQuin(quinId, sellerUserId, buyerUserId, transferReason)
	sellerUserId = tostring(sellerUserId)
	buyerUserId = tostring(buyerUserId)

	local sellerRoster = QuinDataStoreService.loadRoster(sellerUserId)
	local buyerRoster = QuinDataStoreService.loadRoster(buyerUserId)

	-- Find slot in seller roster
	local foundSlot = nil
	local quin = nil
	for idx = 1, QuinDataStoreService.MAX_SLOTS do
		local q = sellerRoster.Slots[idx]
		if q and q.QuinId == quinId then
			foundSlot = idx
			quin = q
			break
		end
	end

	if not quin then
		return false, "Quin not found in seller roster"
	end

	-- Find empty slot in buyer roster
	local buyerSlot = nil
	for idx = 1, buyerRoster.UnlockedSlots do
		if not buyerRoster.Slots[idx] then
			buyerSlot = idx
			break
		end
	end

	if not buyerSlot then
		return false, "Buyer roster is full"
	end

	-- Transfer ownership metadata
	QuinInstance.transferOwnership(quin, buyerUserId, transferReason or "Sold")

	-- Move between rosters
	sellerRoster.Slots[foundSlot] = nil
	buyerRoster.Slots[buyerSlot] = quin

	dirtyRosters[sellerUserId] = true
	dirtyRosters[buyerUserId] = true

	print(string.format("[QuinDataStoreService] Quin %s successfully transferred from %s to %s!", 
		quinId, sellerUserId, buyerUserId))
	return true
end

-- Retire or release a Quin from an active slot into the Memorial / Graveyard
function QuinDataStoreService.retireQuin(userId, slotIndex, reason)
	userId = tostring(userId)
	local roster = QuinDataStoreService.loadRoster(userId)
	local quin = roster.Slots[slotIndex]
	if not quin then return false, "No Quin in slot" end

	QuinInstance.retire(quin, reason or "Retired")
	roster.Graveyard = roster.Graveyard or {}
	table.insert(roster.Graveyard, quin)
	roster.Slots[slotIndex] = nil

	dirtyRosters[userId] = true
	return true
end

-- Dissolve / Sacrifice a Quin for Elemental Cores and Shards (Authoritative Player Destruction)
function QuinDataStoreService.dissolveQuin(userId, slotIndex)
	userId = tostring(userId)
	local roster = QuinDataStoreService.loadRoster(userId)
	local quin = roster.Slots[slotIndex]
	if not quin then return false, "No Quin in slot" end

	local element = quin.Element or "Water"
	local wins = (quin.BattleRecord and quin.BattleRecord.Wins) or 0
	local titlesCount = (quin.Titles and quin.Titles.Earned and #quin.Titles.Earned) or 1

	-- Yield scaling based on Quin combat heritage
	local shardCount = 10 + math.floor(wins * 2.5) + (titlesCount * 5)
	local coreCount = (wins >= 5 or titlesCount >= 2) and math.max(1, math.floor(wins / 5)) or 0

	local yieldData = {
		QuinId = quin.QuinId,
		Element = element,
		Shards = shardCount,
		Cores = coreCount,
		ShardName = element .. "Shard",
		CoreName = element .. "Core",
		DissolvedAt = os.time(),
	}

	-- Mark status as dissolved and archive
	quin.Ownership = quin.Ownership or {}
	quin.Ownership.Status = "Dissolved"
	quin.Ownership.DissolvedAt = os.time()
	quin.Ownership.DissolutionYield = yieldData

	roster.Graveyard = roster.Graveyard or {}
	table.insert(roster.Graveyard, quin)
	roster.Slots[slotIndex] = nil

	dirtyRosters[userId] = true
	print(string.format("[QuinDataStoreService] Quin %s dissolved by %s! Harvested %d %s, %d %s",
		quin.QuinId, userId, shardCount, yieldData.ShardName, coreCount, yieldData.CoreName))

	return true, yieldData
end

-- Find any Quin across active cached rosters
function QuinDataStoreService.findQuinById(quinId)
	for userId, roster in pairs(sessionCache) do
		for slotIdx = 1, QuinDataStoreService.MAX_SLOTS do
			local q = roster.Slots[slotIdx]
			if q and q.QuinId == quinId then
				return q, userId, slotIdx
			end
		end
	end
	return nil
end

-- Record battle match outcome on a Quin (updates BattleRecord, Rivalries, Titles, and marks dirty)
function QuinDataStoreService.recordMatchOutcome(quinId, outcome, matchStats, rivalQuinId)
	local quin, userId = QuinDataStoreService.findQuinById(quinId)
	if not quin then return false end

	QuinInstance.recordBattle(quin, outcome, matchStats)

	if rivalQuinId and rivalQuinId ~= "" then
		local damage = matchStats and matchStats.damage or 0
		QuinInstance.recordRivalry(quin, rivalQuinId, outcome, damage)
	end

	if userId then
		dirtyRosters[userId] = true
	end

	return true
end

-- ============================================================
-- LIFECYCLE HOOKS
-- ============================================================

Players.PlayerAdded:Connect(function(player)
	QuinDataStoreService.loadRoster(player.UserId)
end)

Players.PlayerRemoving:Connect(function(player)
	QuinDataStoreService.saveRoster(player.UserId, true)
	sessionCache[tostring(player.UserId)] = nil
end)

-- Auto-save dirty rosters every 5 minutes
task.spawn(function()
	while true do
		task.wait(300)
		for userId in pairs(dirtyRosters) do
			QuinDataStoreService.saveRoster(userId)
		end
	end
end)

-- Bind to close to ensure all active rosters flush before server shutdown
game:BindToClose(function()
	print("[QuinDataStoreService] Server closing. Flushing all active rosters...")
	for userId in pairs(sessionCache) do
		QuinDataStoreService.saveRoster(userId, true)
	end
end)

_G.QuinDataStoreService = QuinDataStoreService
shared.QuinDataStoreService = QuinDataStoreService

return QuinDataStoreService
