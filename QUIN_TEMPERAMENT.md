# Quin Temperament, Habits and Mood

Agreed with the owner on 2026-10-24. Code: `ReplicatedStorage/QuinCore/Modules/Temperament.lua`.

## The idea

Quins are creatures. Who a Quin is never changes; how it fights changes all the time, shaped by what happens to it and by its owner, like a sculptor working against the arena.

| Layer | How fast it moves | What moves it |
|---|---|---|
| **Mood** | Seconds to minutes; fades after the match | What is happening right now (CurrentConfidence) |
| **Habits** | Small steps every match, up *and* down | Fights, training, plans; habits are linked to each other |
| **Temperament** | Never | Sets where a Quin starts, what comes easily (toward its nature) and what takes work (away from it) |

## Temperament

- A name, never changed. It is chosen in the Hero Intro for a new player's first Quin; every other Quin gets one at random.
- **It is a leaning, not a rule.** There are no scripted moves and no designed matchups. Every Quin uses the same brain, and the temperament only tilts the habits it is born with.
- Every pair of temperaments must differ clearly on at least 3 habits; `Temperament.checkUnique()` checks this.

| Temperament | Leans high | Leans low |
|---|---|---|
| Hothead | Aggression (strongly), Focus, Risk | Awareness, Retreat |
| Jester | Dash, Mobility, Special | Focus, a little Protectiveness |
| Egoist | Confidence (strongly), Special | Protectiveness |
| Stoic | Confidence, Awareness | Dash, Risk |
| Wary | Retreat (strongly), Awareness, Mobility | Risk, Confidence |
| Hunter | Focus (strongly), Awareness | Protectiveness |
| Guardian | Protectiveness (strongly), Confidence | Mobility |
| Free Spirit | Mobility (strongly), Risk | Focus, Special, Protectiveness |
| Friendly | Protectiveness, Awareness | Aggression, Focus |
| Gambler | Risk (strongly), Special, Dash | Retreat |
| Opportunist | Awareness (strongly), Mobility | Aggression, Protectiveness |

There are 11. The 12th slot is left open for the owner. "Focus" is TargetPersistence.

## Habits: how they change

- **Only experience moves them.** Habits change after fights, training and plans. A Quin that sits unused, or waits to be sold, keeps its shape. **Nothing slides back over time.**
- **Judged against the match.** Each Quin is compared with the average of everyone in the same match:
  - knocked down more than most: Retreat up, Confidence and Aggression down;
  - more KOs than most: Confidence and Aggression up;
  - came through more gang-ups: Awareness up;
  - a win or a loss: Confidence up or down.

  Across a match the steps cancel out, so no habit creeps in one direction for every Quin.
- **Links:** a step in one habit pulls its partner the other way at 40%. The pairs are Aggression and Awareness, Retreat and Confidence, Protectiveness and Focus. There is no "max everything" Quin.
- **Nature resists:** inside its home range (±15 points of its nature) steps are free. Further away, a step away from its nature shrinks to 10% at 30 points out. Steps back toward its nature are always full.
- **1:3 protects the owner's work:** a step against what the owner is training (`TrainingFocus`) counts a third. Untrained habits move freely both ways.
- **Cap per session:** a habit moves at most 1.5 points in one session.
- **Stress:** on a losing streak of 3 or more, habits far from its nature ease back toward it a little. This comes only from hard fights, never from time.

## Measured (Edit-mode simulation, 2026-10-24)

- **300 random fights:** habits wander up to about 10 points and stay near the Quin's nature. No Quin turns into another temperament.
- **A 30-fight run of being knocked down more than everyone else:** a Hothead's Retreat goes 8 → 19 → 30 → 40. It moves faster at first and slower as it leaves its nature.
- **1:3:** a bad session took a trained habit down 0.2 points against 0.6 untrained.

## 16v16 check (2026-10-24: 8 matches, 256 Quins, 22-30 of each)

Damage dealt compared with the Quin's own team average (100% = typical); run-to-run noise is about ±10%.

| Guardian | Opportunist | Free Spirit | Wary | Friendly | Jester | Stoic | Hothead | Egoist | Gambler | Hunter |
|---|---|---|---|---|---|---|---|---|---|---|
| 110% | 107% | 105% | 104% | 103% | 101% | 100% | 97% | 95% | 93% | 91% |

- **Nothing is trash.** Hunter and Gambler were below average in *both* runs (about 7-9%), so they're the ones to watch.
- **Egoist** fights the most, retreats the least and dies first in both runs: overconfident. That's character, not weakness (95% damage).
- **Behaviour differences are subtle:** time in Fight/Chase/Circling is within a few % for all temperaments. The habits act as small biases in the decision system.
- **Found and fixed:** nothing ever recorded KOs, knockbacks or gang-ups for the habits. They are now hooked in DamageModule (Kill), KnockbackState (KnockedDown = any knockback, about 13 per Quin per match) and SituationAwareness (a surround of 1.5 s or more, survived). Match steps now judge counts relative to the average.

## Not built yet

- **Training sessions** (they set `TrainingFocus` and push habits): economy step 3, Workshop/Trainer dialogs.
- **Plans** shaping habits; **Bond** scaling the owner's influence against the arena's.
- The **stats panel arrows** (they read `HabitTrend`) and Low/Mid/High discovery bands.
- The **16v16 check:** arena Quins now get temperaments too. Measure each temperament's wins and score, and adjust any leaning that keeps losing.
