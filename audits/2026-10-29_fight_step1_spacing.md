# Fight Programme step 1: spacing

Step 1 of [FIGHT_PROGRAMME.md](../FIGHT_PROGRAMME.md), built and measured 2026-10-29 in Studio (QUIN_COMBATV4). It is compared against [the step 0 baseline](2026-10-29_fight_step0_baseline.md). **Still waiting on:** the owner's eye in a 1v1.

## What was wrong

- **What moved the bodies together:** a new probe, [scripts/overlap_cause_probe.lua](../scripts/overlap_cause_probe.lua), recorded it on the baseline 16v16 (150 s, 344 episodes of roots under 3 studs).
  - **No push was moving them in 53% of the overlap time.** The Humanoid's own walk kept carrying the body on after a step-in, mostly attacker into attacker.
  - The strike step-in itself caused 29%.
  - Being shoved caused 6%, and the body's own slides 4%.
  - Mid-air clashes made up 8%, where contact is intended.
- **How far each clip reaches:** a second probe, [scripts/strike_reach_probe_client.lua](../scripts/strike_reach_probe_client.lua), measured how far ahead of the root each clip's striking limb gets, from HitStart to HitEnd:
  - punches: 4.3 studs;
  - low kicks: 5.1;
  - high kicks and wheel kicks: 5.25.

  Every strike used to stop at 4.8 studs, so punches stopped short and their step-in finished the job by walking in.
- **Real collision is already on.** Every Quin has a `CollisionBody` (2.4 × 6.8 × 1.8, CanCollide). It is what stops bodies at about 1.9–2.3 studs. That is inside each other on the drawn mesh, but never through. A "real collision" switch would change nothing, so it was dropped.

## What changed (all in QuinCore, no refactor)

| Where | Change |
|---|---|
| `Modules/Spacing` (new) | Every frame, for every two Quins on one ground level:<ul><li>neither walks or is pushed closer than `Spacing_BodyGap` (3.0) to the other;</li><li>a striking Quin stops at its strike's own gap toward its target;</li><li>bodies already inside each other (under 2.5) are eased apart.</li></ul>Only the closing part of the motion is removed; sideways motion goes on. It works as a 0.06 s `ImpulseModule` request (tag `space`, Reaction priority) that is refreshed only while the body still closes. Left alone: air, clash, knockback, recovery, wall run, re-entry, specials, death, a player's Quin, and `SpacingExempt` (for grabs later). |
| `Modules/ImpulseModule` | `cancelToward(model, dir, minDot, keepTag)` stops the body's own pushes toward the other body. A knockback is never stopped. |
| `AnimationConfig` Attacks | `reach` on all 8 clips (4.3 / 5.1 / 5.25), with a note to re-measure when a clip is replaced. |
| `States/FightState/Strike` | The step-in stops at `Spacing.strikeStopGap(reach)` = reach + 0.72 (torso radius) − 0.25 (limb depth) = 4.77 for punches, 5.57 for low kicks, 5.72 for high and wheel kicks. It is published as `StrikeStopGap`. The jab hitbox reaches 6.5, so every gap is inside it. |
| `States/FightState` | The riposte lunge after a block gets a room limit (it had none). |
| `CombatConfig` | `Spacing_Enabled`, `Spacing_BodyGap`, `Spacing_ApartSlack`, `Spacing_TargetRadius`, `Spacing_ContactDepth`. |
| `ServerScriptService.Server` | `Spacing.start()` next to `Instinct.start()`. |

**Switches:**
- `CombatConfig.Spacing_Enabled = false` turns it off.
- In Studio, the Workspace attribute `Ablate_Spacing = true` turns it off live, for A/B.

## Results

| Measure | 1v1 baseline (mean of 3) | 1v1 step 1 | 16v16 baseline | 16v16 step 1 |
|---|---|---|---|---|
| **Roots under 3 studs**, % of engaged time | 8.9 | **2.0** | 9.0 | **3.6** |
| Roots under 4.8 studs, % | 31.5 | 21.0 | 27.7 | 17.1 |
| **Drawn torsos inside each other**, % of close frames | 3.8–9.2 | **1.4** | 6.7 | **3.1** |
| **A limb inside a body**, % | 3.3–5.4 | **1.4** | 3.6 | **2.0** |
| ... while neither is striking, % | 0.4–2.1 | 0.8 | 1.1 | 0.5 |
| Limb depth, median studs | 0.45 | 0.46 | 0.46 | 0.46 |
| Hit / whiff / blocked / interrupted, % | 64.8 / 2.5 / 3.4 / 29.1 | 70.9 / 3.8 / 0.7 / 24.4 | 65.1 / 9.4 / 2.2 / 23.2 | 64.8 / 8.6 / 2.9 / 23.5 |
| Same clip as last strike, % | 21.6 | 18.0 | 21.6 | 21.6 |
| Phrase length, median s / strikes | 1.1 / 4 | 1.6 / 5 | 0.9 / 3 | 0.8 / 2 |
| Re-entries per pair-minute | 12.0 | 12.8 | 12.4 | 13.4 |
| Tempo fast / mid / slow, % | 85.5 / 9 / 5.4 | 85 / 7.8 / 7 | 83.2 / 9.7 / 6.9 | 83 / 10.2 / 6.7 |
| Engaged, % | 55.1 | 56.5 | 47.9 | 47.4 |
| Server frame, median ms | 9–10 | 9 | 21.8 | 21.9 |
| Client frame, median ms | 9.2–9.6 | 9.4 | 21.3 | 22.0 |

The 1v1 is a single run (seed E544A1); the baseline is the mean of three. The 16v16 is one 240 s run each.

**What this says:**
- **Bodies inside each other dropped by 60–80%.** Limbs still land in the body during strikes, about 0.46 studs deep, as intended (`Spacing_ContactDepth`).
- **Hits didn't drop:** the 16v16 rates are flat, and the 1v1 has slightly more hits.
- **No measurable cost:** frame times are unchanged. That also suggests the baseline's 21.8 ms in the 16v16 is real, not an artifact of the stray probes.
- **The fight's rhythm didn't move:** variety, phrases, re-entries and tempo are all within run-to-run noise.

## What's left

- **Overlap the hold can't remove.** In the 16v16, 456 overlap episodes still happen, 78% "walking", mostly attacker into attacker. They are short (124 s of overlap across 31.5 pair-minutes). Two likely reasons:
  - AI bodies are simulated on the player's machine (network ownership), so the server's hold arrives a frame or two late;
  - two bodies closing at once each get held only after the gap is already gone.

  Both could be tuned (a slightly larger look-ahead gap, or holding on predicted distance) if the owner's eye still sees clipping. It isn't worth it before then.
- **The hold uses the body's actual velocity**, so while it is on, sideways motion continues at the speed it had. It lasts 0.06 s, so the Humanoid steers again almost at once.
- **Re-measure `reach` when a strike clip is replaced** (the probe above).

## For the owner to judge (1v1)

Start a 1v1 and watch close exchanges. Bodies should no longer sink into each other when both attack. Punches should land with the fist in the body, not with the chests touching. Toggle the Workspace attribute `Ablate_Spacing` (true = off) during the fight to compare live.
