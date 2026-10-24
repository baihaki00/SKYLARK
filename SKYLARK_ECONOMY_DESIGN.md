# Skylark: Economy, Stats and Scoring (proposal, 2026-10-23)

Nothing here is decided until the owner picks. All numbers are starting points for tuning.

## The loop

Register a Quin → watch the fight → win or lose → earn SC from the score → repair at the Workshop and train at the Training Ground (both take Skylark time) → register again.

## 1. The terminal (ArenaTerminal)

Two options:

- **Spectate**
  - Pick a side: Alpha or Beta.
  - **Normal Seat: 100 SC.** A seat in that side's stands.
  - **VIP Seat: 300 SC.** The VIP box. Its terminal gives the drone cameras and the free-fly camera, but only while you're inside the box.
- **Register Quin**: works as it does now.

## 2. Skylark Coin (SC)

- **Earned only by playing:** event payouts and selling things. It can never be bought with Robux.
- **Robux buys only cosmetics:** wristband colours, room decor, emotes. Never stats, repairs, training or SC.
- **Starting balance: 2,500 SC, not 10,000.** 10,000 would make the first two weeks free, so the economy would mean nothing. 2,500 covers about two events with repairs and a little training, so money matters from day one.
- **Safety net:** a Quin can always enter a free "Open" event, and a basic self-repair kit is free once a Skylark day. A broke player is slowed down but never locked out.

### Where SC goes

| Sink | Cost |
|---|---|
| Event entry fee | 150 per Quin (featured events 300) |
| Repairs | 0–600 by damage taken. A Quin that got knocked out costs the most. |
| Training session | 100–400 by length (1 / 2 / 4 Skylark hours) |
| Seats | 100 normal / 300 VIP |
| Specialist work | Paid extras that change how a Quin is tuned (see 4), never raw power |

### Where SC comes from (paid when the winner is decided)

| Faucet | Amount |
|---|---|
| Taking part | 100 per Quin that fought |
| Win bonus | 400 per Quin on the winning side |
| Performance payout | Performance score × 0.5 (a 0–1000 score gives 0–500) |
| Survival bonus | 150 if the Quin was still standing at the end |

**Balance target:**
- An average Quin that loses, with average damage, comes out about −150 to −250 after the entry fee and repairs.
- An average win comes out about +400 to +600.
- A strong loss (high score) is about break-even.
- So a 50% player slowly gains, and a careless one slowly drains.
- Every week, check the server-wide total SC, and adjust the repair costs and payouts to keep it flat.

## 3. Performance score (0–1000 per Quin)

Calculated at WINNER_DETERMINATION. Every part is shown on the glass, so it is never a mystery.

| Part | Max | From |
|---|---|---|
| Damage dealt | 300 | share of the team's total damage |
| Hits landed / swings | 150 | accuracy |
| Knockouts + assists | 200 | 60 per KO, 25 per assist |
| Survival | 150 | time alive / match time |
| Damage avoided | 100 | dodges, blocks, guards |
| Team result | 100 | win 100, draw 50 |

## 4. Stats: an edge without grinding

The owner's rule: the player should feel they have an edge before the fight, without training more being the way to win, and with no pay to win.

### 4.1 Stats are a budget, not a ladder

- Each Quin has six stats from 15 to 100: Power, Speed, Endurance, Guard, Agility and Focus.
- **The total is capped**, for example 360 for a Standard Quin. Training moves points between stats; it does not add more.
- A maxed Quin is a specialist with clear weaknesses, never strictly better. Two players with 300 hours each can have very different Quins, and neither is simply "higher".
- **Gains shrink as a stat rises:** gain = base × (100 − stat) / 85. From 15 to 50 is quick; 50 to 80 is slow; 80 to 100 is rare.

### 4.2 Condition is the thing that moves every day

- **Condition (0–100%):**
  - It drops with damage and with training too hard.
  - The Workshop restores it, and this takes Skylark time.
  - Fighting at 60% condition is a real handicap.
- **Sharpness:**
  - It rises with recent fights and light training, and fades over idle days.
  - It is small (±5%), but players can read it and plan around it.
- **The real choice:** this round, or rest and repair first? That choice belongs to the owner, not to grinding.

### 4.3 Personality is fixed and has to be discovered

- Personality (Aggression, Mobility, Confidence and so on) is set at birth and never trains. It already exists in QuinInstance.
- An owner discovers it by watching. After N fights, the stats panel reveals each trait as a range ("Aggression: high").
- Knowing your Quin is knowledge you earn. It can't be bought.

### 4.4 Plans set before the event

At registration (or in the prep room before the anthem), choose:

- **Stance:** aggressive, balanced or defensive.
- **Target priority:** weakest, strongest, nearest, or protect partner.
- **Pair role (TEAM):** lead, support or roam.

These nudge the AI's decisions; they don't control it. A good plan for this Quin's personality against the visible opponents is the edge. A plan that fights the personality makes the Quin hesitate (the existing indecision behaviour).

### 4.5 Scouting

- The opponents' Quins are visible before the fight: type, title, battle record and revealed traits.
- The arena layout is shown at ARENA_GENERATION. Some Quins do better with obstacles, some in the open.

### 4.6 Unpredictability stays

- The fight is still the AI fighting itself, so better preparation raises the odds without fixing the result.
- **Target:** a well-prepared Quin wins about 60–65% against an equal Quin with a lazy plan, not 95%.
- Upsets happen, and they make good stories.

## 5. Security

- Everything is on the server: the wallet, payouts, stats, training timers and repairs. The client only asks.
- Every purchase and payout is checked server-side and rate-limited.
- Saved in DataStore with a session lock, so one account can't load the same data twice in two servers.
- Prices live in one server config module, never in client scripts.
- Training and repair run on server timestamps (the SST clock), so changing the client's clock does nothing.

## 6. Other owner asks in this batch

- **Quins down:** both of an owner's Quins down → they go back to their own room (not the gate), standing there as losers.
- **Prep room glass HUD:** the owner toggles it on and off. It shows:
  - the game stats (score, time, alive count);
  - their Quins' live stats (health, condition, live performance score);
  - the final score breakdown after WINNER_DETERMINATION.

## Build order

1. **Terminal and wallet:**
   - the terminal's Spectate / Register menu;
   - the SC wallet (server, DataStore);
   - Normal and VIP seats with side choice;
   - VIP-box-only drone and free-fly cameras;
   - defeated Quins back to their room.
2. **Scoring and payouts:** the performance score, payouts at WINNER_DETERMINATION, and the glass HUD with a toggle.
3. **Stats and care:**
   - stats with the budget and condition;
   - Workshop and Training Ground dialogs on the existing NPCs, in Skylark time.
4. **Plans and scouting:** stance and target plans at registration, opponent scouting, and personality reveal.
5. **Balance:** a week of real numbers, then tuning.

---

## Update (owner, 2026-10-23, second round)

### Owner decisions
- **Personality is chosen only once,** in the Hero Intro, for a brand-new player's first Quin. It uses named personalities: Friendly, Jester, Egoist, and so on.
  - After that, nobody chooses a personality.
  - Quins change hands: owner to owner, auction to player, player to auction, reseller to player.
- **Quins are scarce.** A brand-new Quin costs a lump sum, and owners can dispose of them.
- **A Quin's personality is discovered** through appraisal, or over a number of games. The owner likes both.
- **Prebooking** before an event shows a live Alpha / Beta board that anyone can inspect.

### Proposal: discovering personality
- **Hidden at first.** A bought Quin's personality shows as "???".
- **Revealed by fighting:** after 3, 6 and 10 fights, one more trait shows, then the named personality.
- **Revealed by appraisal:** a Quin Appraiser NPC reveals it now, for SC and Skylark time.
- **Why this works for the market:**
  - A Quin with its personality revealed sells for more.
  - Buying an unappraised Quin is a gamble, and sometimes a bargain.

### Proposal: what feels permanent without power creep
Progress buys **depth, reliability and value**, never raw damage.
1. **Bond (owner + Quin)**
   - It grows with every fight together and caps after a few weeks.
   - **It affects how well the Quin follows your plan:** less hesitation, faster switching between stances, and it holds the plan under pressure.
   - It gives zero damage. A new owner with a good plan can still beat a veteran with a bad one; the veteran's Quin just executes better.
   - **Bond doesn't transfer with a sale:** a sold Quin starts at Bond 0 with its new owner.
2. **Veteran traits**
   - Earned by what happened, not by grinding: surviving 1v3, 10 knockouts, a 5-win streak, losing an arm and fighting on.
   - **Each trait is a trade-off:**
     - "Scarred: +guard, −speed";
     - "Showboat: +crowd hype, takes risks";
     - "Survivor: fights smarter at low health, slower to engage."
   - They're permanent and travel with the Quin. Buyers can see them, so they add to the price.
3. **Signature techniques**
   - Unlocked at the Training Ground after a lot of training: a special counter, a finisher, a dash pattern.
   - A Quin can equip a limited number (for example 2). Unlocking more gives variety, not power.
4. **History**
   - Battle record, titles, rivalries, past owners and the Hall of Fame stay on the Quin forever.
   - A Quin with a famous history is worth more at auction. That's the long-term payoff: the Quin becomes valuable, not stronger.

### Proposal: prebooking rules (a reveal-order game)
- **The board shows:**
  - Quin type and title;
  - battle record;
  - **revealed** traits only;
  - condition as a band (fresh / worn / battered).
- **The board never shows** the owner's plan (stance, targets, role). The plan stays secret until the fight.
- **Early booking is a risk, so it pays a little:** a discount that shrinks the later you book (−30% entry fee at T−30 min, full price in the last 10 min) and first pick of side.
- **Plans can change until the lock** at T−5 min, so early bookers can still counter what they see.
- **Cancelling** a prebook costs 25% of the fee, so bluff-booking has a cost.
- **Stacking guard:** a side closes when it reaches 16. If one side's average condition and record is far above the other's, its booking price goes up a little.

### Owner decisions, round 3 (2026-10-23)
- **Bond: yes.** Bond drives how much the Quin trusts your plan, and how well it carries it out in the arena.
- **Signature techniques: parked.** Anything that needs animations waits; the focus now is logic.
- **Side picking:** the owner asked what keeps it fair. Proposed: pick with a guard, with NPQs as the balancer (below).

### Proposal: choosing sides
- **You pick a side when you book.** Your two Quins are always on the same side, and friends can join each other.
- **Strength Index:** a side's strength is worked out only from what the board shows (record, condition band, revealed traits, Bond band).
  - If one side gets ahead by more than ~15%, that side only takes new Quins below its average strength until the other side catches up.
  - Above that, you're offered the other side (or you wait).
- **NPQs balance the rest:**
  - Empty seats at the lock are filled by NPQs, and the weaker side gets the stronger NPQs.
  - Players never see this happen, so a stacked side can't be guaranteed.
- **Why:**
  - Choosing a side is part of the strategy: who you join, and who you face.
  - But nobody can stack a sure win.
  - The NPQ fill quietly evens out whatever imbalance is left.

### Owner decisions, round 4 (2026-10-23)
- **"Quirky" is outdated.** The owner moved past the Quirky labels (Charger, Observer, Showoff...) long ago, but they're still in the code (PersonalitySystem.assignInitialQuirky, RetreatTacticsModule and others).
- **Traits must change.** The 10 personality dimensions must NOT be fixed: Quins are creatures, and the owner shapes them like a sculptor.

### Proposal: temperament + habits (a living personality)
- **Temperament (born):**
  - the named personality (Friendly, Jester, Egoist...), chosen in the Hero Intro or rolled;
  - it sets a home range for each dimension;
  - it practically never changes; it's who the creature is.
- **Habits (the 10 dimensions):** they drift with experience, inside the temperament's range (with some stretch past it after a long time).
  - **Plans you choose:** fighting defensively fight after fight raises Retreat and Protectiveness a little each time.
  - **What happens in the fight:**
    - a reckless charge that gets punished lowers Aggression and Confidence;
    - a clutch win raises Confidence;
    - being ganged up on raises Awareness.
  - **Training focus:** sparring drills nudge Aggression and Target Persistence; evasion drills nudge Mobility and Dash.
  - **Bond scales your influence:**
    - With low Bond, the fights shape the Quin more than you do.
    - With high Bond, your plans and training shape it more.
- **Slow and visible:** about 0.01–0.03 per fight. The stats panel shows arrows (↑ Aggression this week), so owners can watch their sculpting work.
- **Fair:** shaping changes style, not strength. Every shape has counters.
- **Market:**
  - A shaped Quin keeps its habits when it's sold, so a famous owner's craft becomes value.
  - The new owner sees the last appraisal (with its date). Habits keep drifting, so knowledge goes stale and has to be renewed by watching or appraising.

## Step 2 built (2026-10-24): entry, score, payouts, results

The owner's rule: taking part costs something, and an early double loss should come out at about −100 SC. Audience 16–30, so they can handle a loss, as long as the result screen shows exactly why. The start balance stays at 2,500.

- **Entry: 100 SC per Quin**, charged when the Quin is seated for a round, not at registration: you pay only for rounds your Quins fight. A Quin you can't pay for sits that round out (with a notice). A round stopped before its winner refunds the entry.
- **Performance score 0–1000** (SkylarkPayouts), counted live (the Quin's MatchScore attribute):
  - Damage 350: twice the match's average or more scores it all.
  - KOs 200: 3 or more scores it all.
  - Survival 200: share of the match still standing.
  - Efficiency 150: dealt / (dealt + taken).
  - Result 100: its side won.
- **Pay per Quin:** 30 for taking part + score × 0.2 + 150 for a win + 50 if still standing at the end.
- **Results:** a results card for each owner when the winner is decided (each Quin's score part by part, pay, entry, net, balance), plus the STATS board on the owner's prep room glass: live health and score during the fight, results after. HIDE / STATS toggles it.

| 2 Quins, entry 200 | Back | Net |
|---|---|---|
| Both knocked out early (tested: scores 64 and 119) | ~95 | **~−105** |
| Average loss (~465 each) | ~246 | ~+46 |
| Average win (~565 each, one still standing) | ~636 | ~+436 |
| Strong win (tested: 660 and 586, both standing) | 709 | +509 |

An average loss is slightly positive *before* step 3's drains (repairs after damage, maintenance, training). With those, an average loss should come out slightly negative and an average win clearly positive. Re-check this at step 5.

## Step 3 built (2026-10-24): condition, rest, Workshop, Trainer, Specialist

Owner: "yes condition handicap, stats later, timer first, go". Code: `ServerScriptService/QuinCare`
(server), `StarterPlayerScripts/QuinCareClient` (the dialog), remote `ArenaNetwork.QuinCare`.
All timers run on Skylark time (1 Skylark hour = 20 real minutes).

| What | Number |
|---|---|
| Condition after a match | -25 x (damage taken / max health), -15 more if knocked out |
| Worn handicap | max health and energy x (0.75 + 0.25 x condition): 60% fights at 90% |
| Free rest | +5% a Skylark hour (also offline, worked out when next looked at) |
| Workshop repair | 2 SC a point, back to 100% after 30 Skylark min (10 real min) |
| Trainer Short / Normal / Long | 1h 100 SC +1 / 2h 180 SC +2 / 4h 320 SC +4 habit points, before Bond and nature resistance |
| Training wear | -5% condition a session |
| Bond (0-100) | +3 a session, +1 a fight; training counts x (0.6 + 0.4 x Bond/100) |
| Specialist appraisal | 150 SC: each habit Low (<40) / Mid / High (>65), with drift arrows; true that day |
| Free reveal | from 10 fights the 3 most extreme habits show, one more every 5 fights |

A Quin in the Workshop or training is busy: it sits the round out with a notice and pays no entry.
The terminal roster, the glass board and the results card show condition.

Tested in Play: the three dialogs, repair charge and guards (not near, already full, busy),
a Long session (Aggression 58 -> 60 at Bond 0, Awareness -1 by its link, -5% condition, Bond +3),
appraisal bands, and a 4v4 (knocked-out winner 100% -> 60%, standing winner 100% -> 84%).
Not yet seen in Play: a worn Quin's lower max health in a match, and the busy skip at seating.
Studio test hook: workspace attribute `QuinCareDev` = `cond <slot> <value>` | `finish <slot>` |
`dump` (reply in `QuinCareDevResult`). MCP code runs in its own VM: requiring QuinCare there
makes a second copy that takes over the remote, so drive tests through the hook or the client.

Thought for balance (step 5): a Long session gives about +2 at Bond 0 for 320 SC, which is slow
on purpose (the owner's "5 points over 2 days"), but may feel thin; Bond lifts it to +4.
