# Pass 36 (2026-10-04): one id per animation; Quins steer round each other

## Animation ids

Owner: every animation should have one id; placeholders added for later had copied ids and nobody
remembers which.

`AnimationConfig` held 106 entries: 10 blank social slots, 96 with a clip, and only 59 different
ids. 19 ids were shared by 56 entries.

- Each id is now written once, on the entry that owns it. The other 37 entries are placeholders:
  `borrows = "Owner.Path"` in place of the id, with their own speed, fade and priority.
- `AnimationConfig.resolveBorrowed()` fills a placeholder's `id` from its owner when the module
  loads and after every `update()`, so nothing that reads `entry.id` changes behaviour.
- A placeholder given its own id (in the source or in the Animation Lab) stops borrowing.
  `exportLuau()` writes `borrows`, not the resolved id. `AnimationConfig.placeholders()` lists them.
- The owner of each id was chosen from `AnimationModule`'s id-to-name table and the entry names;
  it is a guess where two entries could both be the original (marked ?).

| Owner | Placeholders that borrow it |
|---|---|
| Attacks.Kicks.PowerKick | Attacks.Special.Special1, Attacks.Specials.RivalFinisher |
| Attacks.Kicks.WheelDrive | Attacks.Special.Slam |
| Attacks.Punches.CrossRight | Tactics.DesperateCounter |
| Attacks.Punches.Punch1 ? | Attacks.Punches.Uppercut, Attacks.Specials.Slam, .SlamImpact, .Special1, .Uppercut |
| Attacks.Specials.SlamRecovery ? | Reactions.GetUpGround |
| Awareness.LookingBehind | Awareness.RearThreatGlance |
| Idles.DefaultIdle | Movement.Idle |
| Idles.FightIdle | Attacks.Specials.BeamStruggle, Idles.CombatIdle, Idles.SurveyIdle, Transition.AssessTarget |
| Movement.ArcRun30Rear | Movement.ArcRun30RearLeft, Movement.ArcRun30RearRight |
| Movement.BrakingStop ? | Reactions.HitLight, Reactions.Knockback |
| Movement.FallAirKnockback | Reactions.FallAirKnockback, Reactions.KnockbackAir, Reactions.SlammedDown |
| Movement.Jump | Parkour.VaultObstacle |
| Movement.RunTurn180 ? | Awareness.Turn180Pivot, Movement.RunTurn180Left / Right, Movement.RunTurn90Left / Right |
| Movement.StartRun | Movement.IdleToRun1, Movement.IdleToRun2, Movement.StartSprint |
| Movement.WalkConfident | Movement.WalkThug |
| Parkour.LandingSoft | Parkour.LedgeDropLanding |
| Reactions.Block ? | Reactions.BlockFront |
| Reactions.Death | Reactions.DeathCollapse |
| Strafe.StrafeLeftWalk | Tactics.RetreatBackstep |

## Strafe clips, measured on the rig

| Clip | Length | Travel | Travels toward | Hips face | Chest faces |
|---|---|---|---|---|---|
| StrafeLeftRun | 0.667 s | 17.9 studs/s | 91 deg left of the root | 78 deg | 53 deg |
| StrafeLeftWalk | 1.033 s | 7.3 | 89 deg left | 68 deg | 47 deg |
| StrafeLeftTired | 1.467 s | 2.6 | 90 deg left | 32 deg | 26 deg |
| StrafeRight* | same | same | mirrored | mirrored | mirrored |
| WalkConfident / Jog / Run | | 7.0 / 9.5 / 26.6 | 0 deg (root forward) | 1-3 deg | -7 to 2 deg |

So the owner's reading is right: these are walks along the travel direction with the upper body
turned part of the way back (hips 12-22 deg, chest 37-43 deg off the travel direction), baked a
quarter turn from every other clip. `Tactics.RetreatBackstep` plays the left strafe walk.
Not changed yet: the rename (Tired / Walk / Run) and how circling uses them wait for the owner.

## Bodies in the way (`Modules/BodyAwareness`)

Owner: Quins shove through each other as if nobody were there.

Before: nothing in the movement code knew about other bodies (the reachability sweep excludes
them on purpose). All AI movement passes through `LocomotionModule`'s steer driver, so the rule
sits there: `BodyAwareness.adjust(fighter, rootPart, desired, speed)` bends the direction round
bodies on the path (look-ahead grows with speed), eases away from one right beside it, ignores
its own opponent, and passes a body dead ahead on the right. `BodyInWay` names the body it is
steering round (mind panel: "Someone's in my way. Go round."). Tunables `CombatConfig.BodyAwareness`;
switches Workspace `BodyAwareness` / `BodyPersonalSpace` = false.

16v16, the rule switched off and on every 10-12 s inside the same match:

| Measure | Off | On |
|---|---|---|
| A moving Quin (over 12 studs/s, not striking) running into a body that is not its opponent, share of Quin time, run 1 | 0.27% | 0.09% |
| same, run 2 (longer look-ahead) | 0.19% | 0.15% |
| any two non-opponents within 3 studs, one moving (three-way run: off / path only / path + personal space) | 2.00% | 2.10% / 1.63% |
| hit rate | 68% | 67% |

With the rule on, 45 s of 16v16 held 1.43 Quin-seconds of running into a body; about 60% of that
was a Quin being carried (knocked back, sliding, recovering), not walking. 78% of all remaining
contact is two Quins going for the same opponent.

Not covered: states that move without the steer driver (ReEntry), strike lunges and knockback
slides (physics, not route). The effect is real but modest and noisy between runs.
