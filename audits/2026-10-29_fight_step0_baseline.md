# Fight Programme step 0: baseline

The reference every later step of [FIGHT_PROGRAMME.md](../FIGHT_PROGRAMME.md) is compared against, measured 2026-10-29 on today's code (Studio, QUIN_COMBATV4, after the SurveyIdle removal). QuinCore was not changed for this.

- **Probes:**
  - [scripts/flow_probe.lua](../scripts/flow_probe.lua): the Phase 0 probe, unchanged, so its rows compare with [the 2026-10-07 baseline](2026-10-07_phase0_baseline.md).
  - [scripts/fight_probe_server.lua](../scripts/fight_probe_server.lua) (new): move variety, root overlap, tempo, phrases, drift, re-entries. Definitions in its header.
  - [scripts/fight_probe_client.lua](../scripts/fight_probe_client.lua) (new): limbs and torsos inside each other on the bodies the player sees. Definitions in its header.
- **How it was run:**
  - Serve `scripts/`: `python -m http.server 58918 --bind 127.0.0.1 --directory scripts`.
  - Start a match from the Server: Workspace `ArenaDevCommand` `start {"Mode":"1vs1","Toggles":{"InstantMatch":true}}`, or `{"Mode":"TeamBattle","TeamSize":16,...}`. **Pass Mode every time:** a start without it keeps the previous mode.
  - On the Server, fetch each probe with `HttpService:GetAsync`, put it in a new ModuleScript in ServerStorage, and require it. For the flow probe, its `LABEL` / `DURATION` / `MIN_ALIVE` lines are replaced first. `loadstring` is not available on the Server.
  - Paste the client probe into an execute_luau call on the Client. Its result is ready a few seconds after the server's.
  - Durations: 1v1 150 s (stops if a fighter falls; none did), 16v16 240 s.
- **Render mode:** the default `QuinRenderMode` is now **Direct**, which draws the QuinServer bodies in place; there is no ghost clone. The client probe handles both modes.

## Results

### Move variety, spacing and tempo (new)

| Measure | 1v1 A (0B7F04) | 1v1 B (D989AB) | 1v1 C (635143) | 1v1 mean | 16v16 (EE6E9B) |
|---|---|---|---|---|---|
| Strikes (counted on every change of `Attacking`) | 166 | 146 | 143 | 152 | 2743 |
| **Same clip as its own last strike**, % | 22.2 | 23.2 | 19.5 | 21.6 | 21.6 |
| Same clip three times in a row, % | 6.6 | 8.9 | 4.1 | 6.5 | 5.5 |
| Punch / kick, % | 54.8 / 45.1 | 51.3 / 48.6 | 52.4 / 47.5 | 52.8 / 47.1 | 52.2 / 47.7 |
| Strike clips used per Quin (of 8) | 8 | 8 | 8 | 8 | 8 |
| **Roots under 3 studs** (bodies overlap), % of engaged time | 9.6 | 13.1 | 4.1 | 8.9 | 9.0 |
| Roots under 4.8 studs (inside the lunge stop), % | 28.9 | 38.1 | 27.4 | 31.5 | 27.7 |
| **Tempo:** fast / mid / slow, % of engaged pair time | 82.5 / 10.7 / 6.7 | 92 / 4.1 / 3.8 | 82.1 / 12.1 / 5.6 | 85.5 / 9 / 5.4 | 83.2 / 9.7 / 6.9 |
| Fast ↔ slow switches per pair-minute | 37.8 | 20.5 | 29.8 | 29.4 | 37.2 |
| **Phrases:** count / median length s / p90 s | 26 / 1.1 / 4.9 | 19 / 1.0 / 8.1 | 21 / 1.2 / 6.7 | 1.1 s | 571 / 0.9 / 3.9 |
| Strikes per phrase, median | 5 | 4 | 4 | 4 | 3 |
| Gap between phrases, median s | 2.1 | 4.0 | 3.6 | 3.2 | 2.5 |
| **Re-entries** (apart past 12 studs, back under 8) per pair-minute | 9.8 | 13.7 | 12.6 | 12.0 | 12.4 |
| **Drift:** pair midpoint wander in 10 s, median / p90 studs | 13.9 / 13.9 | (no 10 s engaged spell) | 14.8 / 14.8 | ~14 | 19.4 / 53.5 |
| Pair midpoint speed, median studs/s | 2.6 | 2.6 | 2.3 | 2.5 | 5.0 |

### The drawn bodies (new, client)
Run A has no client numbers: the probe waited for a ghost folder that Direct mode doesn't have.

| Measure | 1v1 B | 1v1 C | 16v16 |
|---|---|---|---|
| Close pair frames sampled (roots under 12 studs) | 2251 | 2206 | 22821 |
| **A limb inside the other's torso or head**, % | 5.4 | 3.3 | 3.6 |
| ... while one of them is striking / while neither is, % | 6.2 / 2.1 | 4.2 / 0.4 | 4.6 / 1.1 |
| **Torsos inside each other**, % | 9.2 | 3.8 | 6.7 |
| Limb depth inside, median / p90 studs | 0.45 / 0.58 | 0.45 / 0.62 | 0.46 / 0.59 |
| Spine length (Hips to Neck), studs: torso radius taken as 0.72 | 2.39 | 2.41 | 2.40 |
| Client frame, median / p90 ms | 9.2 / 10.6 | 9.6 / 10.9 | 21.3 / 26.5 |

### The Phase 0 measures, re-run (flow_probe.lua)

| Measure | 1v1 mean (A / B / C) | 1v1 on 10-07 | 16v16 | 16v16 on 10-07 |
|---|---|---|---|---|
| Hit / whiff / blocked / interrupted % | 64.8 / 2.5 / 3.4 / 29.1 | 66.8 / 7 / 4.6 / 21.5 | 65.1 / 9.4 / 2.2 / 23.2 | 68 / 7.1 / 5 / 19.7 |
| Strikes per Quin-minute (10 Hz sampled, see the note below) | 22.1 | 15.9 | 19.8 | 13.9 |
| Engaged, % of time | 55.1 | 53.4 | 47.9 | 47.3 |
| Standing to decide, % of engaged | 10.7 | 8.5 | 12.3 | 9.5 |
| Action chain, mean | 14.2 | 17.1 | 13.2 | 15.5 |
| Answers, % | 36.5 | 34.4 | 39.3 | 40.7 |
| Speed when a strike starts, median | 8–9 | 10 | 9 | 11 |
| Speed kept, Chase → Fight | 0.40 (0.70 / 0.39 / 0.12) | 0.36 | 0.77 | 0.37 |
| Bands contact / beat / closing / far, % | 40 / 15 / 16 / 28 | 29 / 24 / 14 / 32 | 29 / 19 / 23 / 27 | 22 / 26 / 25 / 27 |
| In the air, % | 6.5 | 10.8 | 9.6 | 11.3 |
| High ground, % | 0.9 | 2.8 | 6.5 | 14.6 |
| Wall runs per Quin-minute | 0.13 | 0 | 0 | 0 |
| Knockdowns per Quin-minute | 2.77 | 3.50 | 2.38 | 2.67 |
| Rhythm: activity mean % / CV / swings per minute | 42 / 0.77 / 10.9 | 38 / 0.70 / 13.9 | 37 / 0.24 / 6.7 | 30 / 0.26 / 10.9 |
| Time in Fight / Chase / Circling, % | 49 / 22 / 13 | 36 / 27 / 14 | 41 / 23 / 11 | 29 / 26 / 12 |
| Deaths in the window | 0 | 0 | 0 | 0 |
| Server frame, median ms | 9–10 | 4 | 21.8 | 5.9 |

**Notes:**
- The flow probe samples at 10 Hz and misses quick strikes: it counted 112 / 103 / 96 strikes against the fight probe's 166 / 146 / 143. Use the fight probe's count from now on. The flow row is kept for comparison with 10-07.
- **Frame times need a recheck before anything is blamed on them.** For its first ~3 minutes, the 16v16 ran next to a second set of probes started by mistake (on a match that was still 1v1). The client probe also ran in the same Studio process.

## What the baseline says, for the steps ahead

- **Clipping is real but not constant (step 1).**
  - Bodies are closer than their own radii (roots under 3 studs) for about 9% of engaged time.
  - On the drawn bodies, torsos sit inside each other in 4–9% of close frames. A limb is inside a body in 3–5%, mostly during strikes, by about 0.45 studs: about a fist's depth.
  - A third of engaged time is spent closer than the 4.8-stud lunge stop. The stop alone isn't holding the spacing.
- **Same-move use is close to random, not answers (steps 4 and 6).**
  - Every Quin uses all 8 strike clips. Punches are half of all strikes, from only two clips.
  - The repeat rate (22%) is a bit above what a random pick would give (about 17% with these shares).
- **Fights come in short bursts with a lot of re-entry (step 6).**
  - Phrases last about 1 s, with 3–5 strikes, and 2.5–3.5 s between phrases.
  - A pair comes apart and re-engages about 12 times a minute.
  - 1v1 fights wander about 14 studs per 10 s. The 16v16 moves more (median 19, p90 54).
- **The tempo split is provisional.** By this probe, 83–92% of engaged time is "fast" and only 4–7% "slow". That doesn't match the owner's sense of slow, deliberate moments. Either those moments happen outside 20 studs (Circling further out), or the definition is too broad ("fast" includes any strike by either side). Calibrate it against the owner's recorded fights before using it as a gate.
- **Since 10-07:** more time at contact and in Fight, fewer whiffs in the 1v1 (2.5%), more trades (interrupted 23–29%), less time in the air.

## Still needed from the owner: recorded fights

As in Phase 0, the visual half of the baseline is the owner's screen recordings:
- 2–3 clips of a 1v1 and 1–2 of the 16v16;
- each a moment the owner likes;
- saved in `QUINCORE_BACKUP/baseline/` (`.mp4` is gitignored).

They are also what the tempo measure gets calibrated against.
