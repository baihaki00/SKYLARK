# Pass 59: One door for a Quin's target (item 22, the remainder)

Pass 43 gave `TargetingModule.selectTarget` a commitment rule, but eleven other places wrote
`CurrentTarget` directly. This pass sends every one through one function, measures who causes
the flip-flopping, and fixes the two causes found.

## Step 1: one door, with the reason recorded (no behaviour change)

- `TargetingModule` has a local `assign(fighter, name, reason)`; every change of target inside
  the module goes through it.
- States use `TargetingModule.setTarget(fighter, target, reason)` (ChaseState x5, FightState,
  OverwatchState, AirInterceptModule) and `clearTarget`. No state writes `CurrentTarget` itself
  any more. (`Main` still writes back what `selectTarget` returned: the same value.)
- The attribute `TargetChangedBy` says who asked for the last change: `Select` (the utility
  choice), `Nearest` (a state's nearest-enemy look-up), `Distraction`, `RearThreat`, `Dive`,
  `Intercept`, `Duel`, `State`.

## Measured with that (16v16, 60 s, 32 Quin-minutes)

639 target changes, **19.9 per Quin-minute**; 126 of them (20 %) went straight back to the
previous target within 3 s.

| Asked by | Changes | Went straight back |
|---|---|---|
| Select | 505 | 74 |
| Distraction | 85 | 35 (41 %) |
| RearThreat | 35 | 8 |
| State / Intercept / Nearest | 14 | 9 |

- **Distraction** (ChaseState: an enemy within 13 studs that is not the target) ping-ponged: 25
  of its flip-backs were Distraction -> Distraction. With two enemies close by, each is the
  other's distraction on the next tick.
- **141 changes (22 %) happened in Knockback, Recovery, ProjectileJump or MidAirClash**, where a
  Quin cannot act on the choice: it comes out of the fall or the jump turned to someone else.
- `Nearest` (the second, distance-based selector inside `getNearest`), which I expected to be
  the culprit, changed the target 3 times. It is not.

## Step 2: the fixes

1. **A distraction respects the hold.** `setTarget` returns false for a reason in
   `HOLD_RESPECTING` (`Distraction`) while the Quin is still inside `Targeting_MinHold` on the
   target it has; ChaseState then carries on with its chase. Urgent reasons (rear threat,
   intercept, dive) are not held back.
2. **No new target while not in control.** `Main` does not run the selection in Knockback,
   Recovery, ProjectileJump, MidAirClash or Airborne (`NO_RETARGET_STATES`); the Quin keeps the
   target it has.
3. **A held target that leaves the near view is still the target** while the hold lasts (thrown
   clear, round a corner). Before, the commitment only applied while it was among the nearby
   candidates.
4. Every change, whoever asks, starts the hold (`assign` keeps the record).

## Measured after (16v16, 56 s, 29.8 Quin-minutes; a different match)

| | Before | After |
|---|---|---|
| target changes per Quin-minute | 19.9 | 13.9 |
| straight back within 3 s, per Quin-minute | 3.9 | 2.65 |
| Distraction changes / flip-backs | 85 / 35 | 15 / 3 |
| changes in Knockback + Recovery + jump + clash | 141 | 25 |

All 32 Quins alive at the end of both minutes.

## What is left

- **Select -> Select** is now most of the flip-backs (43 in the minute; a second sample: 25 in
  50 s, median 2.0 s apart, i.e. as the hold runs out). Their reasons read "It is hunting me",
  "Immediate rear threat": a Quin with two enemies on it turns from one to the other. That may
  be right; shortening it means changing the rear-threat and hunted scores. **Left for the
  owner's call.**
- 18 changes still happen in ProjectileJump and 7 in Knockback: states re-asserting their own
  target (`State`) and rear-threat reactions. Not followed further.
- Two samples in two different matches: the size of the effect is clear for Distraction and for
  the out-of-control states; the overall rate should be re-measured over a longer run.
- Not checked: hit / whiff rate after the change (it was 66 % / 8 % at the Pass 29 baseline).
