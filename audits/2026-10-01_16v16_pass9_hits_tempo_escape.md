# Pass 9 (2026-10-01): hit detection, tempo, projectile jumps, escape and pursuit

Owner's notes after pass 8, plus the first part of plan phase 4. Studio backup:
`ServerStorage.backup_pre_16v16audit9_20261001`.

## Measured before

52 s of 16v16, one probe per swing (distance and outcome at the impact frame):

| Attacker > victim | Hit rate |
|---|---|
| male > male | 48% |
| male > female | 33% |
| female > male | 49% |
| female > female | 38% |

- 254 of 391 misses were thrown with the target 9+ studs away (average miss distance 14).
- Projectile jumps: 4. Mid-air clashes: 0. Block animation played 60 times (it works; it is
  0.45 s long).

## Causes and fixes

| Finding | Cause | Fix |
|---|---|---|
| Females harder to hit | `HitboxModule` tested part bounds; the skinned mesh part is a T-pose box (male 8.6 x 7.9 x 1.6, female 7.9 x 8.0 x 1.4), so reach depended on the target's build and facing | Every Quin is hit as the same body around its root (radius 1.5, half-height 3.5) |
| Swinging at air | Attack decisions ignored range; the step-in was capped to the gap in pass 6 but its speed stayed at the per-step value, so it often fell short | A strike is only thrown within `Combat_StrikeRange` (10); the step-in takes whatever speed closes the gap (ceiling 60) |
| Projectile jump rare | From a chase: first check 6-12 s in, then every 16-35 s, ~12% chance, 20-30 s cooldown, and chases are short now | First check ~2 s, every ~4 s, chance 0.30 x aggression + 0.20 x mobility, cooldown 14 s (`ProjectileJump_*`) |
| No mid-air clash | Only tested at the jumper's impact phase, against a target still airborne | Two jumpers within 40 studs and 12+ up clash in any phase; a Quin being jumped at can answer with its own jump (0.5 x aggression) |
| Fights look slow | Half the swings missed and reset the combo; attack cooldown 0.3-1.0 s; long, slow standoffs | Reach fix above; cooldown 0.2-0.7 s; Circling 30% shorter, pace from condition (spent = slow, aggressive or nimble = run strafe), and it ends early when the target turns its back |
| Chase triangles on the spot | Nothing made a Quin care about the enemy hunting it unless it was within 10 studs behind | Target utility for the enemy that is closing on and targeting this Quin (`Targeting_HuntedScore` x awareness) |
| Retreat is a lap around the fight | Destination re-chosen every 0.1 s; "to allies" meant the centroid of allies standing in the same brawl; cover searched within 35 studs, open ground 35 studs | An escape plan (one objective, one destination) held until reached / cut off / stuck / 4 s old; distances scale with the arena (150-stud run, 120-stud search on the 600 arena); allies nearer than 40 studs are not an escape; never a destination toward the pursuer; "got away" also when out of the pursuer's sight for 2.5 s |
| Hunter gives up after 0.9 s | Chase walked to the last seen point, looked around, went idle | Follows the memory track: believed position, then onward along the target's last heading in 45-stud legs while the track's confidence is worth it (persistent hunters follow a fainter trail); a committed hunter ignores passers-by unless they are after it |

## After (54 s of 16v16)

| Measure | Before | After |
|---|---|---|
| Hit rate m>m / m>f / f>m / f>f | 48 / 33 / 49 / 38% | 47 / 49 / 56 / 56% |
| Hits landed | 282 (52 s) | 621 (54 s) |
| Projectile jumps | 4 | 34 |
| Mid-air clashes | 0 | 3 |
| Guards held | — | 31 |
| Time in Circling (Quin-seconds) | 256 | 185 |
| Forced retreats: net distance | — | 35-150 studs |

No script errors.

## Not done / not verified

- Retreat was verified with forced retreats only (the decision layer rarely chooses it in the
  first minute); a forced retreat exits after 2.5 s because the decision does not want it. One
  7.6 s retreat changed objective 9 times (the pursuer kept cutting its route).
- Remaining misses are mostly mutual exchanges: the Quin that is hit first is pushed out of
  reach and its own swing still plays out.
- Still open from phase 4: jump validity checks on every jump, platforms as places to fight and
  flee to, believed positions inside the states.
