# Pass 47 (2026-10-05): walking on after a soft landing; headroom awareness (item 4)

Both measured in a generated arena (`ArenaGenDevCommand "run 4"`, then `team:16`), as the owner
suggested: seeds CFEB4F (before) and B6A9FD (after).

## Soft landing: it stands through it and walks on

Pass 46 reported Quins at 14.6 studs/s 0.4 s after a soft landing. Traced one by one, the hold
does work: 6 of 8 were at 0 studs/s at 0.2-0.4 s. The average was pulled up by two that were hit
or went into a projectile jump. What was missing was the walk: once the hold ended, Chase took
the run straight back.

Now a soft landing sets `CasualUntil` (the hold plus `Landing_CasualWalkTime`, 2.5 s), and Chase
keeps to a walk until then unless the target is within 14 studs or something is behind it.

| Soft landing in Chase | 0 s | 0.4 s | 0.8 s | 1.5 s | 2.5 s | 3.5 s |
|---|---|---|---|---|---|---|
| 6E2A | 7 | 0 | 3 | 7 | 0 | 0 |
| BC3D | 7 | 0 | 1 | 7 | 0 | 7 |
| BC3D | 7 | 0 | 2 | 7 | 7 | 16 |
| 63C4 | 5 | 0 | 3 | 7 | 7 | 18 |
| 2438 (went out of bounds: ReEntry) | 7 | 0 | 14 | 34 | 6 | 6 |

(speed across the ground, studs/s). It lands, stands, walks at 7, and takes the run up again
after about 3 s. Who walks off a ledge in the first place still depends on confidence
(`Dismount_CasualConfidence` 0.7), as the owner asked.

## Headroom awareness

A Quin is 8 studs tall but its collision ends at about 6.4, so it can stand under a 6.5-8 stud
ceiling with its head inside the part, and lower gaps push against its body.

- **`Modules/HeadroomAwareness`**: `exit(fighter, rootPart, humanoid)` returns nil when there is
  room to stand (8.2 studs over the floor under it), otherwise the nearest spot with a floor at
  its own level and room over it (rings of 8 directions every 4 studs out to 20, the way it
  faces first).
- **`Main`**: in Idle, Fight, Circling, Chase, Retreat and Overwatch, when it is on the ground
  and not sliding, a Quin with no room to stand steers to that spot at 14 studs/s before its
  state does anything else (`LowCeiling` attribute, awareness "No room to stand: getting out").
  A slide under a low bar is not interrupted. Config `CombatConfig.Headroom`.

| Generated arena, 80 s | Before | After |
|---|---|---|
| Samples standing under a ceiling lower than 8.2 studs | 2.13 % (367 of 17203) | 1.38 % (218 of 15833) |
| Separate times | 319 | 180 |
| Longest stay | 0.5 s | 0.7 s |
| Tipped over while there | 0 | 0 |
| "Getting out" started | - | 48 times, 224 ticks |

Strikes in the after run: 443 hit, 42 whiff, 26 blocked, 133 interrupted. No script errors.

## Not shown

- **The stuck-and-rotating bug itself was not reproduced** in either run (nobody tipped, nobody
  stayed over 0.7 s), so the rule is shown to act, not shown to cure that bug. The seeds each
  had only one piece (and its mirror) with a gap a Quin could get under; most low pieces sit
  2 studs off the floor.
- The two runs are different seeds, so the before/after percentages are not a controlled pair.
- Not looked at by eye.
