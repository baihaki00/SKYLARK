# Pass 72: Strikes read their markers (hit window, free at Recover)

The owner asked for the marker reader: contact over the HitStart–HitEnd window, and the Quin freed at `Recover`. `Whoosh` is not used yet, by the owner's choice.

## How it works

**`Modules/StrikeMarkers` (new):**
- Reads `HitStart`, `HitEnd` (and the HitStart limb) and `Recover` from each strike clip with `KeyframeSequenceProvider` (~0.4 s per clip on the server).
- Caches them per asset.
- `Server.server.lua` preloads every clip in `AnimationConfig.Attacks` at server start.
- `get(id)` never yields. A clip not read yet, or without a HitStart/HitEnd pair, returns nil, and the strike uses its config ratios.

**`FightState.executeAttack`, with markers:**
- The wind-up (`AttackWindupUntil`, step-in, punch sound) ends at `HitStart`.
- At `HitStart` the box in front is cast, then again every frame until `HitEnd`.
- Each body is struck once, with damage on the frame of contact.
- The window closes early once the target itself is met (hit, blocked or dodged), or if the Quin leaves Fight or dies.
- A whiff is called at `HitEnd`, and the whiff-recovery cut follows as before.
- At `Recover`: `actionEndTime` and `attackFinishTime` are set, `Attacking` goes false, and the Quin may act and move. The clip's settling tail is blended over by whatever comes next.

**Without markers:** unchanged (one check at `impactRatio`, free at `cancelRatio`, done at the clip's end).

**Switch:** `CombatConfig.Combat_UseStrikeMarkers` (true). Debug attribute: `StrikeTiming` = "markers" | "ratios".

## Measured (16v16, 100 s)

| | Pass 71 (ratios) | Pass 72 (markers) |
|---|---|---|
| strikes | 807 | 1038 |
| hit | 67 % | 71 % |
| whiff | 8 % | 6 % |
| blocked | 4 % | 5 % |
| interrupted | 21 % | 19 % |

- **All 1038 strikes used markers**, and no marker warnings or errors were logged.
- **Hits landed after the window's first frame:** 20 of 734. Median 0.007 s, max 0.17 s after `HitStart`. These are the ones a single check would have missed.
- **About 29 % more strikes:** a Quin used to count as attacking until the clip ended, and is now free at `Recover`.

## Not done

- `Whoosh` (owner: later), `Windup` (could drive defenders' read of the attack), `Cancel`.
- Limb-following hitboxes (the HitStart limb is read and stored but not used: the hit box is still the box in front of the body).
- Other strike users (desperate counter, mid-air clash, specials) still use their own timing.
