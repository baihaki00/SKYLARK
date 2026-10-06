# The Quin: A Creature Made for Combat

Design doc. Written 2026-10-07 from the owner's direction, after the first Player Quin session. For discussion and correction before anything is built.

---

## 1. The vision

A Quin is not a character that decided to fight. It is **a living creature built for combat**. Fighting is its nature, the way the hunt is a predator's.

Throw Quins anywhere and they fight beautifully: on the ground, up walls, through the air, from the ground into the air and back. It looks like a fight scene, or one of those stickman fight animations, and nobody scripted it. It emerges because creatures like this meet.

The references are:
- Avatar: The Last Airbender;
- Naruto;
- Dragon Ball's Goku;
- One Punch Man season 1 (Madhouse: impact, timing, the contrast of slow and fast, easing);
- The Legend of Hei 2;
- Jhanzou's stickman fights.

What they share: it is high-speed, and it also has slow, deliberate, tense moments. There is aura and presence. It is emergent, believable, physically honest, never stiff, and the fighters look alive and smart.

**What the audience should feel**, in the owner's words:
- Watching: "these Quins fight so badass… it doesn't scream *look at my cool VFX*, it just works… who made this?"
- Playing: "playing as a Quin is so badass, it's butter smooth and yet has weight while being fast, it's not cheesy and not dry at all."

**What it is not:**
- ring-based combat ("inside this circle you may act": the generic boss-fight loop);
- VFX clutter standing in for substance;
- scripted set pieces.

**Later, on the same system:** weapons, then guns and new arenas. The design must let those be *additions*, not rewrites.

---

## 2. What "a creature made for combat" means

| Trait | What it means for a Quin |
|---|---|
| **Instinct first, thought on top** | Reflexes act before decisions: a slip, a flinch that turns into a counter, a twist in the air. Thinking adds reading, baiting, choosing angles. |
| **It perceives the world as a fight** | A wall is a launch point, a platform is high ground, a gap is a pounce, another Quin is a threat, a rival or prey. Nothing is neutral. |
| **The whole body is the weapon** | Running, landing and turning are already half a fighting move. No "walking mode" and "fighting mode": one creature, always ready. |
| **Space is all one place** | Ground, wall and air are just places to be. From anywhere, at any speed, it asks: *what can I reach, how, and how soon?* |
| **Combat feelings** | Alertness, thrill, caution, fury, exhaustion, the rush of a clean hit, respect for a dangerous opponent. Animal intensity, not human drama. They colour every choice. |
| **Alive in the stillness** | The stalk, the circling, the stare, the pause after a clean hit. A predator sizing up its opponent is as gripping as the strike. This is the aura. |
| **Honest body** | Fast and heavy at once. Momentum is never faked and never thrown away. |

**The player is one of them.** A player's Quin is the same creature with the same body, senses, reflex presentation and costs. Only the choice of what to do comes from a person instead of its own mind (Pass 73: `PilotedState`). So the player's feeling is a true reading of what it is like to be a Quin, and improving the body for the player improves every Quin.

---

## 3. What makes fights look choreographed

These come from studying why fight scenes and stickman animations are beautiful. They are the rules the system has to produce, not script.

1. **Nothing resets.** A dodge is already the start of the counter. A knockback carries into a wall, the wall becomes a kick-off, the kick-off becomes the next attack. No one stops to stand and decide.
2. **Every move is an answer.** Two fighters build the scene together: attack, read, evade, punish, change the angle. You can see each one *seeing* the other.
3. **The fight travels.** It moves from hand range into a dash, up a wall, into the air and back down, without switching modes. Range is a direction the fight moves in, not a category it sits in.
4. **The world is a partner.** Walls, edges, platforms and the dais get used, not only avoided.
5. **Rhythm.** A burst, a breath, a stare-down, an explosion. Contrast is what makes the fast parts hit.
6. **Physics stays honest,** so the wild moments feel real.

---

## 4. Where QuinCore is today

### Already pointing there

| Piece | What it gives |
|---|---|
| **Cognition** (`Gaze → Senses → Attention → Memory → Self / Environment / Situation`) | Perception as a creature has it. Sight is a cone with line of sight, where the head points. Attention keeps the few enemies that matter most (salience, limited capacity, tunnelling in a fight). Memory ages what it no longer sees. No "if within the arena, enemy". |
| **Personality** (9 dimensions), **DecisionSystem** | Individual temperament biasing choices. |
| **Social layer** (leaders, respect customs and duels on the dais, lulls, late-game pressure) | Stillness, ceremony, tension, aura. |
| **Traversal verbs** (jumps, projectile jumps and dives, wall runs and dash off the wall, air dash, slides, slide tackle and hurdle, intercepts, mid-air clash, slams, overwatch) | Most of the moves a creature needs in 3D space already exist. |
| **Body layers** (whole-body tilt and lean, square-up, wall hand, soft elbows, knee over toe) and the **strike markers** (Pass 72) | Presentation that reads as alive, and authored timing to read and exploit. |
| **One body for AI and player** (Pass 73) | The player's feel can now be used to judge and improve the creature. |

### Fighting against it

| Today | Effect |
|---|---|
| **Separate states with their own rules** (Chase, Fight, Circling, Retreat, ProjectileJump, WallRun, Airborne, MidAirClash…) | The fight *switches modes* instead of flowing. Ground and air live in different places in the code. |
| **Actions reset** | Approach → strike → recover → decide again. A strike starts from a planted stance, not from the run or dodge before it. |
| **Strikes are pulled at random** from a pool (punch or kick) | Not chosen as an *answer* to what the opponent is doing. |
| **Reactions are generic** (a random flinch) | A hit doesn't become the next beat. |
| **Ranges are fixed stud thresholds** in each state (strike ~10, combat ~8, chase 60, projectile jump 25–90) | The "ring" model, and it would have to be rewritten for every weapon. |
| **Heavy body at fighting speed.** Lateral grip 90 studs/s² is about 0.46 g (gravity here is Roblox's default, 196.2). | A sprint needs an ~18-stud radius to turn and ~0.7 s for 90°. Small repositioning, slipping to the rear and stepping off-line are expensive, so they can't dance. Weaker cornering than a human athlete (1–1.5 g). |
| **Costs live in states, not the body** (sprinting costs mana only in Chase) | Two Quins doing the same thing pay differently depending on the state they're in. |

---

## 5. The creature, in layers

One creature, from the world in to the body out. Each layer is shared by AI and player, except where marked.

```
            ┌───────────────────────────────────────────────┐
  WORLD ──▶ │ PERCEPTION   Cognition (exists): senses,      │
            │              attention, memory, situation     │
            ├───────────────────────────────────────────────┤
            │ REACH        what can I reach, how, how soon  │  new
            │              (3D: ground, wall, air)           │
            ├───────────────────────────────────────────────┤
            │ INSTINCT     reflexes to what's coming at me  │  new (from the guard rolls)
            ├───────────────────────────────────────────────┤
            │ MIND         chooses among the options        │  AI: DecisionSystem grown
            │              (player: the inputs choose)       │  Player: PilotedState
            ├───────────────────────────────────────────────┤
            │ DRIVES       combat feelings colour the mind  │  grown from personality
            │ RHYTHM       burst / breath / stare           │  grown from the social layer
            ├───────────────────────────────────────────────┤
            │ BODY         one honest, continuous body:     │  grown from Locomotion,
            │              locomotion, verbs, momentum,     │  strikes, states
            │              costs, presentation              │
            └───────────────────────────────────────────────┘
```

### 5.1 Body: honest, continuous, able to dance
- **Agility depends on speed.** At fighting speed (a step, a shuffle, a jog): near-instant direction changes, small steps, cuts. At a full sprint: a real carve and a real plant. Momentum is earned.
- **Grip fit for superhumans.** Lateral grip raised to about 1 g or more; the exact value is set by eye.
- **Air control, not lower gravity.** World gravity stays (it keeps ground fights snappy and landings heavy). Anime air time comes from moments: a hang at the apex of a jump or launch, controlled air moves that briefly override gravity (dive, air exchange, air dash), and full or stronger gravity on falls and slams. The wall-run arc already works this way (20 % gravity on the wall).
- **Intent shows in layers.** Head first, then chest, hips and feet. Velocity cannot change instantly, but the *acknowledgment* can. This is how it can be responsive and weighty at once.
- **Momentum hand-off.** Every action starts from the current motion and passes its motion to the next: a run into a strike, a dodge into a counter, a knockback into a wall into a rebound.
- **Costs belong to the body.** Stamina spent by actual effort (speed, strikes, dashes, jumps) and recovered when slow, in every state, for every Quin.

### 5.2 Reach: the creature's sense of distance
Replaces fixed stud thresholds and rings. For each relevant opponent, from where the Quin is now and how it is moving, it knows **which moves reach and how soon (time to contact)**:

| Band | Meaning |
|---|---|
| **Contact** | Inside strike reach right now: hands, knees, blocks. The close-quarters exchange. |
| **One beat** | One lunge, dash, slide or hop away (~0.3 s): the dash-kick, the step to the rear. |
| **Closing** | A few seconds of running or a jump: chase, cut-off, circling for an angle, taking height. |
| **Sighted** | Known (sight, sound, a teammate's call) but far: stalk, flank, ambush, overwatch. |
| **Aerial** | Someone's arc puts them in the air: intercept, dive, wait under the landing. |

- **Bands are computed in 3D.** A Quin on a wall or in the air has different reach than one on the ground.
- **Reach comes from the creature's own verbs and body**, so it changes when the body or the move set changes.
- **Weapons and guns later only add verbs with their own reach**; the bands adapt by themselves.
- **Bands decide which options are on the menu, not which one is picked.**

### 5.3 Instinct: reflexes
Fast reactions that don't wait for the mind's tick:
- slip or guard a strike it reads coming (the `Windup` marker is the tell);
- hop a sweep (the hurdle exists);
- twist in the air;
- break a fall (land on its feet, roll out, wall-splat into a kick-off);
- turn to a threat behind.

Instinct quality varies by Quin (personality, fatigue, feelings), so reflexes are fallible and readable. **For the player,** instinct is presentation only (flinches, head turns); the decision stays with the player.

### 5.4 Mind: choosing answers
- The mind picks from what Reach offers, against what Perception knows, as an **answer** to the opponent: read its intent, bait, punish, change the angle, take or deny height.
- **Strikes are chosen, not rolled:**
  - which limb and from which side, given the opponent's guard and position;
  - from the current motion (a running strike, an air strike, a wall kick);
  - chained when the last one landed or opened something.
- **Learning within a fight:** it notices an opponent's habits (always dodging left, always jumping) and exploits them.

### 5.5 Drives: combat feelings
A small set of feelings that rise and fall in a fight and colour the mind's choices and the body's presentation:
- **alertness / threat** (cornered, outnumbered, hunted);
- **confidence / momentum** (landing hits, winning exchanges);
- **thrill**, against a worthy opponent;
- **fury**, after being humiliated or after an ally falls;
- **caution / fear**, when hurt;
- **exhaustion**, from the body's stamina;
- **respect**, for a dangerous rival.

They are grown from personality (temperament) and the social layer (respect, rivals, leaders). The same Quin fights differently at 20 % health than at full, and against a rival than a stranger.

### 5.6 Rhythm
Something that senses the tempo of a fight (or the whole arena) and nudges it: after a long burst, a breath (circle, stare, reposition); after a long lull, someone explodes. **It sets tempo, never moves**, so it stays emergent. The social layer's lulls and late-game pressure are its first form.

### 5.7 Attention as "lock"
There is no lock-on today. A Quin's focus is its target (`TargetingModule`, held by commitment rules) and what Cognition's Attention keeps. Proposed:
- **"Lock" = attention, for everyone.** A Quin always has a focus, ranked by salience, and can only lock what it perceives.
- **The player's lock is the same thing**, with inputs:
  - a soft lock from camera and movement intent (Pass 73's strike soft lock is its seed);
  - an optional hard-lock key;
  - a flick to the most urgent threat (Attention already ranks them).

---

## 6. Principles (the rules every change is checked against)

1. **One creature.** AI and player share body, senses, reflex presentation, costs and moves; only the choice differs.
2. **Nothing scripted.** Beauty must come from the creature meeting the world and other creatures.
3. **No resets.** Every action starts from the current motion and leaves motion for the next.
4. **Every move is an answer** to something perceived.
5. **Space is continuous.** No ground-only or air-only logic where one model can serve both.
6. **Range is time, not studs.**
7. **The body never cheats and never lags.**
8. **Restraint.** No VFX or animation that doesn't carry meaning; impact comes from timing and contrast first.
9. **Everything switchable and measured.** The existing 16v16 the owner loves is the reference.

---

## 7. Protecting what already works

The current 16v16 is approved by the owner: compelling, surprising, fast and deliberate. Before changing the body or the mind:
1. **Baseline.** Record the numbers (hit / whiff / blocked / interrupted, time per state, fight length, reversals, deaths per minute) and **a few recorded fights in random arenas that the owner has watched and liked**.
2. **Every change behind a switch,** compared side by side with the baseline, by numbers *and* by the owner's eye.
3. **Better numbers don't win on their own.** A change that loses the tension, the slow moments or the surprises is switched off, even if it measures better.

---

## 8. How we'll know it's working

Hit rate isn't the measure; flow is:

| Measure | Meaning |
|---|---|
| **Action chains** | How often a Quin goes action → action without dropping back to a standing decision. |
| **Momentum kept** | Speed surviving each transition. |
| **Travel** | Range changes and ground ↔ wall ↔ air transitions per fight. |
| **World use** | Walls, edges, platforms and the dais used in a fight. |
| **Answers** | Share of strikes and moves that respond to the opponent's last action. |
| **Rhythm** | Alternation of bursts and breaths (activity over time). |
| **Player feel** | Input to visible acknowledgment; time to change direction at each speed. |

**The final judge:** the owner's eye on recorded fights and the owner's hands in Player Quin.

---

## 9. Roadmap (each step a pass or a few, measured, owner-reviewed)

| Phase | What | Why first |
|---|---|---|
| **0. Baseline** | Record the numbers and fights of today's 16v16 (section 7). Add the flow measures (section 8). | Nothing else can be judged without it. |
| **1. Body** | Speed-dependent agility, higher grip, stamina by effort for every Quin, intent shown in layers (head / chest / hips). | The creature can only be as alive as its body. Felt immediately in Player Quin, seen in every fight. |
| **2. Continuity** | Momentum hand-off: strikes from motion, dodge into counter, knockback into wall into rebound. Reactions that become beats. | "Nothing resets" is the biggest single difference between a game fight and a fight scene. |
| **3. Reach + attention** | The 3D time-to-contact bands replace fixed thresholds, Fight first, then the others. Attention-based lock, then the player's lock key. | Range as time is what lets the fight travel and what weapons will plug into. |
| **4. Instinct + answers** | A reflex layer reading `Windup` and arcs; strikes chosen as answers; learning within a fight. | Two creatures *seeing* each other is what makes it look choreographed. |
| **5. Drives + rhythm** | Combat feelings shaping choices and presentation; tempo sensing. | The slow, tense, aura-filled moments, by design rather than chance. |
| **6. Impact** | Timing and contrast at contact (hit-stop, anticipation, easing), driven by the markers. Restraint on VFX. | The Madhouse layer: last, because it amplifies whatever is underneath. |
| **Later** | Weapons, then guns and arenas, as new verbs with their own reach. | Additions, not rewrites, if phases 1–4 hold. |

States are not thrown away in one go. Each phase moves one piece of behaviour from "a state's rule" to "the creature's layer", behind a switch, and the old path stays until the new one is approved.

---

## 10. Owner's answers (2026-10-07)

1. **Cornering: steered by the mouse, Tales Runner style; fluid.**
   - Holding W, the Quin runs where the camera points, and moving the mouse turns the run continuously. The curve is as sharp as the mouse movement, limited by what the body can do at that speed.
   - "Superhuman grip" means how tight a curve can be at a given speed (sideways pull), never an instant 90° turn.
   - The AI steers by goals under the same body limits.
2. **Default pace when piloting: jog.** A calm stadium walk-on pace (arena, crowd, broadcast); Shift to run.
3. **Player instinct: only what the player presses.** No automatic guard, dodge or counter. Being hit still plays the hit reaction (the body taking the hit, not a choice).
4. **Feelings on show:** open. Should feelings be visible on the body (breathing, posture, stance, guarding a hurt side) or only in behaviour? Asked again with examples.
5. **First fight to judge phases 1–2 on: 1v1.**
