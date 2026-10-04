# Pass 46 (2026-10-05): the soft landing is for an unhurried straight drop

Owner: remove the soft landing during Recovery ("it looks funny"); keep it for a drop with no
movement across the ground: a Quin on high ground steps off the ledge in its own time, lands
soft, and walks on ("nonchalant ledge drop, aura farming").

## Rule now

- **Recovery never plays `LandingSoft`.** A front-side instant recovery picks `LandingHard` or
  `LandingSuperHero`; a stepping-stone hop lands with `LandingHard`.
- **A drop off a platform lands by its speed across the ground at touchdown**
  (`Landing_SoftMaxSpeed`, 8 studs/s): at or under it the soft landing, over it the hard one. A
  dive that arrives at 28-52 studs/s used to get the soft landing too.
- **A walked-off drop gets the soft landing** (GaitModule's ground contract): no jump, nothing
  threw it, at least 0.28 s of falling (about 8 studs), 8 studs/s or less across. It sets
  `LandingHoldUntil`, which the steer driver honours like its own landing hold.
- **Who walks off instead of diving** (Chase, target below): `CurrentConfidence` 0.7 or more,
  health over half, target at least 18 studs away, no social urgency or hunt, nothing behind it.
  It walks to the ledge at walking pace and over it ("Walking off the ledge").

A first version stepped off with a small hop; the hop carried 0.8 studs, did not clear the ledge,
and was retaken about 11 times per drop (121 ticks for 11 landings). Replaced by simply walking
off.

## Measured (16v16, 85 s)

| Landing clip | Where | Across at touchdown | Count |
|---|---|---|---|
| LandingSoft | Chase | 8 or less | 8 |
| LandingSoft | Fight | 8 or less | 2 |
| LandingSoft | Recovery | any | 0 |
| LandingHard | Chase | more than 8 | 5 |
| LandingHard | Recovery | any | 27 |
| LandingSuperHero | Recovery | any | 19 |

Casual walk-offs: 2 in 85 s. Strikes 639 hit, 44 whiff. No script errors.

## Not right yet

- **It does not stand through the landing and walk on.** 0.4 s after a soft landing started the
  Quins were moving at 14.6 studs/s on average, and 18.2 after 1.6 s: they run off. The landing
  hold is not holding them, or Chase's pace takes over at once. Not diagnosed.
- Only 2 casual walk-offs occurred; the rule is rare with the current confidence values.
- `GaitModule` was pushed without first checking Studio's copy against the last commit.

## Baseline for item 4 (under obstacles lower than a Quin)

Standing (not sliding) with a ceiling under 8.2 studs above the floor: 309 of 15718 samples
(1.97 %): 216 in Fight, 66 in Chase, 27 in Circling. None of them was tipped over at the time.
Nothing changed for this yet.
