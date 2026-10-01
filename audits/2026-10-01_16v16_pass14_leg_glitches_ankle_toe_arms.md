# 16v16 pass 14: leg glitches, ankle slope alignment, toe flex, arm secondary motion

Backup: `ServerStorage.backup_pre_16v16audit14_20261001`. Base: pass 13 (`668a91d`).

## Requests (owner)
1. Ankle slope alignment and toe flex.
2. "Weird leg glitches when they're moving."
3. Can the whole body (arms, torso) move less 100%-canned / more fluid, or is that unnecessary?

## Measuring glitches
Client probe in `PreAnimation` (final pose), alternating workspace switches in 10-20 s blocks in the same 16v16. Metrics per 1000 leg/arm-frames:
- **Snap:** knee angle or thigh direction changes > 25° in one frame. Also catches fast normal motion (a run cycle swings the arm 10-20° per frame at ~46 fps).
- **Spike:** a reversal of > 10° in each of two consecutive frames. This is the visual "pop"; smooth fast motion does not reverse within a frame. Used for the final verdicts.

## 2. Leg glitches (the pass 13 leg solver)

| knee snaps / thigh flips per 1000 | clip only | pass 13 solver | now |
|---|---|---|---|
| knee > 25°/frame | 20 | 38 | 30 |
| thigh > 25°/frame | 5-7 | 16 | 10 |

Causes found in frame samples:
- **Knee pop near a straight leg.** With the solver at full weight, the knee went 172° → 136° → 172° between frames. Near full extension, a hair of hip-to-goal distance swings the knee angle tens of degrees.
  - Fix: soft reach. Past 92% of leg length, the distance is eased toward 99.5% instead of clamped. The foot falls slightly short of a goal it could only reach with a locked knee.
- **Thigh flips.** Pass 13 switched outright between the clip's knee-bend direction and "forward" when the clip's bend got small or pointed back.
  - Fix: a continuous forward bias (clip bend + 0.35 × forward), smoothed over time per leg (18/s, reset after any pause > 0.1 s so it never blends from a stale direction).
- **What remains.** Spikes with the solver on are 1-2.5 per 1000. Most samples flagged with the solver on show solver weight 0, meaning the clips themselves (fight clip transitions).

Foot slide stayed fixed: fast median 31-32 → 0.8-1.7 studs/s, gliding 42-50% → 21-26%.

## 1. Ankle slope alignment and toe flex
Both config switches existed but were never implemented.
- **`FootIK_AnkleAlignment`:** when the solver places a foot, the foot is turned by the rotation from flat ground to the surface normal under it, over the clip's own heel-strike/toe-off angles, scaled by the solver weight. Flat ground leaves the clip untouched (the arena floor is flat; this acts on wedges and tilted OB parts).
- **`FootIK_ToeFlexion`:** on the final foot pose (solved or not), the toe tip is estimated (ToeBase + 70% of the foot-to-ball length along the bone; the rig has no toe-end bone). If the tip is below the ground plus `FootIK_ToeSoleThickness`, the toe bends up at the ball of the foot, at most `FootIK_ToeMaxFlexDegrees` (50). Smoothed (35/s up, 12/s down). Not in the air, Knockback, Recovery or PlatformStand.
- **Result:** toe tips below the floor in 0.5% of near-ground frames.

## 3. Whole body: secondary motion on the arms
Recommendation given to the owner: a fully procedural / physics-driven body (active ragdoll) would cost the authored style, the CPU budget for 32 Quins, and add new failure modes. A light secondary-motion layer gives the "not 100% canned" feel cheaply. The spine already has force lean and hit recoil; the head has LookController; the arms were 100% clip.

`ProceduralCombatReactionController:updateSecondaryMotion`:
- **Spring:** each upper-arm and forearm tip follows its clip position through a damped spring (6 Hz, damping 0.75), sub-stepped at 120 Hz. The spring is fed the clip's own velocity, low-passed because far Quins have their animation stepped at a lower rate. Steady motion is followed with no lag; a start, stop, turn or hit leaves the arm trailing briefly.
- **Caps:** 14° for the upper arm, 20° for the forearm.
- **Fade:** fades out while the clip moves the arm faster than 12 studs/s relative to the body (strikes stay as authored). The weight is rate-limited.
- **Resets:** the springs reset when the root moves more than its velocity explains (CFrame placement). The layer is off in MidAirClash, which places bodies by CFrame every tick.
- **Switches:** `CombatConfig.SecondaryMotion_*`; workspace `SecondaryMotion` = live A/B.

Tuning history (spikes per 1000 arm-frames, MidAirClash excluded):

| version | upper-arm spike off → on |
|---|---|
| 4.5 Hz, damping 0.55, per-frame fade weight | 3.6 → 9.9 (MidAirClash teleports, flickering weight) |
| + rate-limited weight, teleport reset, filtered feed | 3.1 → 5.7 (whip at every run-cycle swing) |
| 6 Hz, damping 0.75, fade from 12 studs/s | **5.6 → 3.1** (elbow 1.1 → 1.3) |

With the final settings, the layer smooths the clips' own arm pops: Knockback 157 → 4 spikes, Recovery 112 → 5. It is on by default.

## Also fixed
`QuinDebugHUD` used `TweenService` without defining it; hovering the Spectator HUD button threw two errors.

## Checks
- 0 server and 0 client errors in the final runs.
- Screenshot of a fighting Quin: arms in a guard, knees forward, rear foot on its toes.
- Motion quality (overlap, steps) is not something a still capture can show; judged by the frame metrics.

## Open
- The clips themselves have knee/arm snaps (fight clip transitions, ~20 knee snaps per 1000 frames). Those are animation-side.
- Secondary motion covers arms only. Spine/head already have procedural layers; hands and fingers are untouched.
