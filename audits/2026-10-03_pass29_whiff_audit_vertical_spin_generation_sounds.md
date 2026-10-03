# Pass 29: 16v16 whiff audit, the vertical "Y-axis race", crowd silent-start bug, generation sounds

## Generation sounds

`ARENA_GENERATION1` (10 s) and `ARENA_GENERATION2` (2.5 s) are in `ArenaSoundFX`.
- They play from an invisible emitter at the arena centre, 25 studs above the floor (roll-off 200–1600), through the arena master volume. They don't use the ArenaGlobe speaker.
- `ARENA_GENERATION1` starts with the scan. `ARENA_GENERATION2` plays when the arena is complete.
- The emitter lives in the generated folder, so restoring the arena also silences it.
- Config: `ArenaGeneration.Sounds`.
- **Tested:** the sweep played at (0, 27, −438) on ArenaSpeakerGroup; the finish played at "ARENA READY".

## 16v16 strike audit (before the fix)

A collector hooked every Quin's `Attacking`, `StrikeSeq` and `StrikeResult` over 60 s and 40 s runs:

| Run | Strikes | Hit | Whiff | Interrupted | Blocked |
|---|---|---|---|---|---|
| 1 | 557 | 61% | 13% | 19% (counted as "other" in this run) | 7% |
| 2 | 359 | 59% | 12% | 22% | 6% |

**Why the whiffs happened.**
1. **Thrown while not facing the target.**
   - Facing at the throw (dot product): whiffs averaged 0.47. In run 2, 14 of 31 sampled whiffs were below 0.5, against 6 of 104 hits.
   - FightState threw a strike as soon as the cooldown allowed, while the facing gyro was still turning.
2. **The target moved out during the ~0.34 s wind-up.**
   - Targets were 5–9 studs away at the throw, but 8–14 ahead or 5–10 to the side at impact (strafing in Fight or Circling).
   - The step-in lunge went along the body's LookVector, toward where the target had been. Jab reach is 6.5 forward and 3.5 to the side.
3. **The whole clip played on a miss:** 0.6–1 s of swinging at air.

Height was rarely the cause (3 of 55 whiffs).

## Fixes (FightState, CombatConfig)

- **`Combat_StrikeFacingDot` 0.8 and `Combat_StrikeFacingWait` 0.5:** a strike waits until the body faces the target (at most 0.5 s; the gyro turns at 14 rad/s).
- **Aimed step-in:** the lunge goes toward the target's position plus 0.6 × its velocity × the time to impact (`Combat_StrikeLead`), not along the facing.
- **`Combat_StrikeTracking`:** re-aims the step-in halfway through the wind-up.
- **`Combat_WhiffRecovery` 0.2 s:** on a whiff the attack clip fades out and the Quin moves again; `Attacking` clears at the same time.

## After the fix (16v16, 60 s)

| Measure | Before | After |
|---|---|---|
| Hit | 59–61% | 66% |
| Whiff | 12–13% | 8% |
| Blocked | 6–7% | 8% |
| Interrupted | 19–22% | 18% |

- **Facing at throw:** hits 0 below 0.5 and 170/207 above 0.95; whiffs 1 of 24 below 0.5.
- **Remaining whiffs:** the target's forward distance at impact was under 6.5 for 12, 6.5–9 for 7, 9–12 for 4 and over 12 for 1. These are targets stepping just out of reach.
- **Generated arena, 8v8 (seed 8980E0):** hit 63%, whiff 9%.
- **Interrupted (18–22%):** strikes cut by a hit during the wind-up. The clip stops (`DamageModule`), so these are trades, not whiffs. Left as is.

## The "Y-axis race" (ChaseState)

**Cause.** When a target is perched more than 8 studs above and the chaser is within 16 studs flat, ChaseState steered to a "vantage" point computed every tick from the chaser's own facing (22 studs behind, 8 to the right). Turning toward it moved it, so the Quin ran in a circle on the spot under the platform.

**Fix.**
- The chaser backs straight away from the target to a fixed spot `HighGround_VantageDistance` (24) out, along the target→chaser line. A random direction is saved as `VantageDir` when it stands right underneath.
- If the target is beyond jump reach, the chaser waits in the 16–24 band, creeping toward the target at 2 studs/s so it stays turned to it, until a jump or projectile jump opens up.
- Targets within jump reach still get the normal run-up approach.

**Measure** (yaw faster than 3 rad/s, target more than 6 above or below, under 10 flat):
- Chase samples went from 14 to 6 (16v16, 60 s) and to 1 in 40 s on the generated arena.
- The rest are knocked-back or airborne bodies, where spinning is expected.

## Body stability

Tilt over 30° outside Knockback, Airborne and ProjectileJump: 5 of 9,056 samples (all Recovery), then 10 of 8,928. No problem.

## Other quirks swept (16v16, 45 s)

- **Falls out of the arena:** none. **Fight standoffs** (8.5–12 studs, nobody attacking, 3 s or more): none.
- **Stuck 6 s or more:** 6 short cases, one each in Fight (x2), Overwatch, Idle, Circling and Chase. Watch item.
- **State flip-flops** (4 changes within 2 s): 86.
  - These are mostly one Idle visit between combat states: 16 Idle visits in 30 s, all from Fight, lasting 0.1–1 s, with a target attribute set.
  - That's the moment after a kill before the next enemy is perceived. Reads as a beat; left as is.
- **Crowd silent-start bug (found while testing, Pass 26 bug).**
  - On the server a Sound reports `TimeLength` 0 until it loads. The crowd skipped length-0 templates to avoid the one failed upload, so in a session where none had loaded yet, every sound was skipped: 0 loops, a silent crowd.
  - **Fix:** templates are no longer filtered by length. A loop copy that hasn't loaded after `LoadTimeout` (6 s) marks its template bad and is replaced. One-shots end on `Ended`, with a timer fallback.
  - **Tested:** 29 crowd sounds all loaded and playing 1.5 s into ARENA_OPEN; 22 beds still playing at 9.5 s; nothing wrongly flagged.

## Regression

- 16v16: 32 Quins, 0 errors.
- Arena match on a generated arena to IN_GAME: 0 errors.
- P possess: Costume_baiyyaki00 player-controlled.
