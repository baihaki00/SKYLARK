# Pass 71: The strike clips are the owner's 8; old attack IDs removed

The owner authored and published 8 strike clips with markers: punches L/R, and low, high and wheeldrive kicks, each L/R. The Left kicks were mirrored from the Right ones in Studio. The owner asked:
- replace the attack IDs with these;
- keep only these in Kicks and Punches;
- delete `Special`;
- refactor `Specials` into `Special`, keeping only `ProceduralSmackDown` (the only one with its own clip).

## AnimationConfig.Attacks now

| Path | Asset |
|---|---|
| Punches.LeftPunch / RightPunch | 90752953215195 / 100294955898321 |
| Kicks.LowKickRight / LowKickLeft | 120201409079711 / 128873647170869 |
| Kicks.HighKickRight / HighKickLeft | 112847704540861 / 78628980439076 |
| Kicks.WheelDriveRight / WheelDriveLeft | 72225232579765 / 103890244670922 |
| Special.ProceduralSmackDown | 71743026406362 (unchanged) |

**Removed:**
- Punch1, Uppercut, CrossLeft, CrossRight, HighKick, LowKick, PowerKick, WheelDrive;
- `Special` (Slam, Special1);
- `Specials` (Slam, SlamImpact, SlamRecovery, Special1, Uppercut, RivalFinisher, BeamStruggle).

**Timing:** `impactRatio` and `cancelRatio` come from the owner's markers, read from the published assets:
- `impactRatio` is the middle of HitStart–HitEnd;
- `cancelRatio` is Recover.

| | impactRatio | cancelRatio |
|---|---|---|
| punches | 0.60 (was 0.35) | 0.83 |
| low kicks | 0.43 | 0.86 |
| high kicks | 0.43 | 0.93 |
| wheeldrive | 0.47 | 0.89 |

Speeds are kept from the old entries. This is interim until the marker reader.

## What used the removed entries, and where it points now

| User | Now |
|---|---|
| Beam struggle (`Attacks.Specials.BeamStruggle`, a fight-idle borrow on its own track) | moved to `Transition.BeamStruggle` |
| `SpecialState` (Special1 / Slam) | `Attacks.Kicks.HighKickRight` / `WheelDriveRight` |
| `AnimationIds.RivalFinisher` (DamageModule) | the right high kick |
| `Tactics.DesperateCounter` | borrows `Attacks.Punches.RightPunch` |
| `ProjectileJumpState` SMACK_PATH | `Attacks.Special.ProceduralSmackDown` |

**Also updated:**
- `AnimationIds` punch and kick lists; the Uppercut, Slam, SlamImpact and SlamRecovery aliases are removed;
- AnimationModule's known lengths and names;
- QuinDebugHUD names;
- PlayerQuinController punch list;
- Animation Lab defaults and combo chain.

No old attack asset ID or path is left in any script.

## Measured (16v16, 100 s, 807 strikes)

| | Pass 69 | Pass 71 |
|---|---|---|
| hit | 67 % | 67 % |
| whiff | 7 % | 8 % |
| blocked | 7 % | 4 % |
| interrupted | 19 % | 21 % |

- **Clips played:** RightPunch 376 (includes the desperate counter), LeftPunch 246, HighKickRight 91, WheelDriveRight 85, WheelDriveLeft 81, HighKickLeft 78, LowKickRight 73, LowKickLeft 69, smack-down 5.
- **Errors:** none (only Studio's DataStore notices).

## Not done

- **The marker reader:** hits still land at one moment (`impactRatio`), not over the HitStart–HitEnd window.
- **Punch clips:** both have an empty `HitEnd` parameter.
- **Punch / kick share:** punches are 2 of 8 entries but ~77 % of strikes. FightState's own pick weights punches; that is unchanged.
