--// QuinRosterService.lua
-- Server-authoritative player roster and Quin ownership service
-- Manages persistent Quin slots, ownership transfers (buying/selling/trading), and DataStore persistence

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))
local QuinDataStoreService = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinDataStoreService"))

local QuinRosterService = {
	MAX_SLOTS = 4,
	DEFAULT_UNLOCKED_SLOTS = 2,
}

-- Get roster for player (loaded from DataStoreService)
function QuinRosterService.getRoster(player)
	local userId = tostring(player.UserId)
	return QuinDataStoreService.loadRoster(userId)
end

-- Save player roster
function QuinRosterService.saveRoster(player, force)
	local userId = tostring(player.UserId)
	return QuinDataStoreService.saveRoster(userId, force)
end

-- Get Quin in specific slot
function QuinRosterService.getQuinInSlot(player, slotIndex)
	local roster = QuinRosterService.getRoster(player)
	if slotIndex < 1 or slotIndex > roster.UnlockedSlots then
		return nil, "Slot locked or invalid"
	end
	return roster.Slots[slotIndex]
end

-- Set or swap Quin in slot
function QuinRosterService.setQuinInSlot(player, slotIndex, quinInst)
	local roster = QuinRosterService.getRoster(player)
	if slotIndex < 1 or slotIndex > roster.UnlockedSlots then
		return false, "Slot locked or invalid"
	end
	if quinInst then
		quinInst.OwnerId = tostring(player.UserId)
	end
	roster.Slots[slotIndex] = quinInst
	QuinDataStoreService.saveRoster(player.UserId)
	return true
end

-- Unlock additional slot (up to MAX_SLOTS)
function QuinRosterService.unlockSlot(player, slotIndex)
	local roster = QuinRosterService.getRoster(player)
	if slotIndex <= roster.UnlockedSlots then
		return true, "Already unlocked"
	end
	if slotIndex > QuinRosterService.MAX_SLOTS then
		return false, "Exceeds maximum slots"
	end
	if slotIndex == roster.UnlockedSlots + 1 then
		roster.UnlockedSlots = slotIndex
		QuinDataStoreService.saveRoster(player.UserId)
		print(string.format("[QuinRosterService] Unlocked slot %d for %s", slotIndex, player.Name))
		return true
	end
	return false, "Must unlock slots sequentially"
end

-- Transfer Quin from one player to another (Selling / Trading / Gifting)
-- Full battle history, rivalries, titles, and personality are preserved!
function QuinRosterService.transferQuin(quinId, sellerPlayer, buyerPlayer, transferReason)
	local sellerId = tostring(sellerPlayer.UserId)
	local buyerId = tostring(buyerPlayer.UserId)
	return QuinDataStoreService.transferQuin(quinId, sellerId, buyerId, transferReason)
end

-- Retire or release a Quin to the Memorial/Graveyard
function QuinRosterService.retireQuin(player, slotIndex, reason)
	return QuinDataStoreService.retireQuin(player.UserId, slotIndex, reason)
end

-- Dissolve / Sacrifice a Quin for Elemental Cores and Shards (Authoritative Player Destruction)
function QuinRosterService.dissolveQuin(player, slotIndex)
	return QuinDataStoreService.dissolveQuin(player.UserId, slotIndex)
end

-- Find any Quin across active rosters by QuinId
function QuinRosterService.findQuinById(quinId)
	return QuinDataStoreService.findQuinById(quinId)
end

-- Record match outcome on persistent Quin (updates stats, rivalries, titles, and persists)
function QuinRosterService.recordMatchOutcome(quinId, outcome, matchStats, rivalQuinId)
	return QuinDataStoreService.recordMatchOutcome(quinId, outcome, matchStats, rivalQuinId)
end

_G.QuinRosterService = QuinRosterService
shared.QuinRosterService = QuinRosterService

return QuinRosterService
