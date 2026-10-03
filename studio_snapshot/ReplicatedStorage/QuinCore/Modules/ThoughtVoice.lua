--// ThoughtVoice.lua
-- What a Quin is thinking, in its own words (the mind panel: StarterPlayerScripts.QuinMindPanel).
--
-- Quins never speak; this is the spectator reading their mind. It adds no behaviour: it only
-- phrases facts the game already has.
--   reason keys   DecisionSystem tags every reason for a decision with a key ("HealthLow")
--   social keys   SocialTension / SocialRespect attributes (restless and why, waiting, hunting,
--                 the respect custom's roles)
--   action keys   the action taken, for a decision that needed no reason
-- Each key has a few phrasings; a bold Quin and a careful one say the same thing differently.
-- An unknown key falls back to its own name, so a new reason still shows up.

local ThoughtVoice = {}

-- { any = {...} } or { bold = {...}, careful = {...} }
local PHRASES = {
	-- DecisionSystem reasons
	HealthLow = { bold = { "I'm hurt. Doesn't matter.", "That one cost me." }, careful = { "I'm hurt. I need space.", "I can't take many more of those." } },
	Outnumbered = { bold = { "More of them than us here. Good." }, careful = { "Too many of them here.", "I'm outnumbered. Not here." } },
	Surrounded = { any = { "They're all around me.", "I'm boxed in." } },
	Focused = { any = { "They're all coming for me.", "Why is everyone on me?" } },
	EnergyLow = { any = { "I'm spent. I need a moment.", "Nothing left in the tank." } },
	ConfidenceBroken = { any = { "This isn't going my way.", "I've lost my nerve." } },
	CounterStrike = { any = { "They think I'm easy. Hit back.", "Push me and I push harder." } },
	LastStand = { any = { "Nowhere to run. Make it count.", "If I go down, I go down swinging." } },
	HoldForAlly = { any = { "Help is coming. Hold on.", "Just buy time." } },
	DuelNoRetreat = { any = { "This is the duel. I don't back down." } },
	HoldHighGround = { any = { "Good view from here. Stay.", "I hold the high ground." } },
	SeekHighGround = { any = { "I want to be above this.", "Get up high." } },
	RearThreat = { any = { "Someone's behind me.", "Watch my back." } },
	AllyInDanger = { any = { "One of ours is in trouble.", "Hold on, I'm coming." } },
	ClashInstinct = { any = { "He's charging something. Meet it head on." } },
	ChargeAura = { any = { "Nobody's near. Charge up.", "A moment to myself. Use it." } },
	PunishShowoff = { any = { "He's showing off. Shut him up." } },
	QuirkCharger = { any = { "Go. Just go." } },
	QuirkObserver = { any = { "Watch first. Then move." } },
	QuirkOverconfident = { any = { "Nobody here can touch me." } },
	QuirkLowConfidence = { any = { "I'm not sure about this." } },
	QuirkRevenge = { any = { "That one hit me. He's mine." } },
	WaitingThemOut = { any = { "You move first.", "Let them come to us." } },
	Committed = { any = { "I've started this. Finish it." } },
	SurvivalInstinct = { any = { "I'm nearly gone. Get out. Get out!", "One more hit and I'm done. Run." } },
	NothingToLose = { any = { "No more running.", "Nothing left to save myself for." } },
	Hunting = { any = { "He beat our leader. Get him.", "Don't let him breathe." } },
	Restless = { any = { "Enough waiting. I'm going in." } },

	-- SocialTension: restless or waiting, and why
	["Restless:Lull"] = { any = { "It's gone quiet. Somebody has to move. Fine, me.", "Enough standing around." } },
	["Restless:Drought"] = { any = { "This is taking too long.", "Nobody's going down. That ends now." } },
	["Restless:Clock"] = { any = { "Time's running out. If I stall, we lose.", "No time left to be careful." } },
	["Restless:Stall"] = { any = { "I can't keep running.", "I've backed off enough." } },
	["Restless:Futile"] = { any = { "I'm finished either way. Take one with me.", "We lose on time anyway. Go." } },
	["Waiting:Lull"] = { any = { "You move first.", "I can wait." } },
	["Waiting:Drought"] = { any = { "Someone will crack. Not me.", "You move first." } },
	["Waiting:Clock"] = { any = { "We're ahead. The clock is on our side.", "Let them come to us." } },
	["Waiting:Stall"] = { any = { "I've been keeping away a while now..." } },
	["Waiting:Futile"] = { any = { "Hanging on isn't going to save me." } },

	InMyWay = { any = { "Someone's in my way. Go round.", "Mind the body. Round him." } },

	-- SocialRespect roles
	["Respect:Hesitating"] = { any = { "Wait. He's alone.", "Ease off. He's the last one." } },
	["Respect:Watching"] = { any = { "Let them settle it.", "This one is between them." } },
	["Respect:Spectator"] = { any = { "Let them settle it.", "I want to see this." } },
	["Respect:Duelist"] = { any = { "Just me and him now.", "Everyone's watching. Don't slip." } },
	["Respect:Honored"] = { any = { "They're giving me a fair fight.", "One on one. I can do this." } },

	-- actions, when a decision needed no reason
	["Action:Attack"] = { any = { "He's open. Hit him.", "Now." } },
	["Action:Pursue"] = { any = { "Don't let him get away.", "After him." } },
	["Action:Retreat"] = { any = { "I need space.", "Back off. Reset." } },
	["Action:Guard"] = { any = { "Hands up. Wait for it." } },
	["Action:Dash"] = { any = { "Close the gap. Now." } },
	["Action:Reposition"] = { any = { "Bad spot. Move." } },
	["Action:ProtectAlly"] = { any = { "Hold on, I'm coming." } },
	["Action:AuraFarm"] = { any = { "Nobody's near. Charge up." } },
	["Action:Special"] = { any = { "This is the moment. Everything I've got." } },

	Lost = { any = { "I don't know what to do.", "..." } },
}

-- What it is doing, by state (%s: the target's name)
local DOING = {
	Fight = "Trading blows with %s",
	Chase = "Going after %s",
	Circling = "Circling %s, looking for an opening",
	Retreat = "Getting away",
	Overwatch = "Holding high ground, watching",
	Idle = "Standing by",
	Recovery = "Catching its breath",
	Knockback = "Knocked back",
	ProjectileJump = "In the air, coming down on %s",
	MidAirClash = "Clashing with %s in mid-air",
	Special = "Unleashing a special",
	Death = "Down",
}

-- One phrasing for a key. aggression: the Quin's Pers_Aggression (0-1), if known.
function ThoughtVoice.say(key: string, aggression: number?): string
	local entry = PHRASES[key]
	if not entry then
		return key -- a reason nobody has phrased yet still shows
	end
	local list = entry.any
	if not list then
		list = (aggression or 0.5) >= 0.6 and entry.bold or entry.careful
	end
	return list[math.random(#list)]
end

-- The thought keys that hold right now.
-- facts: { action, reasons = {keys}, posture, why, respectRole, inWay, lost }
function ThoughtVoice.keys(facts): { string }
	local keys = {}
	if facts.respectRole then
		table.insert(keys, "Respect:" .. facts.respectRole)
	end
	if facts.posture then
		table.insert(keys, facts.posture .. ":" .. (facts.why or "Lull"))
	end
	local social = { Restless = true, WaitingThemOut = true } -- (said above, with the reason why)
	for _, key in facts.reasons or {} do
		if not (social[key] and facts.posture) then
			table.insert(keys, key)
		end
	end
	if facts.inWay then
		table.insert(keys, "InMyWay")
	end
	if #keys == 0 then
		if facts.lost then
			table.insert(keys, "Lost") -- nothing to do and nobody to do it to
		elseif facts.action then
			table.insert(keys, "Action:" .. facts.action)
		end
	end
	return keys
end

function ThoughtVoice.doing(state: string?, targetName: string?): string
	local text = DOING[state or ""] or (state or "...")
	if text:find("%%s") then
		text = string.format(text, targetName and targetName ~= "" and targetName or "someone")
	end
	return text
end

return ThoughtVoice
