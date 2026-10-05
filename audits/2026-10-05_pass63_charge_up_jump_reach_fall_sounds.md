# Pass 63: Charge-up before a projectile jump, jumps up to 25 studs, new fall sounds

The owner: fall sounds QUIN_FALLHARD / QUIN_FALLSOFT; a 1 s charge-up before a projectile jump
with QUIN_CHARGEUP; normal jumps up to 25 studs; and a diagram: from anywhere a Quin may get
about by a normal jump, a projectile arc or any jump style ("free to move wherever and however
they choose").

## Sounds

- `AudioModule.playFallOnGround(position, soft)`: QUIN_FALLHARD by default (slams, knockdowns,
  long drops), QUIN_FALLSOFT when `soft`. Soft is used for the `LandingSoft` clip's landing
  marker and for a jump that was in the air less than `Landing_SoftSoundAirTime` (0.7 s).
  The two old FALL_ON_THE_GROUND sounds are no longer used for this.
- `AudioModule.playChargeup`: QUIN_CHARGEUP.
- Volumes are my guesses (hard 0.4, soft 0.3, charge 0.35): **not heard**.

## Charge-up

An attacking projectile jump starts with a `Charge` phase of `ProjectileJump_ChargeTime` (1.0 s):
the Quin stays on the spot facing its target, the charge sound and the existing gathering-aura
effect play, then it takes off. Its launch clip is held on its first frame meanwhile; the
smack-down clip plays its own wind-up (its first 0.53 s, which used to be skipped) across the
charge. **Not** before a hop on to a spot (traversal) nor an interception (it has to leave at
once). The flight is timed from the takeoff.

Measured, 16v16 in a generated arena, 97 s: 72 charged jumps, each launched 1.04 - 1.09 s after
the charge began, none interrupted, no errors.

## Jump reach 12 -> 25

`Jump_MaxReach` 25. The limit was also written into five other places, all now derived from it:
`LocomotionModule.jump` (four clamps at 14), `TraversalModule.Config.MaxTraversalHeight`,
`HighGroundJumpReach`, and a literal 14 in ChaseState.

Raising the number alone changed nothing (highest jump 11.1 studs, 36 spot hops in the match).
Two rules were in the way:

1. **Stepping stones came first** for any climb of 8 studs or more, so the jump was never
   reached. Now a top within a jump's reach is jumped at first; the stones take over for what
   is higher, or when the jump has not come off for `HighGround_ClimbPatience` (5 s).
2. **The vantage rule walked it away.** With the jump solvable but not lined up, the code fell
   through to "back off from under the platform" (21 run-ups and no jump in 97 s). Now it runs
   at the edge and goes when lined up; the vantage rule waits while the jump is being worked at.

Also: a stepping stone that the Quin is facing, within a jump's reach and range, and at least
`Nav_StoneJumpMinWidth` (10) wide is jumped on to; the spot hop stays for the rest (too high, too
far, a small top, not lined up).

Staged on a generated arena's own platforms (target frozen on top, chaser 20 studs out):

| Top | Result |
|---|---|
| 12 up | on top by a jump, 0.8 s and 2.2 s (2 of 2) |
| 15 up | jump from 13 studs off the edge: peak rise 15.1, landed on top; another got up by a spot hop in 0.9 s; one jump fell short |
| 18 up | got up by spot hop in 2 of 4; no jump taken |

So jumps of 15 studs now happen and land; I did not see one above that, and in natural
16v16 play they are still rare (most climbs there are to targets more than 25 up, or 30 - 60
studs across, which only a projectile arc covers).

## Not done / not checked

- The diagram's other half: leaving a platform by a chosen jump of any length. Getting down is
  still the dive / walk-off logic from Pass 45 - 47.
- Jumps of 18 - 25 studs: allowed by every limit, not observed.
- The remaining list items (11 wall rim, 14 mind panel, 6 knowledge) were not touched.

## Follow-up (Pass 63b): the owner's verdict

"Remove the chargeup stuff, I don't like it; bring back the previous fall sound, it's fine
already; just remove the HIT_POWERFUL sound."

- **Charge-up removed** completely: `ProjectileJumpState` is back to its Pass 62 text, the
  `ProjectileJump_ChargeTime` setting is gone.
- **Fall sounds reverted** to the two FALL_ON_THE_GROUND sounds at their old volume; the
  hard / soft split and `Landing_SoftSoundAirTime` are gone. QUIN_FALLHARD, QUIN_FALLSOFT and
  QUIN_CHARGEUP stay in the Assets folder, unused.
- **HIT_POWERFUL (90318464419858) is no longer played.** It was in three places: the heavy hit,
  a second layer under every slam, and a second layer under the mid-air clash. The slam and the
  clash keep their main sound; a heavy hit now uses the light impact set, lower and fuller
  (my choice, unheard).
- The jump reach changes of Pass 63 stay.

Checked in a 16v16, 50 s: 61 projectile jumps, no Charge phase, no HIT_POWERFUL sound created,
no errors.
