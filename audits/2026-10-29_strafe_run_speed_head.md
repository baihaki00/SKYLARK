# Strafe run: the speed dip and the 90° head

2026-10-29, Studio (QUIN_COMBATV4). Built from the owner's report on the strafe run:
- the speed slows down, still under the run clip, then speeds up again;
- the head looks 90° off the way the body runs (the owner's top-view drawing: the direction arrow points up, the gaze points right).

**Waiting on:** the owner's eye.

## 1. "Slows down, then speeds up" (Circling)

**Cause (measured, 16v16).**
- A Quin circling at run pace usually arrives at 36–44 studs/s, out of a sprint or a dash.
- Circling's "carrying momentum" mode runs that speed off, and it was taking the body down to the jog speed (12). While that happened, the gait played the run strafe clip at 0.6–0.8×.
- Then the strafe form took it back up to 18.8.

**How much of it there was:**
- 9–15 studs/s made up 21–34% of the Circling frames where the run strafe clip played.
- In that mode, 502 of 895 frames had WalkSpeed 12.

**Fix (`States/CirclingState`).** While it is only running momentum off, or settling onto the circle, it eases down to the strafe pace it is about to take, not below it.
- Switch: `CombatConfig.Circling_DriftAtStrafePace = false` brings back the jog.

| Circling frames under the run strafe clip | Before | After |
|---|---|---|
| 9–15 studs/s | 21–34% | **11%** |
| Carrying momentum at WalkSpeed 12 | 502 of 895 | 8 of 498 |

**Also added:**
- **Hysteresis on the line between the strafe form and the travel form** (`Circling_FormHysteresis`, 15°). On its own it made no measurable difference to the dip; it is kept to stop flip-flopping at the line. Setting it to 0 brings back the single line.
- **Debug readout `CirclingForm`.** It shows the form Circling is in, and why: strafe; travel because it's carrying momentum; travel because it's moving off the path; or travel because the path doesn't follow the circle. It is written only while a debug screen is open.

**Not fixed: Fight.** A strafe clip keeps playing at its last rate while the body is stopped: a strike sets WalkSpeed to 0, and the gait isn't updated during an attack.
- That is 31% of Fight's strafe-run frames.
- Most of it is probably under full-body strike clips, where the legs don't show.

## 2. The head 90° off the run

**Cause.**
- The strafe clips move the body 90° sideways and keep the head to the front.
- SquareUp turns the chest to the front as well.
- LookController aims the head at the target relative to the root, and in a strafe the root faces the target. So the head stays square to the target while the legs run sideways.

**Fix.** Built on `SquareUp.runLead(root)`, which is 0 when walking or moving along the facing, and 1 when sideways at 15 studs/s or more (it starts from 10).
- **`Procedural/SquareUp`:** doesn't square the chest up while running sideways, so the chest stays turned into the run, as the clip has it.
- **`LookController`:** keeps the head within `Look_RunMaxOffTravel` (50°) of the travel, whether looking at a target or with no target. Deliberate looks (glance back, social) keep their full turn.
- **Switches:**
  - Workspace `RunLeadOff = true` brings back the old pose (it can be set on the client, so you can compare it live);
  - `CombatConfig.Look_RunLead = false` turns it off.
- **Tunables:** `Look_RunMaxOffTravel`, `Look_RunLeadFrom`, `Look_RunLeadFull`.
- Walking strafes are unchanged: they still look to the front, which the owner chose on 2026-10-04.

**Measured** on the drawn body (client), within one 16v16, switching the lead on and off every 8 s. The sample is Quins moving at 15+ studs/s, sideways to their facing.

| | Lead off | Lead on |
|---|---|---|
| Head off the travel, mean | 73° | **55°** |
| Over 70° | 53% | 40% |
| Over 55° | 62% | 52% |

- The 40% still over 70° is likely the deliberate looks (glance back, social), which keep their turn, and the head spring catching up after a direction change. Not checked further.

**Probe trap.** A bone's `TransformedWorldCFrame`, read on the client in a render step, doesn't include the offsets that scripts wrote this frame. It showed the head unchanged while LookController's own `LookYaw` was 65°. Build the head's world rotation yourself instead: start from the mesh part's CFrame and multiply down the chain by each bone's `CFrame * Transform`. The bone method in the 2026-10-28 head report (head vs hips 78°) may have had the same blind spot.

## For the owner to judge

- **Circling at run pace:** no slow-motion drop after it arrives; it settles straight into the strafe.
- **Running sideways:** the chest is turned into the run and the head looks over the shoulder, about 50° off the run instead of 90°.
- **Walking strafes:** unchanged.
