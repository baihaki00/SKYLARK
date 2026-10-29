# Gait transitions: the run clip in slow motion (2026-10-29)

The owner said: "running animation slowing down … no slowing down, just maintain the speed", and "what i care is the fucking transitions" between walk / jog / run / strafe.

## Chase holds its run (`ChaseState`, `ChaseState/Steer`)

- None of these slow a chase any more: the walk to a downed target (this morning's 22-stud change made a run → walk drop), the stalking walk, the walk after a soft landing, the casual walk off a ledge, or the Pace gears (Jog far out, shifting down as urgency drops).
- Only out of breath (fatigued) walks.
- Obstacle pacing between back-to-back hurdles is kept: without it a sprint lands with no run-up for the next one.
- Switch: `CombatConfig.Chase_HoldSpeed`, Workspace `ChaseHoldSpeedOff`.

A/B (20 s windows, chase 18+ studs from the target, on the ground):

| | On | Off |
|---|---|---|
| Mean WalkSpeed | 27.4 | 26.5 |
| Below 80% of run speed | 47% | 49% |

**Small.** The walks were rare. Most chase slowdowns happen inside the Run gear: turnarounds, the strafe cap, landings, ramping up.

## The real cause of the slow-motion run: the gait blend (`GaitModule`)

- The blend gave the run clip the whole pose from **18 studs/s** (`Gait_JogToRunEnd`). The clip is authored at **29.5**, so from 18 to ~27 it played at 0.6-0.9×.
- Baseline (40 s, all moving Quins): the run clip under 0.85× in **21%** of moving frames (under 0.7×: 13%).
- The clips also step at different rates (walk 1.03 s a cycle, jog 0.83, run 0.47), so a blend by speed alone can't keep them at 1×.

**Fix: the rate-matched blend** (`rateMatchedWeights`):
- Between two neighbouring clips, the mix t is the one where the blended stride × the blended natural cadence equals the speed.
- Every clip plays at that mix's cadence, so the clip leading the pose plays close to its own pace.
- The mix follows the speed at 16/s instead of 7/s (`Gait_RateMatchedFollowRate`). At 7/s, a Quin speeding up showed an over-cranked jog, and one slowing down a slow-motion run.
- Switches: Workspace `GaitRateMatchOff` (the old bands); Workspace `GaitBlendFollowRate` (number, for A/B).

**A/B** (15 s windows × 2 each, a 16v16, all moving Quins on the ground):

| | Old | Rate-matched, follow 7 | **Rate-matched, follow 16** |
|---|---|---|---|
| Run leading the pose in slow motion (<0.85×) | 8.9% | 4.3% | **3.4%** |
| Leading clip over 1.4× | 5.5% | 7.6% | **5.5%** |
| Leading clip outside 0.85-1.4× | 16.5% | 14.8% | **11.3%** |
| Leading clip flips back within 0.3 s | 50 | 76 | 82 |

The first run (follow 7) also had the run clip's median speed **0.86× → 1.02×**.

No script errors.

**The flip-back count rose.** With the rate-matched mix, Quins spend more time near a 50/50 jog/run mix, where the "leading clip" crosses back and forth. The blend itself is continuous, so it should not read as a pop, but this is for the owner's eye.

## Not changed

- **The strafe:** the walk strafe plays over 1.35× in ~10% of moving frames (median 1.5×), because the run strafe clips are off (`Strafe_RunClips`, owner: they need polish). Sideways speed above ~11 studs/s over-cranks the walk strafe.
- **Found, not built:** the spin under stepping stones. `HeadroomAwareness.exit` searches for the way out starting from the Quin's own facing, and its fallback is "back the way it came" relative to its facing. Both turn with the body, so each tick picks a new direction (a spin loop). Fix: keep the chosen exit until it is reached or loses its room.

## Built: no more spinning under stepping stones (`HeadroomAwareness`)

- Each Quin now keeps its chosen exit point until it reaches it, the point has no room any more, or 3 s pass. The fallback point ("back the way it came") is held the same way.
- Switches: `CombatConfig.Headroom.Sticky` (nil = on); Workspace `HeadroomStickyOff = true` brings back the fresh search every tick.

**A/B** (16v16; first 30 s windows × 2, then 45 s windows × 2; Quins with `LowCeiling`):

| | Off | On |
|---|---|---|
| Mean turn rate under a low ceiling | 323 °/s | 251 °/s |
| Frames turning > 360 °/s | 35 | 21 |
| Turn in one "no room" episode, mean | 113° | **52°** |
| Turn in one episode, max | **1275°** (a spin) | 194° |
| Episodes with a full spin (> 360°) | 1 of 43 | **0 of 30** |
| Stuck over 3 s | 0 | 0 |

The fast turns left are single turnarounds to an exit behind the Quin, not spins.

**Seen in the console, not mine:** `SpatialModule:180 attempt to index nil with 'FindFirstChildOfClass'` (isGrounded, Main line 555), right after a SafetyNet void teleport.
