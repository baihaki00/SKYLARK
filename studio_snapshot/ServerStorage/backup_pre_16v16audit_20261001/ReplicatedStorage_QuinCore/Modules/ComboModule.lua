--// ComboModule.lua
-- Combo sequence engine
-- Tracks combo state per fighter, handles combo chains and transitions

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComboModule = {}

-- Per-fighter combo state
local comboStates = {}

-- Combo sequences (index = step)
local COMBO_SEQUENCES = {
	Light = {
		{name = "Jab", damageMultiplier = 1.0, knockback = 18, hitboxSize = Vector3.new(4, 4, 4), duration = 0.3},
		{name = "Cross", damageMultiplier = 1.1, knockback = 25, hitboxSize = Vector3.new(4, 4, 5), duration = 0.3},
		{name = "Hook", damageMultiplier = 1.2, knockback = 32, hitboxSize = Vector3.new(5, 4, 5), duration = 0.35},
		{name = "Uppercut", damageMultiplier = 1.3, knockback = 40, hitboxSize = Vector3.new(5, 5, 5), duration = 0.4},
		{name = "PowerPunch", damageMultiplier = 1.6, knockback = 105, hitboxSize = Vector3.new(6, 6, 6), duration = 0.6},
	},
	Heavy = {
		{name = "Haymaker", damageMultiplier = 1.8, knockback = 30, hitboxSize = Vector3.new(5, 5, 6), duration = 0.6},
		{name = "GutPunch", damageMultiplier = 2.0, knockback = 35, hitboxSize = Vector3.new(5, 5, 5), duration = 0.5},
		{name = "OverheadSlam", damageMultiplier = 2.5, knockback = 126, hitboxSize = Vector3.new(6, 6, 6), duration = 0.7},
	},
	Aerial = {
		{name = "AirJab", damageMultiplier = 1.0, knockback = 20, hitboxSize = Vector3.new(4, 4, 4), duration = 0.25},
		{name = "AirCross", damageMultiplier = 1.2, knockback = 30, hitboxSize = Vector3.new(4, 5, 5), duration = 0.3},
		{name = "MeteorSlam", damageMultiplier = 2.0, knockback = 120, slam = true, hitboxSize = Vector3.new(6, 6, 6), duration = 0.6},
	},
}

-- Initialize combo state for a fighter
local function getState(fighter)
	if not comboStates[fighter] then
		comboStates[fighter] = {
			currentSequence = nil,
			currentStep = 0,
			lastAttackTime = 0,
			comboWindowTime = 0.8,
		}
	end
	return comboStates[fighter]
end

-- Start or continue a combo
function ComboModule.nextAttack(fighter, sequenceType)
	local state = getState(fighter)
	local now = tick()
	
	sequenceType = sequenceType or "Light"
	local sequence = COMBO_SEQUENCES[sequenceType]
	if not sequence then return nil end
	
	-- Check combo window
	if state.currentSequence ~= sequenceType or (now - state.lastAttackTime) > state.comboWindowTime then
		-- Reset combo
		state.currentSequence = sequenceType
		state.currentStep = 0
	end
	
	-- Check combo max from QuinData
	local comboMax = fighter:GetAttribute("ComboMax") or 5
	
	-- Advance
	state.currentStep = state.currentStep + 1
	if state.currentStep > #sequence or state.currentStep > comboMax then
		state.currentStep = 1
		state.currentSequence = sequenceType
	end
	
	state.lastAttackTime = now
	local moveData = sequence[state.currentStep]
	
	return {
		name = moveData.name,
		step = state.currentStep,
		totalSteps = math.min(#sequence, comboMax),
		damageMultiplier = moveData.damageMultiplier,
		knockback = moveData.knockback,
		isLaunch = moveData.launch or false,
		isSlam = moveData.slam or false,
		hitboxSize = moveData.hitboxSize,
		duration = moveData.duration,
	}
end

-- Reset combo state
function ComboModule.resetCombo(fighter)
	local state = getState(fighter)
	state.currentStep = 0
	state.currentSequence = nil
end

-- Get current combo step
function ComboModule.getComboStep(fighter)
	local state = getState(fighter)
	return state.currentStep
end

-- Check if combo is at the launch finisher
function ComboModule.isAtLaunchFinisher(fighter)
	local state = getState(fighter)
	if not state.currentSequence then return false end
	local sequence = COMBO_SEQUENCES[state.currentSequence]
	if not sequence then return false end
	local move = sequence[state.currentStep]
	return move and move.launch == true
end

-- Cleanup
function ComboModule.cleanup(fighter)
	comboStates[fighter] = nil
end

-- Expose sequences for config
ComboModule.SEQUENCES = COMBO_SEQUENCES

return ComboModule
