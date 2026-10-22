--// OwnerChatter.lua
-- What Quin owners, their managers and their friends say to each other in the preparation rooms
-- and the hallways (ArenaNpcOwners). Unlike the stands they discuss: a conversation is a thread on
-- one topic, 4 to 7 turns, so the answers fit the question. Separate topics before the fight
-- (pre), during it (live) and after it (post), at the glass (watching their own Quins) and in the
-- hallway (friends hanging out). Slots: {team} (the speaker's side), {other}, {quin} (a Quin
-- described), {n} (a number), {name} (someone they know), {place} (somewhere in Argonia).

local OwnerChatter = {}

local QUINS = {
    "the tall one", "our female", "the bronze one", "number {n}", "the quick one", "the one on the left",
    "the big one", "their captain", "the new one", "the one by the wall", "the one limping", "their leader",
    "the small one", "the dodger", "their brawler", "the one in the middle", "our second", "our first",
}
local NAMES = {
    "Kai", "Mira", "Dex", "Juno", "Rook", "Sana", "Theo", "Lumi", "Bram", "Nia", "Oz", "Pia", "Ravi", "Tess",
    "Vale", "Ines", "Hugo", "Wren",
}
local PLACES = {
    "the Argonia Trade Center", "the ATC food court", "the workshop", "the night market", "the skybridge",
    "the dorm roof", "the noodle place by the gate", "the training yard",
}

-- TOPICS[phase][context] = { { open, reply, follow, close }, ... }
local TOPICS = {
    pre = {
        glass = {
            { -- the plan
                open = { "So what's the plan this round?", "Walk me through the plan one more time.", "We sticking with the same plan?", "Tell me you've got a plan." },
                reply = { "Keep them together early, split late.", "Let {quin} lead, the rest follow.", "Defend first, punish mistakes.", "Same as last time, but faster." },
                follow = { "And if {other} rushes us?", "What if they go for {quin} first?", "You sure that's enough?" },
                close = { "Okay. I trust you.", "Fine, let's see it work.", "Alright, deep breaths.", "Then let's go." },
            },
            { -- nerves
                open = { "My hands are shaking, look.", "I always get nervous before the anthem.", "Is it normal to feel sick before a round?", "I can't sit still." },
                reply = { "Everyone does. It passes.", "That means you care.", "Breathe. They trained for this.", "Sit down, you're making me nervous." },
                follow = { "What if they freeze out there?", "What if I picked the wrong pair?", "Did you feel like this your first time?" },
                close = { "Okay. Okay. I'm fine.", "Thanks. I needed that.", "Right. Eyes on the glass.", "Let's just watch." },
            },
            { -- the opponents
                open = { "Did you scout {other}?", "What do we know about {other}'s lineup?", "Who's the threat on {other}'s side?", "Seen {other} fight before?" },
                reply = { "Their {quin} hits hard but slow.", "They rush. Always rush.", "Their captain baits, then flanks.", "Nothing special, honestly." },
                follow = { "So we bait the rush?", "Can ours outlast that?", "How do we stop the flank?" },
                close = { "Good. Let them come.", "We'll find out soon.", "Keep an eye on that one.", "Noted." },
            },
            { -- the Quins' condition
                open = { "How's {quin} feeling after the patch?", "Did the workshop finish the repairs?", "Is {quin} fully charged?", "Any damage left from last time?" },
                reply = { "Good as new.", "Mostly fixed, the left arm's a bit stiff.", "Fully charged, ready to go.", "Nothing that'll slow it down." },
                follow = { "You checked the joints yourself?", "Should we hold it back a bit?", "And the second one?" },
                close = { "Good. No excuses then.", "Then it fights.", "Perfect.", "Let's hope it holds." },
            },
            { -- the stakes
                open = { "How many credits are riding on this?", "If we win this, we're in the top ten.", "This one matters, right?", "You know what happens if we lose?" },
                reply = { "Enough that I'm not looking.", "Top ten. Imagine.", "Every round matters.", "We don't lose. Simple." },
                follow = { "What do we do with the winnings?", "And the sponsors are watching?", "No pressure then." },
                close = { "One fight at a time.", "Let's earn it first.", "Ha. No pressure at all.", "Okay, focus." },
            },
            { -- the room
                open = { "This room is nicer than last season's.", "The view from here is perfect.", "Who had this room before us?", "Can they see us through the glass?" },
                reply = { "They upgraded the whole floor.", "Best seat for watching our own.", "Some {team} owner, I think.", "One-way glass. We're invisible." },
                follow = { "Do we get to keep it?", "Even the snacks are free?", "Good, I make faces when I watch." },
                close = { "I could live here.", "Not bad at all.", "Ha, me too.", "Alright, enough sightseeing." },
            },
        },
        hall = {
            { -- weekend plans
                open = { "What are you doing after this?", "Any plans tonight?", "You going to {place} later?", "We should do something after the match." },
                reply = { "Probably food. Always food.", "Nothing yet, why?", "Maybe {place}, if it's not packed.", "Sleep, honestly." },
                follow = { "Come with us, {name} is coming too.", "Want to grab a bite at {place}?", "You always say that." },
                close = { "Okay, I'm in.", "Fine, but you're paying.", "Sure, count me in.", "Let's see how the match goes first." },
            },
            { -- someone's Quin
                open = { "Did you see {name}'s new Quin?", "{name} finally got a Quin.", "Whose room is this one?", "Is {name} fighting tonight?" },
                reply = { "Yeah, it's huge.", "Took them long enough.", "Some new owner, never met them.", "Two Quins, both on {team}." },
                follow = { "Think it'll survive the first round?", "Do they even know how to coach it?", "Should we knock and say hi?" },
                close = { "We'll see.", "Ha, probably not.", "Later, they look busy.", "Let's go see." },
            },
            { -- the season
                open = { "This season's been wild.", "Who's top of the board right now?", "How many rounds left this season?", "You think {team} takes the season?" },
                reply = { "Wildest one I remember.", "{team}, by a hair.", "A few days, I think.", "Too close to call." },
                follow = { "And next season you're entering?", "Did you see the upset last week?", "Who's your money on?" },
                close = { "Maybe. If I save up.", "Still not over it.", "{team}. Always.", "We'll find out." },
            },
            { -- hunger
                open = { "I'm starving.", "Is there food on this floor?", "When does the food stand open?", "Did anyone bring snacks?" },
                reply = { "Same. I skipped lunch.", "Down the stairs, I think.", "After the anthem, probably.", "I have gum. That's it." },
                follow = { "Wanna go now before it starts?", "Can you grab me something?", "Gum doesn't count." },
                close = { "No, we'll miss the anthem.", "Fine. What do you want?", "It counts if you're desperate.", "After. Promise." },
            },
            { -- gossip
                open = { "Did you hear what happened with {name}?", "Okay, you won't believe this.", "So guess who I ran into.", "Have you talked to {name} lately?" },
                reply = { "No, what?", "Try me.", "Who?", "Not in weeks, why?" },
                follow = { "They sold their Quin. Just like that.", "{name} is training at the workshop now.", "They moved to the dorms by the skybridge." },
                close = { "No way.", "That's actually wild.", "Good for them.", "I need details later." },
            },
            { -- the hallway
                open = { "It's packed up here tonight.", "Why is everyone in the hallway?", "This hallway is louder than the stands.", "Can we even get through?" },
                reply = { "Big match night.", "Nobody wants to sit inside.", "Ha, right?", "Squeeze past, it's fine." },
                follow = { "I lost {name} somewhere back there.", "Should we find a room to watch from?", "Is it always like this?" },
                close = { "They'll find us.", "Let's knock on a few doors.", "Every big night.", "Let's just stay here." },
            },
        },
    },
    live = {
        glass = {
            { -- tactics
                open = { "Watch their left side.", "They're splitting us up.", "Pull back, pull back...", "See how they circle?" },
                reply = { "I see it. Ours sees it too.", "Not for long.", "It's pulling back, look.", "Classic bait." },
                follow = { "Now punish it!", "Don't take the bait...", "Wait for the opening." },
                close = { "Yes! Like that!", "Good, good.", "Patience...", "Okay, breathe." },
            },
            { -- a big hit
                open = { "Did you see that hit?!", "Oh, that one hurt.", "That was a clean strike!", "Ours just got rocked." },
                reply = { "The whole arena felt it.", "It's still standing, it's fine.", "That's what we trained for.", "Get up, get up..." },
                follow = { "Can it take another one like that?", "Do it again!", "Is it limping now?" },
                close = { "It'll hold.", "Again! Again!", "A little. It'll manage.", "Come on..." },
            },
            { -- worry
                open = { "Ours is tiring. Look at the footwork.", "It's slowing down.", "Why is it backing off?", "Its guard is dropping." },
                reply = { "It's saving energy.", "That's the plan, trust it.", "Something's wrong with the knee.", "It needs a second." },
                follow = { "Can we tell it anything from up here?", "How long can it keep that up?", "And if they see it too?" },
                close = { "We just watch. That's the hard part.", "Long enough, hopefully.", "Then it's over.", "Come on, come on." },
            },
            { -- the enemy
                open = { "Their big one is the threat.", "That one's reckless.", "{other}'s captain hasn't been touched.", "Who's that one hunting?" },
                reply = { "Keep them apart.", "Reckless wins sometimes.", "Not yet. Wait.", "Ours, I think." },
                follow = { "Two on one, go!", "Can ours bait it out?", "Someone help it!" },
                close = { "There we go!", "Smart.", "Too late...", "Hold on..." },
            },
            { -- the score
                open = { "How many are still up on our side?", "Are we ahead?", "Count the hits, not the swings.", "How long's left?" },
                reply = { "More than them, I think.", "Barely.", "We're landing more.", "Not long. Under {n} minutes." },
                follow = { "Then just survive!", "Can we close it out?", "Don't do anything stupid now." },
                close = { "Hold the line.", "We can.", "It won't.", "Almost there." },
            },
            { -- celebrating
                open = { "Told you. Told you!", "Nice! Nice!", "Did you see that dodge?!", "That's my Quin!" },
                reply = { "Okay, you were right.", "Beautiful.", "Clean. So clean.", "Ha! Yes!" },
                follow = { "Keep that up and we take it.", "Did the crowd see that?", "I want that on replay." },
                close = { "Don't jinx it.", "The whole stadium did.", "Later, watch now.", "Focus, it's not over." },
            },
            { -- frustration
                open = { "Ugh. Sloppy.", "Too slow on the guard.", "Why would it go in alone?!", "That was a bad trade." },
                reply = { "It'll learn.", "It's tired, give it a break.", "Brave though.", "We'll fix it after." },
                follow = { "We're working on guard all week.", "One more of those and it's down.", "I can't watch." },
                close = { "Agreed.", "Then it better not.", "Watch. It's fine.", "Look, it recovered." },
            },
        },
        hall = {
            { -- what's happening
                open = { "What's the score?", "Who's winning?", "Did I miss anything?", "What was that noise?" },
                reply = { "{team} is up, I think.", "Too close to call.", "A big knockdown, you missed it.", "The crowd went off for {team}." },
                follow = { "Let's find a room with a view.", "Can we watch from your friend's room?", "Ugh, I always miss the good bits." },
                close = { "Come on, this way.", "I'll knock.", "Next time come early.", "Let's go." },
            },
            { -- watching through the doors
                open = { "You can see the fight through that door.", "Can you see anything from here?", "Move, I can't see.", "Is that the big screen?" },
                reply = { "Barely, between the heads.", "A bit, the left side.", "Sorry, sorry.", "Just a reflection." },
                follow = { "Let's get closer.", "Should we go down to the stands?", "This is useless." },
                close = { "Okay, closer.", "No, it's packed down there.", "It's fine, listen to the crowd.", "Ha. Yeah." },
            },
            { -- betting
                open = { "I bet {n} credits on {team}.", "Want to bet on this one?", "Who are you backing?", "Last bet of the night?" },
                reply = { "Bold.", "Sure, {n} on {other}.", "{team}, always.", "You never learn." },
                follow = { "Deal. Shake on it.", "Double or nothing?", "Watch me win this time." },
                close = { "Deal.", "You're on.", "No way.", "We'll see." },
            },
            { -- the crowd
                open = { "Listen to that crowd!", "The stands are shaking.", "Was that the wave?", "They're chanting for {team}." },
                reply = { "Loudest I've heard.", "I felt it in the floor.", "It went all the way round.", "Of course they are." },
                follow = { "We should be down there.", "Let's start one up here.", "Want to join them after?" },
                close = { "Next round.", "Ha, nobody would join.", "Sure.", "Maybe." },
            },
            { -- excitement
                open = { "This is the best round tonight.", "My heart can't take this.", "I can't believe it's still going.", "Are you even watching?" },
                reply = { "Easily.", "Mine neither.", "Neither can I.", "Sort of." },
                follow = { "It's going to the wire.", "Whoever wins deserves it.", "Okay, now I'm watching." },
                close = { "Here it comes.", "Agreed.", "Good.", "Shh, look." },
            },
        },
    },
    post = {
        glass = {
            { -- the result, won
                open = { "We did it. We actually did it.", "Did that just happen?", "{team} wins! WE WIN!", "Tell me I'm not dreaming." },
                reply = { "We did!", "It happened.", "Ha, we really did.", "You're not dreaming." },
                follow = { "I need to sit down.", "The workshop's going to love this.", "Can we go see them?" },
                close = { "Sit. Enjoy it.", "They earned it.", "Soon. Let them breathe.", "What a night." },
            },
            { -- the result, lost
                open = { "Well. That hurt.", "We lost it in the last minute.", "I don't want to talk about it.", "They were just better tonight." },
                reply = { "Next round.", "So close though.", "Then don't.", "Tonight, maybe." },
                follow = { "What went wrong?", "I keep replaying it.", "Do we change the pair?" },
                close = { "We'll go over it tomorrow.", "Stop. Get some sleep.", "Maybe. Let's think.", "Next time." },
            },
            { -- the review
                open = { "That dodge in the middle was perfect.", "What did you think of the opening?", "The guard was better this time.", "Did you see when {quin} flanked?" },
                reply = { "Textbook.", "Too slow, but it worked out.", "Much better.", "That won us the round." },
                follow = { "We drill that all week.", "And the ending?", "What do we fix first?" },
                close = { "Agreed.", "Messy, but fine.", "Stamina.", "Let's write it down." },
            },
            { -- repairs
                open = { "How badly is it hurt?", "Workshop tonight or tomorrow?", "Look at the dents on {quin}.", "Is it walking okay?" },
                reply = { "Nothing serious.", "Tonight, before it stiffens.", "Ouch. That'll cost.", "Limping a little." },
                follow = { "Can it fight next round?", "How many credits for the repairs?", "I'll take it in myself." },
                close = { "If the workshop's fast.", "Worth it.", "Thanks.", "I'll come with you." },
            },
            { -- leaving the room
                open = { "Ready to head out?", "Should we pack up?", "Our time in the room's almost up.", "Let's go before the rush." },
                reply = { "One more minute.", "Yeah, let's go.", "Already?", "Good idea." },
                follow = { "Wanna grab a bite at {place}?", "Drinks to celebrate?", "We could watch the replay downstairs." },
                close = { "Sure! Let's go, you lead the way.", "Yes. I'm starving.", "Sounds perfect.", "Okay, let's go." },
            },
            { -- next time
                open = { "When's our next round?", "Do we enter the next event?", "Same pair next time?", "Should we try 1v1 next?" },
                reply = { "Next window, I think.", "If the repairs are done.", "Don't change a winning pair.", "Maybe. It suits {quin}." },
                follow = { "I'll register at the terminal.", "Let's check the schedule.", "We need more training first." },
                close = { "Do it.", "Good idea.", "Agreed.", "Then let's train." },
            },
        },
        hall = {
            { -- food
                open = { "That was a fun watch. Wanna grab a bite at {place}?", "I'm starving. Food?", "Where are we eating?", "Who's hungry?" },
                reply = { "Sure! Let's go, you lead the way.", "Yes. Please.", "{place}?", "Me. Always me." },
                follow = { "{name} said they'd meet us there.", "Last one there pays.", "I know a shortcut." },
                close = { "Let's go then.", "Ha, not me.", "Lead the way.", "Perfect." },
            },
            { -- the highlight
                open = { "What a round.", "Best moment of the night?", "Did you see the ending?", "That last hit though." },
                reply = { "Unreal.", "The comeback.", "I screamed.", "I'm still shaking." },
                follow = { "I'm watching the replay later.", "{name} filmed the whole thing.", "We have to come next week." },
                close = { "Send it to me.", "Definitely.", "Deal.", "Every week." },
            },
            { -- heading home
                open = { "I should head home.", "It's late, huh?", "How are you getting back?", "Leaving already?" },
                reply = { "Me too.", "Skylark late, yeah.", "Skybridge, then the tram.", "Tired." },
                follow = { "Walk with me to the gate?", "Same time next week?", "Text me when you're home." },
                close = { "Sure.", "Same time.", "Will do.", "See you." },
            },
            { -- the owners
                open = { "Did you see the owner's face?", "{name}'s owner must be thrilled.", "The losing rooms are so quiet.", "Should we congratulate them?" },
                reply = { "Priceless.", "Over the moon.", "Poor things.", "Yeah, knock on their door." },
                follow = { "Imagine owning a winner.", "I'd be crying.", "Let them be for a bit." },
                close = { "One day.", "Me too.", "Fair.", "Later then." },
            },
            { -- money
                open = { "You owe me {n} credits.", "I won the bet!", "Pay up.", "Did you win anything?" },
                reply = { "Ugh. Fine.", "Lucky.", "Tomorrow, I swear.", "A little." },
                follow = { "Double or nothing next round?", "Food's on you then.", "You said that last time." },
                close = { "You're on.", "Fine.", "I mean it this time.", "Deal." },
            },
            { -- plans
                open = { "Are you coming to the next match?", "Same group next time?", "We should get a room next time.", "Next time I'm bringing {name}." },
                reply = { "Wouldn't miss it.", "Obviously.", "If someone wins one for us.", "Good, they'd love it." },
                follow = { "I'll check the schedule.", "Let's register a Quin ourselves.", "Let's meet at {place} before." },
                close = { "Send me the time.", "One day.", "Done.", "Perfect." },
            },
        },
    },
}

local function fill(text, rng, team)
    team = team or (rng:NextNumber() < 0.5 and "Alpha" or "Beta")
    local other = team == "Alpha" and "Beta" or "Alpha"
    text = text:gsub("{quin}", function()
        return QUINS[rng:NextInteger(1, #QUINS)]
    end)
    text = text:gsub("{team}", team):gsub("{other}", other)
    text = text:gsub("{name}", function()
        return NAMES[rng:NextInteger(1, #NAMES)]
    end)
    text = text:gsub("{place}", function()
        return PLACES[rng:NextInteger(1, #PLACES)]
    end)
    text = text:gsub("{n}", function()
        return tostring(rng:NextInteger(2, 12) * (rng:NextNumber() < 0.5 and 1 or 5))
    end)
    return text
end

local function pick(list, rng)
    return list[rng:NextInteger(1, #list)]
end

-- A discussion for `phase` ("pre" / "live" / "post") and `context` ("glass" / "hall"), on one
-- topic: { {who = 1 | 2, text}, ... }, 4 to 7 turns. `team` is the speakers' side (optional).
function OwnerChatter.conversation(phase, context, rng, team)
    local byContext = TOPICS[phase] or TOPICS.pre
    local topics = byContext[context] or byContext.glass
    local t = pick(topics, rng)
    local turns = {
        { who = 1, text = fill(pick(t.open, rng), rng, team) },
        { who = 2, text = fill(pick(t.reply, rng), rng, team) },
        { who = 1, text = fill(pick(t.follow, rng), rng, team) },
    }
    if rng:NextNumber() < 0.6 then
        -- (more back and forth before it settles)
        table.insert(turns, { who = 2, text = fill(pick(t.reply, rng), rng, team) })
        if rng:NextNumber() < 0.5 then
            table.insert(turns, { who = 1, text = fill(pick(t.follow, rng), rng, team) })
        end
    end
    table.insert(turns, { who = #turns % 2 == 0 and 1 or 2, text = fill(pick(t.close, rng), rng, team) })
    if rng:NextNumber() < 0.35 then
        table.insert(turns, { who = turns[#turns].who == 1 and 2 or 1, text = fill(pick(t.close, rng), rng, team) })
    end
    return turns
end

-- The phase the owners talk about, from the arena's phase (Workspace attribute CrowdPhase)
function OwnerChatter.phaseOf(crowdPhase)
    if crowdPhase == "IN_GAME" then
        return "live"
    elseif crowdPhase == "WINNER_DETERMINATION" or crowdPhase == "POST_GAME" then
        return "post"
    end
    return "pre"
end

function OwnerChatter.count()
    local n = 0
    for _, byContext in pairs(TOPICS) do
        for _, topics in pairs(byContext) do
            for _, t in ipairs(topics) do
                n += #t.open + #t.reply + #t.follow + #t.close
            end
        end
    end
    return n
end

return OwnerChatter
