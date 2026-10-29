# Leg foot slide in state transitions: measured

2026-10-29, Studio (QUIN_COMBATV4), 16v16 TeamBattle, 60 s, client side (what the owner sees). Nothing changed yet.

**Probe (runtime only, Client):**
- Every Quin, every frame, after the pose: `RenderStepped` + `task.defer`.
- Each foot's ToeBase bone in world space, with a ray down to the floor.
- **Planted** means the toe is under 0.2 studs above the floor for at least 3 frames in a row.
- **Slide** is the planted toe's flat speed, in studs/s. A properly planted foot reads about 0.
- **Legs moving while still:** the root moves under 1 stud/s, but a toe moves more than 3 studs/s relative to the root.
- Frames in the air or in air states are skipped.
- **Buckets, in this order:**
  - Recovery exit: 0.6 s after leaving Recovery;
  - start: 0.6 s after the body begins moving;
  - stop: 0.6 s after it stops;
  - turn on the spot: under 2 studs/s and over 90°/s;
  - other state change: 0.5 s;
  - Fight;
  - still;
  - moving.

## Results

| Bucket | Planted foot-frames | Slide p50 | Slide p90 | Sliding (> 2 studs/s) | Legs moving while still | Move clips > 0.5 while still |
|---|---|---|---|---|---|---|
| still (reference) | 2070 | 0.05 | 0.55 | **2%** | 24% | 3% |
| start | 3406 | 6.3 | 27.2 | **79%** | n/a | n/a |
| Recovery exit | 674 | 6.1 | 25.0 | **70%** | 79% | 36% |
| turn on the spot | 131 | 5.2 | 25.8 | 62% | 76% | 20% |
| other state change | 654 | 4.7 | 28.9 | 61% | 48% | 18% |
| stop | 3115 | 1.8 | 10.7 | 47% | 60% | 14% |
| moving | 1580 | 1.6 | 21.4 | 47% | n/a | n/a |
| Fight (steady) | 2072 | 0.04 | 9.5 | 29% | 36% | 30% |

The still row shows the measure itself is clean: about 0 when nothing moves.

## Where the sliding comes from (the strongest clip above Idle, on frames over 2 studs/s)

1. **Strikes in Fight**: LeftPunch / RightPunch, Low/High kicks, WheelDrive.
   - These are the top of both start and stop.
   - The body lunges or brakes (Strike impulse) while the strike clip holds the feet where they were, so they skate.
2. **Recovery → Chase/Fight**:
   - Move clips run at weight > 0.5 while the body is still 36% of the time.
   - The legs step in place 79% of the time.
3. **Circling strafes**: StrafeLeftWalk / StrafeRightWalk slide while moving; the clip's pace doesn't match the body's.
4. **Starts in Chase**: Jog / Run reach weight before the body has speed (bookmark 6).

`FightIdle` sits at weight 1 under everything (Idle priority); it isn't a cause.

## Proposed fix order

1. **Foot lock:**
   - pin a planted toe where it touched the floor while it stays planted;
   - release it into a quick step once it stretches past a limit.
   - This covers strikes, stops, turns and Fight. It would use the existing foot solver in PCRC, with a switch.
2. **Gait blend:**
   - movement-clip weight and playback rate follow the body's real speed: a walk clip doesn't reach full weight at speed 0, and strafe pace matches;
   - covers starts, Recovery exit and strafes. With a switch.

Re-run this same probe after each step.

## Step 1 built: foot lock (2026-10-29, the owner said "Yes, foot lock")

**The lock already existed:** PCRC's `FootPlant` pins a planted foot and steps it on when it falls behind. The probe showed where it let go:

- **Strikes:** 65% of all sliding. `StrikeFeetFree` freed both feet for the whole strike.
- **Feet down but not pinned**, by the solver's own `FootDebug` reasons:
  - "armed" slid 99% of the time. The plant-when-still rule refused a foot the clip still moved.
  - "waitLift" slid 64-74%. A foot let go waits for a lift that some clips never make.
- **A pinned foot ("lock")** slid only 12-18%, mostly the toe swinging round a fixed ankle.

**Three new layers in `Procedural/Layers`.** Each defaults to on, with its own off switch (Workspace or per-Quin attribute):

- **`StrikeStance`** (`Layer_StrikeStance`):
  - The feet stay planted through a strike.
  - A foot the clip moves against the body faster than `FootIK_StrikeFootFreeSpeed` (5 studs/s) is let go: the kicking foot, or a step inside the clip.
  - Knee over toe still stays out of strikes.
- **`PlantGlide`** (`Layer_PlantGlide`): a foot the clip carries along with the body (still against the body) plants too, below `FootIK_StepMaxSpeed`.
- **`PlantLowHold`** (`Layer_PlantLowHold`):
  - A foot kept down for `FootIK_PlantLowTime` (0.08 s) plants even if the clip still moves it. The walk's heel reaches for about 4 frames, so the still rule keeps that job.
  - An unpinned foot that has been down for `FootIK_PlantRearmTime` (0.3 s) may plant again without a lift.

All code is in `ProceduralCombatReactionController` (foot placement, step 3). The new tunables are read with defaults in code; CombatConfig is unchanged.

**A/B in one 16v16:** the three layers alternated off/on every 8 s for 64 s, client side.

| Bucket | Sliding off → on | Median slide off → on (studs/s) |
|---|---|---|
| strike | 69% → **44%** | 3.7 → 1.4 |
| start | 70% → **37%** | 5.4 → 1.1 |
| stop | 36% → **18%** | 0.7 → 0.2 |
| other state change | 54% → 34% | 2.6 → 0.2 |
| Fight (steady) | 31% → 18% | 0.5 → 0.1 |
| Recovery exit | 46% → 43% | 1.6 → 0.9 |
| moving | 50% → 50% | 2.0 → 2.0 |
| turn on the spot (small sample) | 48% → 56% | 1.9 → 2.1 |
| **all** | **59% → 37%** | |

No script errors. Frame time wasn't judged: the client ran at about 53 ms a frame in both halves (1000 crowd avatars).

**Not fixed by the lock:**
- Legs stepping in place while the body stands still is unchanged (45-70%). The clip moves those legs, so that's step 2, the gait blend.
- Steady moving and turns are unchanged.
- A pinned foot's toe still swivels round the ankle.

**Probe trap:** `(m == "on") and nil or false` is always `false` in Lua. The first two A/B runs had the layers off in both halves.

## Step 2: gait blend (2026-10-29, the owner said "Yes, gait blend"). Tried and reverted

**The blend already exists.** `GaitModule` already does the speed-matched blend:
- Walk / Jog / Run weights follow the body's real speed;
- the cadence matches the stride;
- the gait fades to idle below 3 studs/s and releases below 0.4.

So "the walk clip at full weight while the body stands still" isn't the blend's doing.

**Which clips move the legs while the body stands still** (30 s, 1383 of 2586 still frames, top clip above Idle):

| Clips | Frames | Meant to move the legs? |
|---|---|---|
| strike clips (WheelDrive, kicks, punches) and HitHeavy | ~600 | yes: authored footwork |
| get-up (Recovery) and LandingHard | ~160 | yes |
| Walk / Jog / Run / strafe (running in place) | ~190 | no |
| idle stance only | ~140 | stance bounce plus solver steps |

**The idea tried:** watchers draw the body about 0.18 s behind the server, while clips arrive at once. So `GaitModule` drove the blend from the server velocity 0.18 s back. Switch: `GaitDelayOff`.

**Measured** (A/B, 8 s windows, 64 s):

| | Delay off → on |
|---|---|
| start sliding | 50% → 50% |
| stop sliding | 21% → **27%** (worse) |
| Recovery exit: walk/run running in place | 44% → 25% |
| all sliding | 39% → 40% |

The delay isn't the cause of start slides. **Reverted:** GaitModule is back byte for byte (35,230 characters).

Also measured with the foot solver off: server and client feet slide alike at starts (88% / 90%). The network buffer isn't the main cause.

**Where start slides really are** (solver `FootDebug`, start frames, no strike):
- **"lock" at full leg weight still slides 47%** (872 frames): the ankle is pinned but the toe moves. Two suspects:
  - The solver's turn attenuation (`turnDampen`) loosens the lock above 4 rad/s of body turn, and Quins swing round to their heading as they set off.
  - The toe swivels round the pinned ankle as the foot yaws with the body.
- **Unpinned feet** (waitLift / free / armed / none) slide 87-100%, about 780 frames.

**Proposed next, both in PCRC with switches:**
1. Hold a locked foot's yaw (and so its toe) while it's pinned. The foot turns only when it steps or lifts.
2. Exempt a fresh plant from the turn attenuation at low speed, so a body turning on a planted foot pivots on it instead of dragging it.

## Step 3 built: the toe on a pinned foot (2026-10-29, the owner said "Yes, fix the toe")

**Two new layers in PCRC**, each defaulting to on with a `Layer_*` switch:

- **`PinnedYaw`** (`Layer_PinnedYaw`):
  - A pinned foot keeps the direction it came down in. It's recorded at each new pin from the foot-to-toe line and laid over the clip's foot rotation in `applyLeg`.
  - Past `FootIK_PinnedYawMax` (60°) from the clip, it turns with the body, so it's never twisted far off the leg.
  - Once let go, it eases back onto the clip's direction (12/s, about 0.1 s) instead of snapping.
- **`PlantTurnHold`** (`Layer_PlantTurnHold`):
  - Below `FootIK_TurnHoldSpeed` (6 studs/s), a pinned foot keeps full weight; the turn attenuation (`turnDampen`) no longer loosens it.
  - The drift and overreach rules still step it round.

**A/B in one 16v16:** the two layers alternated off/on every 8 s for 64 s; the step 1 layers stayed on in both halves.

| Bucket | Sliding off → on | Median slide off → on (studs/s) |
|---|---|---|
| start | 50% → **33%** | 1.9 → 0.3 |
| stop | 23% → **12%** | 0.2 → 0.1 |
| Recovery exit | 46% → **22%** | 1.6 → 0.1 |
| strike | 45% → 39% | 1.4 → 0.4 |
| other state change | 41% → 39% | 0.6 → 0.5 |
| Fight (steady) | 20% → 22% | 0.1 → 0.1 |
| moving | 53% → 51% | 2.4 → 2.1 |
| turn on the spot (small sample) | 46% → 51% | 1.8 → 1.9 |
| **all** | **40% → 33%** | |

**Across all three steps:** sliding went 59% → 33% overall. Starts went 70-79% → 33%, stops 36-47% → 12%, strikes 69-78% → 39%.

No script errors.

**Not checked by measurement:** how a foot held up to 60° off the leg looks, and whether the knee looks twisted. That needs the owner's eye.

**Still open:**
- Turns on the spot (too few frames to judge).
- Steady running (about 50%: the run clip's own stance creep, beyond the drift allowance).
- Legs moving in clips while the body stands still (authored strikes and get-ups).
