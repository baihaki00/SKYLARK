--// BattleEventSystem.lua
-- Detects emergent battlefield conditions (Isolated Target, Outnumbered, Surround, Clutch, Rescue)
-- Decoupled observability instrument: emits structured telemetry without altering combat physics.

local BattleEventSystem = {}

local listeners = {}
local eventCooldowns = {} -- Prevent console spamming for the same Quin

-- Emit a detected battle event
function BattleEventSystem.emit(eventName, data)
	data = data or {}
	local quinId = data.QuinId or (data.Model and data.Model.Name) or "Unknown"
	local key = eventName .. "_" .. tostring(quinId)
	local now = tick()

	-- 3-second debounce per entity per event type
	if eventCooldowns[key] and (now - eventCooldowns[key] < 3.0) then
		return
	end
	eventCooldowns[key] = now

	-- Format structured debug output
	local lines = {
		string.format("[BattleEvent] %s", eventName),
		string.format("  Entity: %s (Type: %s | Elem: %s)", tostring(quinId), tostring(data.Type or "N/A"), tostring(data.Element or "N/A")),
	}
	if data.TargetName then
		table.insert(lines, string.format("  Target: %s", tostring(data.TargetName)))
	end
	if data.EnemiesCount ~= nil and data.AlliesCount ~= nil then
		table.insert(lines, string.format("  Local Density: %d Enemies vs %d Allies (Advantage: %.2f)", data.EnemiesCount, data.AlliesCount, data.Advantage or 1.0))
	end
	if data.Extra then
		table.insert(lines, string.format("  Context: %s", tostring(data.Extra)))
	end

	print(table.concat(lines, "\n"))

	-- Notify registered listeners
	for _, cb in ipairs(listeners) do
		task.spawn(cb, eventName, data)
	end
end

-- Subscribe to battle events
function BattleEventSystem.onEvent(callback)
	table.insert(listeners, callback)
end

-- Check and evaluate battle events from a Quin's tactical perception
function BattleEventSystem.checkEvents(quinModel, tacticalContext)
	if not tacticalContext then return end

	local qId = quinModel:GetAttribute("QuinId") or quinModel.Name
	local qType = quinModel:GetAttribute("QuinType") or "TypeA"
	local qElem = quinModel:GetAttribute("Element") or "Fire"

	local allies = tacticalContext.nearbyAlliesCount or 0
	local enemies = tacticalContext.nearbyEnemiesCount or 0
	local adv = tacticalContext.localAdvantageRatio or 1.0
	local hp = tacticalContext.ownHealthRatio or 1.0

	-- 1. OUTNUMBERED: Alone or severely outnumbered against 2+ opponents
	if enemies >= 2 and allies == 0 then
		BattleEventSystem.emit("OUTNUMBERED", {
			Model = quinModel,
			QuinId = qId,
			Type = qType,
			Element = qElem,
			EnemiesCount = enemies,
			AlliesCount = allies,
			Advantage = adv,
			Extra = "Severe local numerical disadvantage",
		})
	end

	-- 2. SURROUND / CONVERGENCE: 3+ allies converging on an isolated opponent
	if tacticalContext.targetInfo and tacticalContext.targetInfo.isIsolated and allies >= 2 then
		BattleEventSystem.emit("SURROUND", {
			Model = quinModel,
			QuinId = qId,
			Type = qType,
			Element = qElem,
			TargetName = tacticalContext.targetInfo.model.Name,
			EnemiesCount = 1,
			AlliesCount = allies + 1,
			Advantage = allies + 1,
			Extra = "Converging on isolated enemy fighter",
		})
	end

	-- 3. ISOLATED_TARGET: Target is completely cut off from team
	if tacticalContext.targetInfo and tacticalContext.targetInfo.isIsolated and enemies <= 1 then
		BattleEventSystem.emit("ISOLATED_TARGET", {
			Model = quinModel,
			QuinId = qId,
			Type = qType,
			Element = qElem,
			TargetName = tacticalContext.targetInfo.model.Name,
			EnemiesCount = enemies,
			AlliesCount = allies,
			Advantage = adv,
			Extra = "Target isolated with zero allied support",
		})
	end

	-- 4. CLUTCH / LAST_STAND: Low health (<20%) holding ground
	if hp > 0 and hp <= 0.20 and enemies >= 1 then
		BattleEventSystem.emit("LAST_STAND", {
			Model = quinModel,
			QuinId = qId,
			Type = qType,
			Element = qElem,
			EnemiesCount = enemies,
			AlliesCount = allies,
			Advantage = adv,
			Extra = string.format("Health critically low (%.0f%%)", hp * 100),
		})
	end

	-- 5. EXHAUSTION: Low energy threshold
	local energyRatio = tacticalContext.ownEnergyRatio or 1.0
	if energyRatio <= 0.15 then
		BattleEventSystem.emit("EXHAUSTION", {
			Model = quinModel,
			QuinId = qId,
			Type = qType,
			Element = qElem,
			Extra = string.format("Energy depleted (%.0f%%)", energyRatio * 100),
		})
	end
end

return BattleEventSystem
