import sys
import time
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")

from roblox_client import RobloxStudioClient
client = RobloxStudioClient()
print("Connected Studio ID:", client.studio_id)

test_code = """
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))
local QuinDataStoreService = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinDataStoreService"))

local results = {}

-- 1. Create QuinInstance
local quin = QuinInstance.create({
    OwnerId = "1001",
    Type = "TypeC",
    Element = "Water",
})
results.createdId = quin.QuinId
results.initialOwner = quin.OwnerId
results.initialElement = quin.Element

-- 2. Simulate 4 matches with Rivalry against Q_NEMESIS
QuinInstance.recordRivalry(quin, "Q_NEMESIS", "Loss", 120)
QuinInstance.recordRivalry(quin, "Q_NEMESIS", "Loss", 80)
QuinInstance.recordRivalry(quin, "Q_NEMESIS", "Win", 30)
QuinInstance.recordRivalry(quin, "Q_OTHER", "Win", 10)

local primaryRival, rivData = QuinInstance.getPrimaryRival(quin)
results.primaryRival = primaryRival
results.rivalEncounters = rivData and rivData.Encounters
results.rivalGrudge = rivData and rivData.GrudgeScore

-- 3. Record Match Battles & Title Unlocks
QuinInstance.recordBattle(quin, "Win", { kills = 3, damage = 450 })
QuinInstance.recordBattle(quin, "Win", { kills = 1, damage = 300 })
QuinInstance.recordBattle(quin, "Win", { kills = 2, damage = 500 })

results.totalBattles = quin.BattleRecord.Battles
results.totalWins = quin.BattleRecord.Wins
results.currentStreak = quin.BattleRecord.CurrentStreak
results.bestStreak = quin.BattleRecord.BestStreak
results.earnedTitles = quin.Titles.Earned
results.equippedTitle = quin.Titles.Current

-- 4. Ownership Transfer (Selling / Trading Quin from User 1001 to User 2002)
local transferOk, err = QuinInstance.transferOwnership(quin, "2002", "SoldOnMarketplace")
results.transferOk = transferOk
results.newOwner = quin.OwnerId
results.prevOwnersCount = #quin.Ownership.PreviousOwners
results.preservedWinsAfterTransfer = quin.BattleRecord.Wins
results.preservedRivalAfterTransfer = quin.Rivalries["Q_NEMESIS"] ~= nil

-- 5. DataStore Serialization Round-Trip
local serialized = QuinInstance.serialize(quin)
local deserialized = QuinInstance.deserialize(serialized)
results.deserializedOwner = deserialized.OwnerId
results.deserializedStreak = deserialized.BattleRecord.CurrentStreak
results.deserializedRivalGrudge = deserialized.Rivalries["Q_NEMESIS"].GrudgeScore

-- 6. QuinDataStoreService Roster Load/Save Mock Test
local testUser = "TEST_USER_999"
local roster = QuinDataStoreService.loadRoster(testUser)
results.loadedRosterSlots = #roster.Slots
results.rosterOwner = roster.OwnerId

-- Save roster
local saveOk = QuinDataStoreService.saveRoster(testUser, true)
results.saveOk = saveOk

return HttpService:JSONEncode(results)
"""

res = client.execute_luau(test_code, datamodel_type="Server")
raw = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Persistence & Rivalry test results:", raw)
client.close()
