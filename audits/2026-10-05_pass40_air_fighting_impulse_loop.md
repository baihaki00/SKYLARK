# Pass 40 (2026-10-05): Quins striking at air from out of reach

Owner: "two Quins not being close enough to actually hit each other ... playfully doing strike
motion but never hitting".

## Measured

- First match of a Play session: normal. 695 strikes in 75 s: hit 71 %, whiff 6 %, blocked 5 %,
  interrupted 18 %; bodies 4.4 studs apart at a hit.
- After `team:16` was started again a few times in the same session: **1042 whiffs of 1046
  strikes in 30 s**, all 32 Quins alive, 30 of them in Fight, standing still (speed 0) 7.6 studs
  apart. Nobody was knocked out.
- On a stuck fighter the `ImpulseLV` mover sat at zero force through four wind-ups in a row, and
  30 Quins carried a mover that was never released.

## Cause

`ImpulseModule` moves the body for every lunge (the step into a strike), spacing step back,
flinch and knockback skid, from one shared Heartbeat loop. The loop was connected inside
`bodyFor`, so it belonged to the script that made the first push: `Main`, which is cloned into
each Quin. A connection dies with its script. When that Quin was removed (knocked out and cleaned
up, or a new match) the loop stopped for every Quin, and because the module still held the dead
connection it was never started again. Strikes were still thrown inside the 9-stud strike range,
but the step-in that closes to 4.8 studs did nothing.

This is not a product of the recent strafe or body-layer passes: the pattern has been there
since the module was written. It also means that any match that outlived the first owner of the
loop had no lunges, step backs, flinches or skids, which will have fed the late-game stalling
looked at in Pass 35.

## Fix

- `ImpulseModule.start()`, called from `ServerScriptService.Server` (which lives all session,
  next to `SocialSystem.start()`): the loop is owned there and is not disconnected when idle.
- `bodyFor` no longer assumes the loop: it reconnects if the connection is missing or dead.

## After (same session shape: three matches started one after another, measured on the third)

| Window | Strikes | Hit | Whiff | Blocked | Interrupted |
|---|---|---|---|---|---|
| 0-25 s | 214 | 67 % | 5 % | 10 % | 18 % |
| 25-50 s | 239 | 66 % | 6 % | 7 % | 21 % |
| 75-103 s | 259 | 69 % | 7 % | 3 % | 21 % |

Movers in use: 6, all with force (30 stale ones before). No server errors.

## Not checked

- No knockout happened in the 103 s measured, so "the loop survives its first owner being
  knocked out" is covered by the match restarts (which remove every Quin), not by a death in
  play.
- Other module-level loops started from a Quin's script may have the same weakness
  (`DebugDraw` connects a Heartbeat loop in its own start-up path; not audited).
- Knockout pace over a full match was not re-measured.
