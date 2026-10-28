# Fight Programme step 3: hits (round 1)

Step 3 of [FIGHT_PROGRAMME.md](../FIGHT_PROGRAMME.md), started 2026-10-29 in Studio (QUIN_COMBATV4). This round answers the owner's report: "hits animation plays too much... both of them playing hits animation while barely any convincing strikes has occurred". **Still waiting on:** the owner's eye.

## What was wrong

1. **A hit didn't need the limb to arrive.**
   - A strike scored on any body inside a box in front of the attacker that reaches about 6.5 studs (`HitboxModule.castInFront`).
   - A punch's fist only gets 4.3 studs ahead of the root (step 1's reach probe). A punch thrown from 6 studs stopped a stud short and still counted as a hit.
2. **Every hit played a full-body hit clip** on the victim (`DamageModule.apply`), even the lightest jab, on top of the procedural flinch the client already draws (`ImpactTime`, PCRC). In a trade both Quins played one.
3. **The light hit clip is a placeholder.** `Reactions.HitLight` borrows `Movement.BrakingStop`, so a jab made the victim do a braking stop. That is why it looked so unnatural.
4. **Found while measuring: step 2's look-ahead cut strikes short.**
   - Step 2 round 2 judged a closing body's gap 0.1 s ahead.
   - At a strike's 60 studs/s lunge that is 6 studs, so `Spacing` stopped the step-in about 6 studs out.
   - The old box hid this; with the contact check it showed as 25% whiffs, nearly all from 5.7–6.6 studs.

## What changed

| Where | Change |
|---|---|
| `States/FightState/Strike` | A body in the box counts only if it is within the clip's `reach` + the body's radius (0.72) + `Hits_ContactSlack` (0.6), measured flat from root to root. Clips without `reach` are checked as before. `damageInfo.isFinisher` is passed on. |
| `Modules/DamageModule` | The full-body hit clip plays only for a blow that means something: heavy, crit, finisher, from behind, or a victim at posture 40 or below. A light hit is the procedural flinch and the short slide back, as before. Damage, stun, hit-stop and knockback are unchanged. |
| `Modules/Spacing` | The look-ahead takes at most `Spacing_LookAheadMax` (0.75 studs) off the gap. |
| `CombatConfig` | `Hits_ContactCheck`, `Hits_ContactSlack`, `Hits_ClipOnLight`, `Hits_ClipBelowPosture`, `Spacing_LookAheadMax`. |

**Switches:**
- `Hits_ClipOnLight = true` brings back a clip on every hit.
- `Hits_ContactCheck = false` goes back to the box alone.

## Measured (server)

| | 1v1, contact check, old look-ahead | 1v1, both fixes | 16v16, both fixes | Step 1 16v16 |
|---|---|---|---|---|
| Strikes | 110 | 61 | 1066 | — |
| Hit / whiff / blocked / interrupted, % | 55 / 25 / 1 / 20 | 56 / 10 / 7 / 28 | 64 / 10 / 2 / 24 | 65 / 9 / 3 / 24 |
| Full-body hit clips per landed hit | 4 / 60 | 4 / 34 | 103 / 685 (15%) | every hit |
| Roots under 3 studs, % of close frames | — | 1.5 | — | (1v1 step 1: 2.0) |
| Server frame, median ms | — | — | 23 (raw Heartbeat) | (step 2: 24, same method) |

- 90 s per 1v1 run, 80 s for the 16v16. The 1v1s are single runs. No errors in the console.
- **Remaining 1v1 whiffs:** 4 of the 6 were thrown from 9–14 studs. That's the mind choosing to strike from too far, which is step 6.

## For the owner to judge (1v1)

- A jab that lands should read as a jab: the victim flinches and gives a little ground, but no longer plays a whole clip.
- The big reaction should come only with heavy kicks, crits, finishers, hits from behind, or a Quin that has been worn down.
- Strikes that visibly stop short should now count as misses.

## Still to do in step 3

- **Real base hit clips.** `HitLight` is still the braking-stop placeholder; it now plays only on worn-down bodies and crits. The plan lists the owner's base clips (flinch, stagger, buckle, knockdown, launch) for this step.
- **Where the hit lands:** a head / body / legs zone and side passed into `DamageModule.apply` and `PCRC.triggerImpact`, so the flinch bends where the blow lands.
- **Balance:** let whiffs and bad footing wear `Posture`, not only hits.
