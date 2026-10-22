--// CrowdChatter.lua
-- What the crowd says to each other (ArenaCrowdClient's conversations): separate lines before the
-- fight (pre), during it (live) and after it (post). A conversation is an opener, a reply, and
-- sometimes a follow-up and a last word. Slots are filled at random: {team} / {other} (Alpha,
-- Beta), {quin} (a Quin described), {n} (a number), {name} (a crowd name), so the lines below
-- (500+) come out in many more forms.

local CrowdChatter = {}

local TEAMS = { "Alpha", "Beta" }
local QUINS = {
    "the tall one", "that female Quin", "the bronze one", "number {n}", "the quick one", "the one on the left",
    "the big guy", "their captain", "the new one", "that one by the wall", "the one limping", "the leader",
    "the small one", "the one that keeps dodging", "their brawler", "the one in the middle",
}
local NAMES = {
    "Kai", "Mira", "Dex", "Juno", "Rook", "Sana", "Theo", "Lumi", "Bram", "Nia", "Oz", "Pia", "Ravi", "Tess",
}

local LINES = {
    pre = {
        open = {
            "Who you got this round?", "{team} is taking this one, easy.", "I've got a good feeling about {team}.",
            "You see the line-up for {team}?", "Did you enter anything this round?", "First time watching live?",
            "This seat is way better than last time.", "I heard {team} trained all week.", "The anthem's coming, get ready!",
            "How long until it starts?", "My Quin's resting this round.", "{other} looked rough last match.",
            "I bet you {n} credits {team} wins.", "Who's that in the prep room up there?", "Is it 16 a side tonight?",
            "Did they change the arena again?", "I can't wait for the anthem.", "Smell that? Arena food.",
            "Look at all these people!", "I came straight from the workshop.", "My Quin got patched up yesterday.",
            "This is the featured match, right?", "Last time {team} won in under a minute.", "I'm saving my voice for the anthem.",
            "You think {other} has a chance?", "Who's the favourite?", "I missed the last event, what happened?",
            "They say {quin} is unbeatable.", "I'm here for {quin}, honestly.", "Check out the globe, it's glowing.",
            "Did {name} come with you?", "I lost so many credits on {other} last time.", "Front row next time, I swear.",
            "Do you know anyone fighting tonight?", "I'm so hyped right now.", "It's packed today.",
            "My cousin's Quin is on {team}.", "Which side are we cheering for?", "This is my first Team Battle.",
            "Is it true they added new obstacles?", "I heard the arena reshapes itself.", "Can't believe I got a seat.",
            "Look, the drones are up.", "Who designed this arena? It's huge.", "I'm calling it now: {team} by a mile.",
            "What's the record for this arena?", "I want a Quin so bad.", "Okay, I'm nervous for some reason.",
            "Why does it always start late?", "That ARIA voice gives me chills.", "{name} said {other} is cursed.",
            "We should've brought snacks.", "I hope it's not over too fast.", "Did you see the prep rooms?",
            "Bet the {team} owners are sweating.", "You hear the crowd on the other side?", "This place is loud already.",
            "I painted my wristband {team} colours.", "Remember the comeback last week?", "Let's go, let's go!",
            "Is that your first time in Argonia?", "My friend got a seat in a prep room!", "Who's your favourite Quin ever?",
            "I can feel the floor shaking.", "Where were you last event?", "I'm getting a Quin next season.",
            "Okay, who's buying the next round of drinks?",
            "I swear {team} looks bigger this season.",
            "My hands are already sweating.",
            "Do you think the owners can see us from up there?",
            "{name} owes me {n} credits from last time.",
            "I'd give anything to have a Quin in this match.",
            "Did you see the new prep rooms? They're like dorms.",
            "Is that the drone cam over there?",
            "Hope the arena isn't flat tonight, I want obstacles.",
            "I read {quin} never loses a one-on-one.",
            "Look at the {team} section, they're already chanting.",
            "I've got my lucky jacket on.",
            "Wait, is this seat ours?",
            "You think it'll go the full time?",
            "The globe looks different today.",
        },
        reply = {
            "Easy. {team}.", "No way, {other} all day.", "Honestly? No idea.", "Same, I'm so ready.", "Ha, you wish.",
            "We'll see about that.", "I'm with you on that.", "Nah, {other} looked sharp in warm-ups.", "Don't jinx it!",
            "Deal. {n} credits.", "Right? It's insane.", "Yeah, me too.", "Not since last season.", "Ugh, don't remind me.",
            "Let's hope so.", "That's what everyone says.", "I heard the same thing.", "No, but I wish I did.",
            "Shh, it's starting soon.", "Bro, it's always like this.", "I came for the anthem honestly.", "Ha! Fair.",
            "It's {team} for sure.", "I'll believe it when I see it.", "You always pick {other}.", "Lucky you.",
            "Wait, really?", "That's wild.", "Yeah, the place is packed.", "Ooh, good call.", "Hmm, maybe.",
            "I'm not betting this time.", "Last time I did, I lost everything.", "Totally.", "Facts.",
            "I've been waiting all week.", "Same seat as always.", "Look, there's {name}!", "Okay okay, you might be right.",
            "Can't argue with that.", "Too early to say.", "I'm just here for the vibes.", "Stop, I'm already nervous.",
            "{quin}? Overrated.", "Watch {quin} carry.", "Nah, {quin} is the real threat.", "Yeah, they rebuilt half of it.",
            "It better not be over fast.", "Whatever happens, it'll be loud.", "You're on.", "I love this place.",
            "My throat's already sore.", "First time in the stands?", "We should come every week.", "Ha, typical.",
            "Not me, I'm broke.",
            "Ha, they eat well.",
            "Mine too, it's normal.",
            "Maybe, the glass is one-way?",
            "Good luck getting it.",
            "Same, one day.",
            "I know, I want to live up there.",
            "Yeah, they follow the fights.",
            "Fingers crossed for chaos.",
            "That's a myth.",
            "They're always early.",
            "It's not lucky, it's ugly.",
            "Yeah, sit down.",
            "Probably not.",
            "They upgraded it, I think.",
        },
        follow = {
            "You'll see.", "Mark my words.", "Watch.", "Okay, {n} credits then.", "Don't cry later.", "We'll see who's laughing.",
            "Just wait for the anthem.", "I'm telling you.", "Remember I said it.", "Fine, fine.", "Shh, look!", "Here we go.",
            "Trust me.", "Bet.", "Alright, alright.", "You're on.", "Ha. Okay.", "I'm serious!", "Whatever you say.", "Let's see.",
        },
    },
    live = {
        open = {
            "DID YOU SEE THAT?!", "Oh, that's gotta hurt!", "Come on {team}!", "Get up, get up!", "No no no no...",
            "Finish it!", "That dodge was clean.", "Look at {quin} go!", "Two on one, that's not fair!", "Ref!!",
            "They're running out of steam.", "{team} is pulling ahead.", "{other} is falling apart.", "WHAT A HIT!",
            "Look left, look left!", "He's down! Wait... no!", "That one's not giving up.", "This is getting intense.",
            "How is {quin} still standing?", "They're circling... here it comes.", "Behind you! Behind you!",
            "That was a knockdown!", "Ooh, so close.", "Did it just counter that?", "I can't watch.", "This is insane!",
            "{team} needs to regroup.", "They're baiting them.", "Too slow!", "Run, run!", "That combo!", "Is it fleeing?",
            "Look at the big one charge!", "Their leader's down!", "It's {n} on {n} now!", "Who's winning? I lost track.",
            "That was dirty.", "Unbelievable.", "{quin} just carried that.", "They're surrounding it!", "Get out of there!",
            "Respect, they're bowing!", "Did they just stop to respect each other?", "That jump!", "It's a comeback!",
            "This crowd is going crazy.", "My heart can't take this.", "{other} is so done.", "That's the one I bet on!",
            "Watch the edge!", "It's gonna fall off!", "Oof, right into the wall.", "Pull back, pull back!",
            "Why is nobody helping it?", "Smart, they're waiting.", "That's tactics right there.", "Now! Go now!",
            "Look at the drones!", "Did you hear that hit?", "They're tired, look at them.", "So clean.", "Oh come ON!",
            "That was a slide!", "It just flipped the whole fight.", "Go for the weak one!",
            "Get behind it, get behind it!",
            "That was the worst block I've ever seen.",
            "WHY ARE THEY STANDING STILL?",
            "Look at {quin}, it's furious!",
            "It's hunting the weak one now.",
            "Okay, that hit echoed.",
            "Did the crowd just go silent?",
            "Please don't lose, please don't lose.",
            "{team} is cooking right now.",
            "They're gonna gang up on it!",
            "Is that a draw coming?",
            "Watch the timer!",
            "Oh, it slipped!",
            "I can't believe it's still going.",
            "That's my favourite move.",
        },
        reply = {
            "YES!", "No way!", "I know!", "Insane!", "Come on!", "Ugh!", "Right?!", "Oh my god.", "LET'S GO!",
            "That's my Quin!", "Don't count them out.", "It's over for {other}.", "Not yet, not yet!", "Easy, easy.",
            "I told you!", "Wait for it...", "Huge!", "Haha, brutal.", "Ouch.", "They had it coming.", "Unreal.",
            "Keep going!", "Watch, watch!", "That's {team} for you.", "Sloppy, so sloppy.", "Respect.", "Clutch!",
            "I can't breathe.", "Get it!", "Noooo!", "Yeah!!", "There it is!", "Called it!", "Look at it go!",
            "This is the best match yet.", "I'm losing my voice.", "Did you see the other one?", "Ha! Told you!",
            "Not like this...", "Come on, get up!", "Too strong.", "That's cold.", "Bro...", "Okay, that was sick.",
            "Again! Again!", "So close!", "I almost spilled my drink.", "Wild.", "Nooo, my credits!", "Here we go!",
            "{quin} is cooking.", "Look at {quin}!", "Behind! Behind!", "That's the plan.", "What a fight.",
            "Right?!",
            "So bad!",
            "THEY'RE THINKING!",
            "Scary.",
            "Classic.",
            "My ears!",
            "For a second, yeah.",
            "It won't, relax.",
            "Smoking!",
            "Not again...",
            "Maybe!",
            "Almost out!",
            "Haha, ice skating.",
            "Me neither.",
            "Same, it's so clean.",
        },
        follow = {
            "SEE?!", "LET'S GOOO!", "Come on come on!", "Unbelievable!", "I can't!", "Yes yes yes!", "Ugh, again?!",
            "Told you!", "Get it!", "Wow.", "Okay okay okay!", "Ha!", "Brutal.", "Look!", "Go go go!", "No!", "Clutch!",
            "Haha!", "Insane.", "That's it!",
        },
    },
    post = {
        open = {
            "What a match!", "{team} deserved that.", "I can't believe {other} lost.", "Pay up, {n} credits.",
            "Best match I've seen all season.", "My voice is gone.", "Did you see that last hit?", "{quin} was the MVP.",
            "That comeback though!", "I'm exhausted and I didn't even fight.", "Same time next event?",
            "Those owners are gonna be busy at the workshop.", "{other} needs a whole new strategy.", "GG, honestly.",
            "I'm still shaking.", "Who was that last one standing?", "That anthem was so loud.", "We have to come back.",
            "I lost so many credits.", "I won {n} credits!", "{name} is gonna be so mad.", "That was worth the wait.",
            "Did you record any of that?", "The ending was brutal.", "Respect to {other}, they fought hard.",
            "I'm hungry now.", "That fireworks show though!", "When's the next event?", "My Quin could've done better.",
            "Those prep room people must be screaming.", "I think {team} is the favourite now.", "Rematch when?",
            "That was close, way too close.", "Honestly {other} got unlucky.", "I'm telling everyone about this.",
            "The crowd was insane tonight.", "That ARIA announcement gave me chills.", "Okay, I'm officially a {team} fan.",
            "Did you see {quin} at the end?", "How many were left at the end?", "I need to sit down.", "Rough night for {other}.",
            "That's going in the history books.", "Who's fighting next?", "That was a clean win.", "I'm buying a Quin.",
            "Let's go get food.", "I didn't expect that ending.", "Was that a time-out win?", "The drones caught everything.",
            "Same seats next time?", "{team} fans are going wild.", "I knew it from the anthem.", "That was chaos.",
            "Wait, is it over over?", "Back to the workshop for them.", "My throat hurts.", "Did {name} leave already?",
            "Okay, that was the best thing ever.", "I'm going to dream about that fight.", "{other} will come back stronger.",
            "Well, that settles it.",
            "Did you see the owners in the prep rooms losing it?",
            "I need a rematch for my heart.",
            "Who's buying the {team} wristband first?",
            "I'm still hearing that anthem.",
            "We were so loud tonight.",
            "Imagine being {quin} right now.",
            "{name} won't stop texting me about it.",
            "That last minute though.",
            "I'm framing my ticket.",
            "Somebody check on the {other} fans.",
            "My legs are numb from jumping.",
            "Okay but the ending wasn't fair.",
            "How does the workshop fix them that fast?",
            "Best seat in the house.",
        },
        reply = {
            "Totally!", "Deserved.", "Yeah, they were robbed.", "Ugh, fine, here.", "Hands down.", "Mine too.",
            "That hit was crazy.", "Easily.", "That comeback!", "Same, I'm wrecked.", "Definitely.", "GG.", "Facts.",
            "Me too.", "No idea, it was chaos.", "So loud.", "We have to.", "Ouch, sorry.", "Nice!", "Ha, he will be.",
            "100%.", "I got some clips.", "Brutal ending.", "Yeah, respect.", "Let's eat.", "Those fireworks!",
            "Next cycle I think.", "Yours is still in the workshop?", "Ha, they must be.", "Agreed.", "Soon I hope.",
            "Way too close.", "Unlucky, yeah.", "Tell everyone.", "Insane crowd.", "Chills.", "Welcome aboard.",
            "{quin} was unreal.", "Like {n}?", "Same, sit with me.", "Rough night indeed.", "For sure.", "No clue, check the board.",
            "Clean win.", "Don't buy one tonight, you'll regret it.", "Food sounds good.", "Nobody did.", "I think so?",
            "They got everything.", "Same seats.", "They're unbearable now.", "Ha, sure you did.", "Pure chaos.",
            "Yeah, it's over.", "Poor owners.", "Water. Need water.", "I think so.", "Agreed, best thing ever.",
            "Me too, honestly.", "Bet they will.",
            "It does.",
            "They were going crazy.",
            "Same.",
            "Not me, I'm saving.",
            "Me too, it's stuck.",
            "Loudest yet.",
            "Must feel amazing.",
            "Let him.",
            "Insane.",
            "Do it.",
            "They'll be fine.",
            "Mine too.",
            "It was fair, cope.",
            "Magic, probably.",
            "Agreed.",
        },
        follow = {
            "See you next event.", "Good times.", "Let's go.", "Ha, okay.", "Anyway.", "What a night.", "Alright, let's move.",
            "Same here.", "Haha.", "For real.", "I'll remember this.", "Next time, front row.", "Okay, food.", "Phew.",
            "Wild night.", "Peace.", "Later!", "Yep.", "Unreal.", "Good match.",
        },
    },
}

local function fill(text, rng)
    local team = TEAMS[rng:NextInteger(1, 2)]
    local other = team == "Alpha" and "Beta" or "Alpha"
    text = text:gsub("{quin}", function()
        return QUINS[rng:NextInteger(1, #QUINS)]
    end)
    text = text:gsub("{team}", team):gsub("{other}", other)
    text = text:gsub("{name}", function()
        return NAMES[rng:NextInteger(1, #NAMES)]
    end)
    text = text:gsub("{n}", function()
        return tostring(rng:NextInteger(2, 16) * (rng:NextNumber() < 0.5 and 1 or 5))
    end)
    return text
end

local function pick(list, rng)
    return list[rng:NextInteger(1, #list)]
end

-- A conversation for `phase` ("pre" / "live" / "post"): { {who = 1 | 2, text}, ... }
function CrowdChatter.conversation(phase, rng)
    local set = LINES[phase] or LINES.pre
    local turns = {
        { who = 1, text = fill(pick(set.open, rng), rng) },
        { who = 2, text = fill(pick(set.reply, rng), rng) },
    }
    if rng:NextNumber() < 0.55 then
        table.insert(turns, { who = 1, text = fill(pick(set.follow, rng), rng) })
        if rng:NextNumber() < 0.45 then
            table.insert(turns, { who = 2, text = fill(pick(set.reply, rng), rng) })
        end
    end
    return turns
end

-- Heading home together: an invitation, a yes (and sometimes a last word on the way)
local LEAVING = {
    open = {
        "That was a fun watch. Wanna grab a bite at the Argonia Trade Center?", "I'm starving. ATC food court?",
        "Okay, I've seen enough. Food?", "Let's beat the rush out.", "Wanna get noodles by the gate?",
        "I'm heading out. Coming?", "Night market's still open, let's go.", "Let's go before the trams fill up.",
        "My legs are done. Let's walk.", "Want to catch the replay at the ATC?", "Drinks? I'm buying.",
        "That's me for tonight. Walk with me?", "I need food after all that screaming.", "Let's go find {name}.",
        "The workshop's open late, wanna go see the Quins?", "Okay, we've earned dessert.",
        "If we leave now we get a table at the ATC.", "Come on, I know a shortcut out.",
        "Let's grab something before the next round.", "I promised {name} I'd meet them at the ATC.",
    },
    reply = {
        "Sure! Let's go, you lead the way.", "Yes, please. I'm so hungry.", "Okay, okay, right behind you.",
        "Only if you're paying.", "Go on, I'll follow.", "Finally. Let's go.", "Yeah, good call.",
        "Lead the way.", "I was about to say the same.", "Let's do it.", "Sure, the usual place?",
        "Wait for me!", "Deal. Last one there pays.", "Ooh, yes.", "Fine, but we come back next week.",
        "Perfect, let's move.", "You read my mind.", "Okay, after you.", "Ha, sure. Go.", "Let's go, let's go.",
    },
    follow = {
        "Watch the steps.", "This way, it's quicker.", "Did you see that last hit though?", "I'm getting the big bowl.",
        "Text {name}, tell them we're coming.", "Hold on, where's my ticket?", "Same time next week?",
        "Best night in ages.", "Stay close, it's packed.", "I'll tell you about my bet on the way.",
    },
}

function CrowdChatter.leaving(rng)
    local turns = {
        { who = 1, text = fill(pick(LEAVING.open, rng), rng) },
        { who = 2, text = fill(pick(LEAVING.reply, rng), rng) },
    }
    if rng:NextNumber() < 0.35 then
        table.insert(turns, { who = 1, text = fill(pick(LEAVING.follow, rng), rng) })
    end
    return turns
end

function CrowdChatter.count()
    local n = 0
    for _, set in pairs(LINES) do
        n += #set.open + #set.reply + #set.follow
    end
    return n
end

return CrowdChatter
