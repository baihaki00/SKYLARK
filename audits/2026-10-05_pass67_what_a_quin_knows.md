# Pass 67: What a Quin knows of its target (item 6)

The owner: on platforms they seem to see through to below; what a Quin knows should depend on
seen / last seen / memory ("common sense" later).

## What already exists

I had proposed a new "knowledge record" in the general audit. It already exists: the Cognition
pipeline (Senses: sight cone with a line-of-sight ray, hearing, touch; Memory: tracks that age,
dead-reckon and are forgotten; reports from allies; a team-wide rumour). ChaseState already hunts
from memory. So nothing new was built. Two things were wrong with how it was used.

## 1. "I can see my target" was not kept honest

`TargetHasLoS` was written in two places (target selection, ChaseState) and only on some paths:
not while knocked down or in a jump (Pass 59), not on the "keep the held target" returns, not in
Fight or Circling. Measured in a generated arena, 16v16, against a ray between the two heads
through solid parts only: of 80 samples with something solid in between, the attribute still
said "seen" in 40.

Now `Main` writes it every tick, from the Quin's own contact record for its target, in every
state, and nowhere else does: `TargetHasLoS` (it sees it now) and the new `TargetKnownBy`
(sight, touch, hearing, memory, report, rumour).

Same measure after:

| | Before | After |
|---|---|---|
| solid part in between, says "seen" | 40 of 80 | 3 of 96 |
| how a hidden target was known | - | report 42, touch 30, memory 13, hearing 8 |

"Not seen though the line is clear": 602 of 3992 samples. That is not an error: the target is
outside the Quin's vision cone or range (it knows it from memory or from an ally's report).

## 2. The line-of-sight ray

`SpatialModule.checkLineOfSight` stopped at the first part of any kind; when that was an effect
part or foliage it answered "visible", whatever stood behind it. It now only meets solid parts.
(Seen in the first measurement: 1 of the 40 wrong answers was a ray through leaves.)

## Mind panel

When the watched Quin cannot see its target it says how it knows where it is: by ear, from
memory ("Lost sight of him. He went that way."), from the others, or only by rumour.

## Not done

- "Common sense" (in a 1v1, footsteps under the platform are the target): later, as the owner said.
- Nothing new uses `TargetKnownBy` for behaviour; the states already act on the contact record.
- The mind panel lines were not looked at in play.
