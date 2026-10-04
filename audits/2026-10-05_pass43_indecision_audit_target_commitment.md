# Pass 43 (2026-10-05): indecision audit, target commitment

Owner's list of 2026-10-05 (25 items, in memory `quin-open-requests-20261005`). This pass takes
item 22 ("chaotic and indecisive ... quick 180 then committing to his target again ... stress
test the conditions") and answers item 1 (fall clips).

## Decision audit (16v16, 100 s, every Quin's state, target, travel and facing)

| | Before | After |
|---|---|---|
| Target switches per Quin per minute | 29.1 | 16.2 |
| Switches straight back to the previous target within 3 s | 639 of 1550 (41 %) | 250 of 862 (29 %) |
| Idle visits (99-100 % of them under 0.5 s) | 145 | 44 |
| Fight > Idle > Fight bounces | 29 | 9 |
| Facing flips over 135 deg in half a second, in Chase | 170 | 118 |
| State changes per Quin per minute | 38.5 | 36.8 |
| Travel reversals in Fight | 248 | 256 |
| Strikes | (not taken) | 663 hit, 48 whiff, 55 blocked, 201 interrupted of 967 |

**What the indecision was.** A Quin's target is re-scored every decision tick from a dozen
moving terms (who is nearest, who is hunting it, who stands behind it, risk). The winner was
taken at once, so the target changed every 2 s, and 46 % of the time (second probe) it went
straight back to the one just dropped, which had been held 0.79 s on average. The most common
reason on a flip was "It is hunting me": the bonus goes to whichever enemy is the primary
pursuer, and with two enemies near, that title moves between them. In Fight each change to a
target more than 12 studs away forces an Idle "look round" (`TargetTransition`): the quick turn
away and back.

Twelve places write `CurrentTarget` (utility selection in Main, nearest-enemy fallbacks, Chase's
distraction and rear-threat rules, air intercept, Overwatch). When nobody was in the local
radius (mid projectile jump: 53 switches) the fallback dropped the target for the nearest enemy.

## Change: commitment in `TargetingModule.selectTarget`

- A Quin stays on its target for at least `Targeting_MinHold` (2.0 s x (0.5 + its target
  persistence)) and changes only to one whose utility leads by `Targeting_SwitchMargin` (30).
- A lead of `Targeting_UrgentMargin` (80, e.g. something hitting it from behind) cuts the hold.
- The hold also notices a target set from elsewhere and holds that.
- With nobody near, the committed target is kept instead of falling back to the nearest.

## Travel reversals in Fight are mostly physics, not indecision

A third probe classified 254 of them: about 110 were the Quin being hit or shoved, about 90 were
a Quin that had been knocked away coming back (walking or lunging at its target), 9 were its own
spacing step back. Every non-launch hit skids the victim 10-18 studs
(`Combat_GroundKnockbackMin/MaxStuds`), so every exchange separates the pair and one walks back
in. That is a design setting, not a race; shorter skids would make fights read as less
back-and-forth. Left for the owner to decide.

## Still there

- 250 flips back in 100 s: the eleven other writers of `CurrentTarget` are not behind the
  commitment yet.
- Recovery (43 %) and Retreat (55 %) are left within 0.5 s; MidAirClash 48 %. Not examined.
- Circling > Fight is the most common transition (302): standoffs are short.
- No knockout in 100 s in the "after" run (32 alive). Knockout pace not compared.

## Item 1: fall clips

Clips played in 100 s: FallAirKnockback 104, Fall 89, GetUpBackFast 84, LandingSoft 76,
StandardJump 54, NinjaJump 47, DiveFly 37, NinjaAirLoop 25, StandardAirLoop 21, Jump 18,
LandingSuperHero 16, LandingHard 9, NinjaLanding 9, StandardLanding 8.

There is no FallFront / FallBack in `AnimationConfig`: the registry has `Movement.Fall`,
`Movement.FallStraight` and `Movement.FallAirKnockback`. A knocked-away Quin always plays
FallAirKnockback whatever way its body faces, and `FallStraight` is preloaded but nothing plays
it. The get-up side exists (GetUpGround / GetUpBackFast), but only GetUpBackFast showed up.
Orientation-based falls need clips (or placeholders) added and a rule in KnockbackState.
