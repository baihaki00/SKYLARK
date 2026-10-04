# Pass 44 (2026-10-05): falls and get-ups by the side the body comes down on

Owner's clip list (new uploads and renames), item 1 of the 2026-10-05 list.

## Names now (`AnimationConfig`)

| Entry | Asset | What it is |
|---|---|---|
| `Movement.FallAirKnockback` | 88475997278069 | Air knockback flailing (name only changed) |
| `Movement.FallBack` | 88441309301154 (new) | Falling with the back to the ground |
| `Movement.FallFront` | 80583167665730 (was `FallStraight`) | Falling with the face to the ground |
| `Reactions.GetUpBackFastNinja` | 95406088712190 (was `GetUpBackFast`) | Instant recovery from the back (kip-up) |
| `Reactions.GetUpBackFast` | 79207866638803 (was `GetUpGround`) | Get up from the back, fast (96 frames) |
| `Reactions.GetUpBackSlow` | 119670118817591 (replaces 128158227118276) | Get up from the back, slow (148 frames) |
| `Reactions.GetUpFrontFast` | 82896239168564 (new) | Get up from the front, fast (96 frames) |
| `Reactions.GetUpFrontSlow` | 90997656474712 (new) | Get up from the front, slow (148 frames) |

`Attacks.Specials.SlamRecovery` now borrows `Reactions.GetUpBackFast` (one id per animation).
`AnimationIds`, `AnimationModule` (lengths, names, overlay group), `QuinDebugHUD`, the Animation
Lab preset label and `COMBAT_ANIMATION_GUIDE.md` follow the new names.

## Rule

- **Knockback (air):** flailing on the way up. Once it has been in the air 0.25 s and sinks at
  6 studs/s or more, the side is decided and the fall pose takes over: thrown backward (hit from
  the front) or already tipped face up -> `FallBack`; thrown forward -> `FallFront`. Published
  as the `FallSide` attribute.
- **Recovery:** back on its feet in an instant (the behaviour the owner likes) -> the kip-up from
  the back, or a landing (`LandingHard` / `LandingSoft` / `LandingSuperHero`) from the front.
  Knocked flat (a heavy knockdown, as before: `hard_ground`, or 15 % of air knockbacks) -> it
  gets up from the side it lies on, slowly when its health is under
  `Recovery_SlowGetUpHealth` (35 %).

## What the clips are (measured on the rig)

| Clip | Length | Lies | Hips height through the clip |
|---|---|---|---|
| FallBack | 1.50 s | on its back, head behind the root | stays at standing height (an air pose) |
| FallFront | 1.57 s | face down, head ahead of the root | drops 7 studs to the floor in the first quarter |
| GetUpBackFastNinja | 2.03 s | back -> upright | on the floor, rises |
| GetUpBackFast | 3.20 s | back -> upright | on the floor, rises |
| GetUpBackSlow | 4.93 s | back -> upright | **stays at standing height** |
| GetUpFrontFast | 3.20 s | face down -> upright | **stays at standing height** |
| GetUpFrontSlow | 4.93 s | face down -> upright | **stays at standing height** |

So the three new get-up clips lie down without lowering the hips: played as they are, the body
lies about 4 studs up in the air. They look exported without the hips' vertical travel. Two
clip corrections cover it until they are re-exported:

- `ground = true` (new, in `CombatConfig.ClipCorrections`, applied by the client controller):
  the body is lowered until its lowest bone rests 0.45 studs above the floor found under it.
  It does nothing for a clip that carries its own hips travel.
- `FallFront` gets `translationScale = 0`, so it is flown as a pose in the air like `FallBack`
  instead of dropping 7 studs under the root.

Head and body direction: on the back the head lies behind the root in all back clips, face down
it lies ahead in all front clips, and the face-down head is turned the same way at the end of
`FallFront` and the start of both front get-ups (80-87 deg). Every get-up ends with the shoulders
turned 39-51 deg to the left and the face 1-33 deg off the front (the ninja kip-up ends square,
the others 15-33 deg): they end in a bladed stance, not the idle's square one.

## Measured in a 16v16 (75 s)

Clips started: flailing 86, FallBack 56, FallFront 20, kip-up 55, landings from a front fall
about 41, GetUpBackFast 10, GetUpFrontFast 4. Fall side: back 61, front 24. Neither slow get-up
came up (they need a heavy knockdown on a Quin under 35 % health). No script errors.

Resting on the floor (lowest bone above the floor under the Quin, median):

| | First 30 % | Middle | Last 15 % |
|---|---|---|---|
| GetUpBackFast (own hips travel) | 0.25 | 0.19 | 0.17 |
| GetUpFrontFast (`ground` correction) | 0.19 | 0.37 | 0.29 |

A first version measured the floor from the root at standing height and sank the front get-up
about a stud into the ground (a body that is down holds its root lower); it now looks for the
floor with a ray.

## Also found

Studio's `AnimationConfig` had been replaced by an older copy (before the placeholder work of
pass 36: 37 duplicated ids back, `resolveBorrowed` / `placeholders` gone) with a stray space in
`BeamStru ggle` that stopped it compiling. Nothing new was in it. It was replaced by the
committed version plus this pass's renames.

## Not shown

- `GetUpBackSlow` and `GetUpFrontSlow` did not occur in the run: their correction is the same
  code as `GetUpFrontFast`'s but unseen.
- Not looked at by eye: the switch from the fall pose in the air to the get-up on the floor, and
  how `FallFront` reads as an in-place pose.
- Saved Animation Lab overrides (DataStore) cannot be read in Studio; an override saved under an
  old path name would not carry over to the renamed entry.
