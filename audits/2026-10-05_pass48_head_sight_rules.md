# Pass 48 (2026-10-05): the head and what it can see (item 6); edge idling not reproduced (item 2)

## Item 6: "on platforms they seem to look through the platform"

Cause, in `LookController` (client):

- The head turned to its target's real head position every frame, with no check that anything
  was in between: a target under the platform, behind a wall or behind a block was stared at
  through it.
- The "look down over the edge" pose of a Quin on high ground (`Cognition.Gaze`, modes resting
  and glance) was taken wherever it stood, including the middle of a wide top.

Now:

- **A target it cannot see is looked for where it last saw it.** A ray from its own head to the
  target's head, ten times a second, blocked by the world and not by other Quins. Clear: the
  spot is remembered. Blocked: the head turns to the remembered spot (mode `TARGET_LAST_SEEN`),
  or stays with the clip if it never saw this target.
- **It does not look into the floor it stands on.** A look steeper than 12 deg down that meets
  level ground within 40 studs of the head is held level (`+FLOOR`); from the rim the same look
  clears the edge and goes down.
- Workspace `LookSight = false` switches both rules off (A/B); `LookDebug = true` publishes the
  head's mode per Quin as `LookDbg`.
- `TargetingModule` drops a stale `LastSeenTargetPosition` when the target changes to one it
  cannot see.

The server's `TargetHasLoS` attribute was tried first and dropped: it said "visible" for 59 % of
the targets a head-to-head ray found hidden (317 of 533 samples).

## Measured

What the head is doing (generated arena, 40 s, `LookDbg`):

| Situation | Samples | Head mode |
|---|---|---|
| Target hidden | 779 | last seen 53 % (6 % of it held off the floor), scan 21 %, live target 17 %, social 6 % |
| Target visible | 9733 | live target 73 %, scan 13 %, social 8 %, last seen 2 % |
| On a platform | 1032 | held level off the floor in 16 % of samples |

So the rules engage. (The 17 % "live target" on hidden targets is the tenth of a second between
checks plus the two rays not being identical.)

**Not shown: a change in where the head ends up pointing.** Two in-match on/off comparisons of
the final head direction showed no difference (head down into its own platform top 9-26 % with
the rules on, 10-24 % off; head on a hidden target 15-24 % on, 7-20 % off). Two reasons, neither
separated out: the clips themselves pitch the head down (the rule only removes LookController's
own added pitch, it does not level a clip), and a "last seen" spot is usually close to where the
hidden target still is. An earlier before/after across two different arenas (21 % -> 6 %) was
arena difference, not the fix. Head snapping is unchanged by the rules (7.3-7.7 % of frames over
500 deg/s on and off). Needs the owner's eye.

## Item 2: idling on edges

Not reproduced. In a generated arena, 80 s, Quins stood still for a second or more for 40 of
1807 Quin-seconds, and within 3 studs of a drop for 0.2 of those. Nothing changed. The owner is
asked which state the idling Quins show and where (platform rim, arena edge, match start or end).

## Not started in this group

Wall-edge awareness (11) and the lag after touching a wall (12): both go with the playable
ArenaWall (13).
