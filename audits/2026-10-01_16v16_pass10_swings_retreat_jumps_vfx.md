# Pass 10 (2026-10-01): swings, retreat, jump validity, platforms, force lean, ground VFX

Rest of plan phase 4, phase 5, and the owner's request to check retreat and swings.
Studio backup: `ServerStorage.backup_pre_16v16audit10_20261001`.

## Swings

128 s of 16v16 before this pass: 845 of 1655 swings landed (51%). Misses by cause:

| Cause | Count |
|---|---|
| Attacker was hit during its wind-up | 270 |
| Target never in reach (swing started at 8-10 studs: 145, 10+: 55, under 8: 46) | 246 |
| Target hit by someone else at the same moment | 109 |
| Target moved out of reach | 64 |
| In reach, no hit (guard held / facing) | 62 |
| Target knocked away | 52 |

Measured on swings started at 6.5-9.2 studs: the step-in needed 2.2 studs on average and
delivered 1.9 while the target receded 0.5, ending right on the edge of a jab's 6.5-stud reach.

Changes:
- A strike whose thrower is hit during the wind-up is cancelled: the attack clip stops, nothing
  is cast, the combo resets (`DamageModule` sets `StrikeInterrupted`; a strike within 0.08 s of
  landing still comes out — a trade).
- The step-in has its own force (60000) so it is not eaten by the Humanoid's braking, and stops
  4.8 studs from the target (was 5.5); strikes are thrown within 9 studs.

After (126-150 s runs): 45-47% of all swings land; 18-21% are cancelled by a hit; of the
swings that come out, 57-58% land.

## Retreat

Before: 75 retreats in 128 s, almost all 2.5-3.0 s. A Quin at 5% health fled, stopped, chased
back in and fled again eight times. Causes:
- Retreat ended as soon as the decision stopped saying "Retreat", and leaving the crowd is what
  makes it stop (no longer outnumbered).
- A Quin that still wanted to retreat was only pulled out of Fight, not out of Chase, so it
  chased straight back in; in Circling it took part in the standoff and attacked when it timed out.
- It turned to counterattack on reaching allies or on a pursuer's whiff even at 5% health.

Changes:
- The run is finished (destination reached or plan 4 s old) before the decision is reconsidered.
- A decision to retreat also pulls a Quin out of Chase.
- In Circling a Quin whose tactical state is RETREATING keeps its distance, takes no part in the
  standoff, and runs again when its target comes within 40 studs.
- Turning to fight during a retreat needs more than 20% health.

After: 61-96 retreats per run, median 2.9-3.1 s, 16-25 of them 4 s or longer, longest 11-15 s,
average net distance 74-84 studs (35-90 before the escape plan, measured on forced retreats).
Most retreats are still short: mid-health Quins break away from being outnumbered, run their
plan and re-engage.

## Jump validity (phase 4)

- `TraversalModule.validateArc`: follows the feet along the launch arc; valid only if it comes
  down on standable ground with headroom. `LocomotionModule.jump` checks every jump that was not
  planned over a known obstacle, also against the arena bounds, and returns false when rejected
  (debug layer "Jump plans" shows "jump rejected: reason"). 45-54 jumps per run were being taken
  into walls; they are now refused.
- Jump callers asked for heights up to 35 studs; a jump gains 14 at most. `Jump_MaxReach = 12`:
  a target up to 12 studs higher is jumped to (energy and cooldown spent only if the jump is
  taken); higher than that the Quin uses a projectile jump at it (27 in a 126 s run).
- Removed two blocks in `ChaseState` that always asked for unreachable jumps ("Elevated Platform
  Awareness", "Positioning Projectile-Jump").
- Escape plans only consider platforms within jump reach.
- Arena has 60 `OB` parts with tops from 2 to 158 studs.
- Teleport probe (position change > 10 studs unexplained by velocity): none outside
  MidAirClash's flash steps in three runs.

## Force lean and per-Quin style (phase 5)

`ProceduralCombatReactionController`: the spine leans into the body's smoothed acceleration
(up to 14 degrees fore/aft, 12 sideways at 60 studs/s^2). Under strong acceleration the chest
tilted toward it in 78% of sampled frames (mean tilt 8.6 degrees).
Experiment, off by default (`ProceduralStyle_Enabled`, HUD switch "Motion: per-Quin style"):
each Quin gets its own lean amount, hip twist and response speed, seeded from its name.
IK-driven foot placement was not added.

## Ground VFX (phase 5)

`VfxModule`: `createLandingDust` (jump landings, knockdown ground contact, projectile-jump
impact), `createSlideSmoke` / `stopSlideSmoke`, `createGroundMark` (slide streaks, stop-run skid,
knockdown skid), `createFootprint` (sprint steps, from the Footstep marker). Marks fade in
2.5-4 s, 60 at most. Switches `Vfx_LandingDust`, `Vfx_SlideSmoke`, `Vfx_GroundMarks`.
Not checked visually (only that marks are created and no errors).

## Open

- Combat on platforms is still rare (3 Quin-seconds of Fight above 12 studs in 126 s).
- Reaching a high platform without an enemy on it (to hide) is not possible: the projectile
  jump needs a Quin as its target.
- 45 jumps per run are still attempted and rejected; the callers do not yet look for another way.
