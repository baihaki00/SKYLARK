# Phases 2–6: Continuity, reach, instinct, drives and rhythm, impact

The first pass of phases 2 to 6 of [QUIN_CREATURE_DESIGN.md](../QUIN_CREATURE_DESIGN.md):
- the owner asked for every phase to be done overnight, and will judge the 1v1 after;
- every piece is shared by AI and player Quins (except reflexes, which are AI-only by the owner's rule: a player's Quin only does what is pressed);
- every piece has a CombatConfig switch;
- in Studio, a Workspace attribute `Ablate_<Layer>` turns a layer off live (Drives, Rhythm, HitStop, Instinct, Reach) for A/B by eye or probe.

## Phase 2: continuity (nothing resets)

| Piece | What |
|---|---|
| **Arrive hot** (`Flow_ArriveHot`) | FightState approaches at the fastest speed it can still brake from by striking range: √(2 · braking · gap) + 6. It used to slow down from far out (8 + 4 × gap). Moving fast, the strike range grows by speed × 0.1 s (at most 4 studs): the lunge covers the extra. |
| **Dodge into counter** (`Flow_DodgeCounter`) | A dodge slips back and to a side about half the time (more for agile Quins) and opens a counter window (`CounterUntil`, 0.7 s): the next strike comes without the cooldown. Blocks already had `ImmediateCounter`. |
| **Wall tech** (`Flow_WallTech`) | A thrown Quin about to hit a wall plants its feet and kicks off back at its attacker (55 studs/s, 28 up, the air-dash pose, the dash sound, a shockwave at the wall) instead of slamming in and bouncing. AI Quins by chance (0.35 × (0.5 + mobility)), and never under 25 % health. A player's Quin only when jump was pressed in the 0.4 s before (`PilotInput.pressedRecently`). The kick-off counts as a wall kick, so an air dash at the attacker may follow (`AirDash.noteWallKick`). |

**Not done:** strikes thrown *from* a run. The strike clips are standing punches and kicks; at a sprint the feet glided, so strikes plant (an earlier pass). That needs running-strike clips.

## Phase 3: reach (range is time)

| Piece | What |
|---|---|
| **`Modules/Reach`** | For a Quin and its target: how soon it can be in contact, from where both are and how both move. Bands: contact (inside strike reach), beat (one burst, a lunge, dash or slide, within 0.4 s), closing (a run within 3 s), sighted (beyond), aerial (the target up out of jump reach). A target running away as fast as the Quin can run is never "closing". Published as `ReachBand`. |
| **Fight ↔ Chase by time** (`Reach_Enabled`) | A fight becomes a chase when contact is more than 0.4 s of running away and the gap is over 1.2 × CombatRange (a hard cap of 4 × CombatRange either way). It used to be over 2.5 × CombatRange in studs. A chase becomes a fight within 0.15 s of contact (up to 3 × CombatRange), as well as within 1.5 × CombatRange as before. |
| **The player's lock** (T / G) | Lock = attention (design doc 5.7). T locks the nearest threat or lets go; G moves the lock to the next. Locked, the Quin is engaged with that enemy at any range unless running, and its strikes go at it. The lock lets go at 120 studs or on the enemy's death. A small white diamond marks the locked enemy for the player. |

**Not done:** the other states' thresholds (dash distances, Circling, Retreat) are still in studs.

## Phase 4: instinct and answers

| Piece | What |
|---|---|
| **The tell** | Every strike publishes `StrikeTellAt` (the owner's Windup marker; StrikeMarkers now reads it) and `StrikeLow` (a low kick). |
| **`Modules/Instinct`** (`Instinct_Enabled`, AI only) | A Server loop, every frame. A Quin a strike is aimed at, not itself mid-strike, sees it at the tell, and after its reaction time answers it. Reaction time: 0.16 s × (1.3 − 0.6 × awareness), +0.08 s when tired. Answers: guard (0.3 × (0.5 + defense) × the drives' guard bias); slip (0.15 × (0.5 + mobility), back and to a side, opening the counter window); hop a low kick (0.5 × (0.5 + mobility)); or nothing. With it on, the old guard rolls (FightState `tryRaiseGuard`, the decideAction block/dodge branch) step aside. |
| **Answers** (`Answers_Enabled`) | The strike is chosen, not rolled at 50/50: a punch to punish an opponent whose strike just whiffed; a kick at a guard; a kick at the edge of reach; and away from whatever kind this opponent has been stopping. Each Quin remembers, per opponent, how its punches and kicks fared. Published as `StrikeAnswer`. |

**Finding:** most strikes in a close fight land on a defender that is itself mid-strike (trades). A Quin committed to its own swing cannot guard until its Recover, so the reflexes fire on fewer than half the strikes.

## Phase 5: drives and rhythm

| Piece | What |
|---|---|
| **`Modules/Drives`** (`Drives_Enabled`) | Five feelings, 0..1. Confidence: landing and stopping strikes, minus hits taken. Fury: heavy hits, knockdowns, an ally falling within 60 studs. Caution: health lost, a run of hits. Thrill: a close, even exchange. Exhaustion: mana. They relax back on their own. They shade the cooldown between strikes (an aggression multiplier 0.6–1.6) and the reflexes' readiness to guard. The strongest is published as `Drive`. Showing them on the body: later (owner). |
| **`Modules/Rhythm`** (`Rhythm_Enabled`) | A burst (5 strikes between the two within 3 s) that stops opens a breath of 1.2–2.5 s: the cooldown × 1.8, and a 35 % chance it becomes a stand-off (Circling). A circling stand-off that goes quiet for 4 s breaks: someone explodes into it (a dash in, or a heavy strike). The fight's own lull check never fired: the quiet moments happen while circling. |

## Phase 6: impact

| Piece | What |
|---|---|
| **`Modules/HitStop`** (`Impact_HitStop`) | A landed strike holds both bodies' action clips for 0.045 s + 0.06 s × weight: a punch about 0.05 s, a kick about 0.08 s, a finisher or crit about 0.1 s. Then they run on. The attacker's free time moves by the same hold, so it is still released at its clip's Recover. No effects. |

## Measured (flow probe, everything on; baseline in [phase0](2026-10-07_phase0_baseline.md))

| Measure | Baseline 1v1 (mean of 3) | Final 1v1 (a / b / c) | Baseline 16v16 | Final 16v16 |
|---|---|---|---|---|
| Strikes per Quin-minute | 15.9 | 19.3 / 19.1 / 22.7 | 13.9 | 15.4 |
| Hit / whiff / blocked / interrupted % | 66.8 / 7 / 4.6 / 21.5 | 76.2 / 1.6 / 0.8 / 21.1, 67.6 / 1.4 / 0.7 / 30.1, 69 / 3.2 / 4.5 / 23.2 | 68 / 7.1 / 5 / 19.7 | 66.6 / 6.8 / 3.8 / 22.6 |
| Engaged % / standing to decide % | 53.4 / 8.5 | 50.2 / 7.6, 61.5 / 8.7, 63.1 / 9.5 | 47.3 / 9.5 | 47.7 / 11.6 |
| Contact / far % | 29 / 32 | 33.9 / 24.4, 36.3 / 26.3, 45.4 / 25.6 | 21.8 / 27.4 | 24.6 / 27.3 |
| **Speed kept Chase → Fight** | 0.36 | **0.50 / 0.50 / 0.51** | 0.37 | **0.51** |
| Strike start speed (median) | 10 | 11 / 5 / 7 | 11 | 15 |
| Answers % | 34.4 | 41.4 / 43.0 / 36.3 | 40.7 | 41.9 |
| In the air % / high ground % | 10.8 / 2.8 | 15 / 8.9, 10.2 / 0.4, 12.5 / 12.4 | 11.3 / 14.6 | 12.2 / 11 |
| Rhythm: swings per minute / CV | 13.9 / 0.70 | 12.5 / 0.63, 11.2 / 0.66, 12.5 / 0.56 | 10.9 / 0.26 | 12.2 / 0.27 |
| Knockdowns per Quin-minute | 3.5 | 2.88 / 3.91 / 2.06 | 2.67 | 3.40 |
| Server frame, median ms | 4 | 4 | 5.9 | 4.9 |

**The new layers in the final 16v16** (240 s, 32 Quins):

| Layer | Count |
|---|---|
| Counters out of a dodge or slip | 75 |
| Wall techs | 12 |
| Breaths | 136 |
| Explosions out of a stand-off | 4 |
| Reflexes | saw 541 strikes: guard 212, slip 35, hop 19, nothing 275 |
| Strike choices | reach 923, learned 735, guard 75, punish 14 |
| Strongest feeling | caution most of the time (many Quins are hurt in a long 16v16); fury and confidence next |

Per 1v1: 14–18 breaths, 1–4 counters, 14–26 strikes seen by the reflexes. Most 1v1 strikes are trades, where the defender is mid-strike and cannot answer.

**Errors:** none.

### A bug found and fixed on the way (in this pass)

The first full runs of phases 2–6 showed **10.7 strikes per Quin-minute in the 16v16**. Switching layers off one by one in Studio (`Ablate_*`, 180 s each) gave:

| Off | Strikes per Quin-minute |
|---|---|
| Drives + Rhythm | 10.3 |
| Instinct | 10.9 |
| HitStop | 16.4 |

So the cost was the hit-stop, but not its 0.05–0.1 s pause. When the hit-stop moved the attacker's finish time on, the one delayed check that clears `Attacking` (tick() ≥ attackFinishTime, at the original finish) failed, and **`Attacking` stayed true after every landed hit** until the next strike. The probe then missed strikes, and defenders read the attacker as still swinging.

**Fix:** the clear now waits out any extension, and checks it is still the same strike (`AttackWindupUntil`). The numbers above are after the fix.

**Also tuned after the first runs:**
- Thrill rose on every trade and sat near 1 in a 1v1: now 0.05 per trade, decaying at 0.15/s.
- Caution held back too hard: `CautionHold` 0.6 → 0.35.
- A breath multiplied the cooldown by 2.5 → 1.8.
- Lulls are now also sensed while circling (they never fired from the fight's own check).

## Reading

- **Continuity shows where intended.** Entering a fight keeps half the chase's speed (was a third), and strikes start faster in the 16v16 (15 vs 11).
- **1v1 whiffs fell from 7 % to about 2 %:** arriving hot, reach-by-time and chosen strikes.
- **The pace is close to the 16v16 the owner likes.** About 10 % more strikes, the same hit rate, the same overall rhythm (CV 0.27), a little more swing.
- **1v1s are denser than the baseline** (about 20 vs 16 strikes per Quin-minute). Breaths do happen (14–18 a run). If the owner finds them too busy, the levers are `Rhythm_BreathCooldown` and `Rhythm_BurstStrikes`, or `Body_Agile` (the agile body is what brought fighters together).

## Not checked

- **By eye (owner, the 1v1 first):** everything here. Especially:
  - wall techs and the dash that may follow;
  - slips and counters;
  - hops over low kicks;
  - hit-stop timing (0.05–0.1 s);
  - breaths and explosions.
- **The player's wall tech** (jump just before hitting a wall). The code path is there; it was not exercised in a test.
- **On the client:** the hit-stop is an animation-speed change made on the server, which replicates; whether it reads the same on every client was not checked.
