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

# Round 2: where the hit lands, and balance

Built 2026-10-29, same day. **Waiting on:** the owner's eye in a 1v1.

## What changed

| Where | Change |
|---|---|
| `AnimationConfig` Attacks | Each clip gets `height`: studs above the attacker's root where the limb lands. Punches 1.1, low kicks −2.8, high and wheel kicks 1.7. **These are estimates, not probed.** Measure them with the reach probe when a clip is replaced. |
| `States/FightState/Strike` | `zoneOf(hitModel)`: the attacker's root height plus the clip's `height`, compared with the target's root. At least `Hits_HeadAbove` (1.5) above it is the **head**, below `Hits_LegsBelow` (−1.0) is the **legs**, anything between is the **body**. A punch to someone standing lower becomes a head shot; a kick to someone standing higher takes the legs. A true whiff (nothing struck) costs the striker `Posture_WhiffCost` (6) balance. |
| `Modules/DamageModule` | `DamageModule.posture(model)` and `wearPosture(model, amount)`. Posture now **comes back**, `Posture_RecoverPerSecond` (6/s) after its last change. It is worked out when read (`PostureAt`), so no loop is needed. Before this it never recovered, so every Quin drifted toward a guard break over a match. A blow to the legs wears `Hits_LegsPosture` (1.6×) as much posture. `resolveOutcome` reads posture through the new function. `ImpactZone` is set just before `ImpactTime`. |
| `Modules/ProceduralCombatReactionController` | `triggerImpact(dir, mag, type, zone)`. **Head:** a new neck and head spring snaps the head away from the blow; the chest moves only 0.45×. **Body:** the chest folds over the blow instead of rocking back, and the hips dip (about 0.1 stud). **Legs:** the hips drop (about 0.25 stud) and the body tips over the struck side (roll 1.6×). No zone: the old reaction. |
| `CombatConfig` | `Hits_Zones`, `Hits_HeadAbove`, `Hits_LegsBelow`, `Hits_LegsPosture`, `Posture_RecoverPerSecond`, `Posture_WhiffCost`. `Hits_ClipBelowPosture` goes from 40 to **20** (see below). |

**Switches:**
- `Hits_Zones = false` brings back the single reaction for every blow.
- `Posture_RecoverPerSecond = 0` and `Posture_WhiffCost = 0` bring back the old posture.

## Measured (server, 80 s 16v16 unless noted)

| | Round 1 | Zones, head line 1.2 | Head line 1.5, kicks 1.7 | + clip at posture ≤ 20 |
|---|---|---|---|---|
| Hit / whiff / blocked / interrupted, % | 64 / 10 / 2 / 24 | 57 / 9 / 3 / 28 | 60 / 7 / 2 / 27 | 60 / 6 / 2 / 28 |
| Zones, head / body / legs | — | 364 / 258 / 180 | 342 / 330 / 181 | 361 / 355 / 178 |
| Hit clips per impact | 15% | 34% | 35% (180 of 336 from posture ≤ 40) | **21%** |
| Guard breaks | — | 32 | 45 | 32 |
| Mean posture | — | 83 | 82 | 84 |
| Server frame, mean ms | 23 (median) | 25.7 | 22.4 | 21.9 |

- **1v1 (60 s):** body 23, head 17, legs 6; posture never fell below 19, mean 82. No errors on the server or the client.
- **Impacts with no zone** (81–118 per run) come from blows that aren't Strike clips, such as slams. They react as before.
- **Hit clips:** recovering posture made worn Quins common in a 16v16 (ganged bodies sit at ≤ 40), so the clip rate doubled. With the threshold at 20 it is 21%: still above round 1's 15%, but each clip now comes from a heavy, crit, finisher or back hit, or a body close to a guard break.
- **Interrupted rose from 24% to about 28%.** It is likely the guard-break stuns. Watch it in step 4 (rules and openings).
- **Not measured:** the client springs, by number. The PCRC lives in the client's module copy, which an MCP call can't reach. Judge them by eye.

## For the owner to judge (1v1)

- A **head shot** (a high kick, or a punch from higher ground) snaps the head; the chest barely moves.
- A **body shot** folds the chest in over the blow.
- A **low kick** drops the hips and tips the body over the struck leg.
- A Quin that keeps whiffing gets easier to stagger.
- A Quin left alone for a few seconds gets its footing back.

## Still to do in step 3

- **Real base hit clips.** `HitLight` is still the braking-stop placeholder. The plan lists the owner's base clips (flinch, stagger, buckle, knockdown, launch).
- **Probe `height` per clip** with the reach probe, instead of the estimates.
- **The side of the hit** (left/right) is still read from the direction of the blow. The striking limb (`StrikeSide`) isn't used yet.
