# Pass 69: Regression check after Passes 52 - 68; the settings that were not in the config

Nothing was asked for here beyond "continue": this is a check that the last seventeen passes
did not break the fight, and one loose end from the general audit.

## Regression check (16v16, default arena)

| | Pass 29 baseline | Now |
|---|---|---|
| strikes that hit | 66 % | 67 % |
| whiff | 8 % | 7 % |
| blocked | 8 % | 7 % |
| interrupted (hit during the wind-up) | 18 % | 19 % |

(221 strikes over 57 s, counted per strike on `StrikeSeq`. A first count on `StrikeResult`
changes read 45 % hits: that attribute does not fire when two results in a row are the same, so
repeated hits were dropped. Count on `StrikeSeq`.)

- Frame rate: 121 fps over the first 127 s (worst frame 46 ms).
- Target changes: 11.3 per Quin-minute (19.9 before Pass 59, 13.9 after it).
- Chasing but standing still for more than 1.5 s: 0 times in 127 s.
- Time by state: Fight 33 %, Chase 32 %, Circling 11 %, Recovery 8 %, ProjectileJump 6 %,
  Knockback 5 %.
- Pace: no knockout in the first 197 s; 8 by 239 s, mean health then 28 % (1000 health each,
  almost no healing). Matches are decided late, all at once.
- Errors: none. A second match (generated arena) was left running for 69 minutes: no errors.

## Jump down in natural play (Pass 68)

That 69-minute match: 47 jumps down that left the ground, 5 of them came down on the same
level, 23 walk-offs. Median landing 35 studs from the target: in natural play the target is
usually 75 - 170 studs away and moving, far beyond one jump, so the jump goes as far as it can
(arcs of 11 - 16 studs, 50 - 98 across) and the Quin runs on. Where the target was within reach
it landed 5 and 15 studs from it. 11 attempts never left the ground (the jump was refused: not
looked into).

## Config

The general audit found 13 settings that code read but `CombatConfig` never defined, so they ran
on a default written at the place of use. They are now listed in the config with those same
values (checked by loading the module): `Nav_AgentRadius`, `Nav_MaxHeightOnFoot`,
`Nav_SweepHeight`, `Nav_OffPathDistance`, `Nav_PathRefresh`, `Nav_ClearHoldTime`,
`Gait_AutoDriveInterval`, `Gait_StartFade`, `Gait_WeightFade`, `HighGround_VantageDistance`,
`EnergyDrain_PointJump`, `BeamStruggle_MaxDuration`, `ProjectileJump_TurnLegSlope`.
No behaviour change.
