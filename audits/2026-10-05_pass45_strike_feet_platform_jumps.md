# Pass 45 (2026-10-05): feet free in a strike; platform jumps (items 3, 5, 7 of the list)

## Feet left to the clip in a strike

Owner: "disable foot IK or solver, it looks funky during strikes".

While a Quin's `Attacking` attribute is set, foot planting, the uneven-ground height conform and
knee-over-toe let go of its legs (a held foot fades back to the clip from where it was pinned).
Body layer `StrikeFeetFree` (`Layer_StrikeFeetFree`, HUD row "Body: feet left to the clip in a
strike"), on by default.

Checked with the solver's own debug readout (`FootDebug`, left foot, Quins in Fight, 7 s):

| | Foot held by the solver | Samples |
|---|---|---|
| Striking | 4 of about 410 (1 %) | 410 |
| Not striking | 70 of about 250 (28 %) | 250 |

A first check through the `IKControl.Weight` readout showed no difference between the switch on
and off (0.27 against 0.31): that readout does not track this and should not be used for it.

## Item 5: jumping at a platform from underneath

Cause: Chase's "seek high ground" rule looked for a platform top straight above the Quin (and 4
studs to each side) and then jumped straight up at it with a fixed 22 studs/s forward. Under the
platform that is a jump into its underside, repeated every 6 s.

Now: the platform is taken from the catalogue and reached from outside its footprint. Under it,
the Quin walks out the nearest way with room for a run-up ("Under the platform: stepping out to
jump"); outside, the jump is solved for the rim as the target-intercept jump is (back off if too
close, line up, jump). It gives the climb `HighGround_ClimbPatience` (5 s), then leaves it for
6 s.

**Not seen in play:** the rule did not fire in either 85 s run (before or after), so this is
verified by reading only.

## Item 3: landing on the edges of platforms

Cause: jumps onto a platform were solved to land `LandingMargin` (2.5 studs) past the nearest
point of the rim, and stepping-stone hops aimed 1.2 studs in from it.

Now: `TraversalModule.solveJumpOnto` takes a landing depth, and `PlatformCatalogue.landingDepth`
gives the way toward the middle of the top (at most `Jump_LandingDepthMax`, 8 studs; less on a
small top). Used by Chase's intercept and climb jumps and Retreat's jump to high ground.
Stepping stones aim 30 % of the top's width in from the rim (at most 8).

## Item 7: several tries to get off a platform

Cause: the dive off a platform was taken whenever the target was within 28 studs, however far
the ledge was. From the middle of a wide top a 2-stud hop of 8-15 studs came down on the same
top, played its landing, and was taken again.

Now: the leap is taken only when it carries past the ledge (ledge distance +
`HighGround_DiveLedgeMargin` 2.5 within the leap's reach); until then the Quin walks to the ledge.

## Measured (16v16, 85 s each, one run before and one after; small samples)

| | Before | After |
|---|---|---|
| Arrivals on a platform | 5 | 9 |
| Mean distance from the rim on arrival | 1.9 studs | 3.6 studs |
| Arrivals within 2 studs of the rim | 60 % | 33 % |
| Time on platforms within 2 studs of the rim | 14 % (152 samples) | 6 % (194) |
| "Ledge Dive Down" ticks | 137 | 86 (15 separate dives, 5.7 ticks each) |
| "Climbing High Ground" jumps | 0 | 0 |

Strikes in the after run: 573 hit, 42 whiff, 32 blocked, 151 interrupted. No script errors.

## Still open in the platform and obstacle group

Idling on edges (2), stuck under low obstacles (4), seeing through platforms (6), wall-edge
awareness (11), the lag after touching a wall (12). A dive still takes about 6 ticks to leave,
so the repeated-landing report is reduced, not shown gone. Not looked at by eye.
