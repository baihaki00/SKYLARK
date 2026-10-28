---
name: quin-temperament-habits
description: "CORE (owner loved it): Quin = mood + habits + temperament; built 2026-10-24 (Temperament.lua, QUIN_TEMPERAMENT.md); owner rejected scripted rules/matchups/neat formulas and time-based drift-back"
metadata:
  node_type: memory
  type: project
  originSessionId: 763b81d0-f578-4604-9efb-fa8705d651aa
  modified: 2026-10-23T15:49:39.554Z
---

On 2026-10-23 the owner said this is the first time they feel they "tied the knot" on how Quins behave. Keep it.

**Temperament: who the Quin is.**
- The named personality (Friendly, Jester, Egoist, ...). It is chosen only in the Hero Intro, for a new player's first Quin; every other Quin has it rolled.
- It practically never changes, and sets a home range for each habit.

**Habits: the 10 dimensions in PersonalitySystem.** Aggression, RiskTolerance, DashPreference, RetreatTendency, TargetPersistence, Protectiveness, MobilityPreference, SpecialPreference, Confidence, Awareness.
- **What drifts them** (about 0.01–0.03 per fight):
  - the plans the owner uses;
  - what happens in fights (a punished charge lowers Aggression and Confidence; a clutch win raises Confidence; being ganged up on raises Awareness);
  - training focus.
- **Bounded:** they stay near the temperament's range, and only stretch past it after a long time. "A disciplined Jester, never an Egoist."
- **Bond scales who sculpts:** with low Bond the fights shape the Quin; with high Bond the owner's plans and training do. Bond also = how well the Quin trusts and carries out the plan.
- **The stats panel shows drift arrows.** Habits are seen as Low/Mid/High bands, discovered over fights or by appraisal; appraisals go stale as habits drift.
- **Sales:** habits carry over, so the sculpting becomes resale value. Bond resets to 0.
- **Fair:** shaping changes style, never strength.

**Quirky labels** (Charger, Observer, Showoff, WallTapper, LoneWolf, Egoist-as-quirky ...) are long outdated per the owner. Removing them was ordered on 2026-10-23.

**Settled 2026-10-24 (built, commit 5de73b9; full spec D:\SKYLARK\SKYLARK LOCAL REPO\QUIN_TEMPERAMENT.md):**
- 3 layers: mood (in-match, fades) / habits (step every match, up AND down) / temperament (never changes).
- 11 temperaments are *leanings only*. The owner REJECTED per-temperament special rules, designed beats/loses matchups and "each owns exactly one habit" formulas as "hardcoded". Never reintroduce those.
- The owner also REJECTED a "drives / how it reacts" abstraction ("i dont get it", "i still want temperament"). Keep the named temperament.
- NO drift back with time: "people would wait weeks... just buy a new friendly". Only experience moves habits. Nature = resistance far from home, plus losing-streak stress.
- 1:3 = a step *against the owner's TrainingFocus* counts 1/3. The owner agreed with my point that a plain "down is 3x slower" would inflate everything. Cap 1.5 pts per session.
- Match steps are judged vs the match average: absolute counts made every Quin creep to Wary in simulation.
- The 12th temperament slot is open for the owner.
- The owner likes to discuss before I build ("dont take it up for me"): when they ask a design question, answer it and wait.

**16v16 audit 2026-10-24 (commit 92a8ac2, 8 matches):**
- Damage vs team average: 91% (Hunter) to 110% (Guardian). Noise is about ±10%; Hunter and Gambler were low in both runs.
- Behaviour shares (Fight/Chase/Circling) differ only a few %. The habits are small biases.
- Trap: nothing called PersonalitySystem.recordCombatOutcome until this pass. Kill/knockback/surround are now hooked.
- Collector recipe: a server task.spawn loops DevCommand "team:16", samples CollectionService "Quin" every 0.5 s and writes JSON to a Workspace attribute. A match lasts about 6-7 min. Kills are in `MatchKills`; `MatchDamageDealt` holds damage.

**How to apply:** all behaviour should come from the habits (shaped by temperament), never from Quirky labels.
**Why:** this is the creature vision ([[quin-creature-vision]]).

Related: [[skylark-economy-design]], [[skylark-mvp-target]]

**OPEN THREAD (owner 2026-10-24: "keep that thread open, focus on the core game loop first"):**
- Should temperaments be *visibly* different in the arena (habits weigh more in DecisionSystem), or stay subtle and just nudge Hunter and Gambler?
- The 12th temperament name is also still open.
- Come back to both after the core loop.
