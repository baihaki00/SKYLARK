# Phase 0: Baseline of today's fights

The reference every later phase of [QUIN_CREATURE_DESIGN.md](../QUIN_CREATURE_DESIGN.md) is compared against: the 16v16 and 1v1 the owner already likes, measured on code at `fce6de0` (Pass 73b).

- **Probe:** [scripts/flow_probe.lua](../scripts/flow_probe.lua). Its definitions are in the file's header. Later phases re-run the same file.
- **How it was run:** Arena System, instant match, generated arena (random seed), Studio Play.
  - The probe is served from the repo (`python -m http.server 58918` in `scripts/`). On the Server, it is fetched into a ModuleScript in ServerStorage with `LABEL` / `DURATION` / `MIN_ALIVE` as parameters, then required.
  - 16v16: `TeamSize 16`, 240 s.
  - 1v1: `Mode 1vs1`, 150 s, stops if a fighter falls (none did).

## Results

| Measure | 16v16 (seed 7D4C6F) | 1v1 A (28CB30) | 1v1 B (566DFC) | 1v1 C (8FB214) | 1v1 mean |
|---|---|---|---|---|---|
| **Strikes** | 1660 | 79 | 73 | 80 | 77 |
| Hit / whiff / blocked / interrupted % | 68 / 7.1 / 5 / 19.7 | 65.6 / 6 / 4 / 24.2 | 70 / 5.5 / 4.4 / 20 | 64.8 / 9.5 / 5.3 / 20.2 | 66.8 / 7 / 4.6 / 21.5 |
| Strikes per Quin-minute | 13.9 | 16.2 | 15.0 | 16.4 | 15.9 |
| **Engaged** (target within 20 studs), % of time | 47.3 | 59.1 | 47.0 | 54.0 | 53.4 |
| **Standing to decide**, % of engaged time | 9.5 | 6.8 | 9.2 | 9.4 | 8.5 |
| Action chain, mean actions between stands | 15.5 | 18.9 | 17.1 | 15.3 | 17.1 |
| Chains of 3+ actions, % | 85 | 100 | 100 | 87.5 | 96 |
| **Answers:** strikes within 0.6 s of the target's own action, % | 40.7 | 37.9 | 32.8 | 32.5 | 34.4 |
| Speed when a strike starts, median (studs/s; a run is 40) | 11 | 10 | 10 | 11 | 10 |
| **Speed kept**, Chase → Fight (after 0.3 s / before) | 0.37 | 0.27 | 0.46 | 0.34 | 0.36 |
| Speed kept, Knockback → Recovery | 0.16 | 0.16 | 0.16 | 0.17 | 0.16 |
| **Range bands**, % time contact / beat / closing / far | 22 / 26 / 25 / 27 | 30 / 29 / 13 / 28 | 29 / 18 / 17 / 36 | 28 / 25 / 13 / 33 | 29 / 24 / 14 / 32 |
| Band changes per Quin-minute | 46.6 | 45.7 | 58.0 | 48.1 | 50.6 |
| **In the air**, % of time | 11.3 | 9.3 | 10.8 | 12.2 | 10.8 |
| Air entries per Quin-minute | 6.4 | 4.5 | 6.5 | 5.7 | 5.6 |
| High ground (3+ studs above the floor), % | 14.6 | 4.5 | 2.9 | 0.9 | 2.8 |
| Wall runs per Quin-minute | 0 | 0 | 0 | 0 | 0 |
| Air dashes / dashes / slides / projectile jumps / guards per Quin-minute | 0.1 / 1.5 / 0.7 / 3.0 / 4.0 | 0 / 1.4 / 1.2 / 1.6 / 6.5 | 0 / 2.2 / 0.8 / 2.2 / 4.3 | 0 / 0.8 / 0.8 / 2.4 / 4.5 | 0 / 1.5 / 0.9 / 2.1 / 5.1 |
| Knockdowns per Quin-minute | 2.67 | 3.71 | 3.70 | 3.08 | 3.50 |
| Deaths in the window | 0 | 0 | 0 | 0 | 0 |
| **Rhythm:** arena activity mean % / CV / swings per min | 30 / 0.26 / 10.9 | 38.5 / 0.70 / 13.3 | 36 / 0.74 / 15 | 39.5 / 0.67 / 13.3 | 38 / 0.70 / 13.9 |
| Server frame, median ms | 5.9 | 4 | 4 | 4 | 4 |

**Time by state, %:**

| | Fight | Chase | Circling | Overwatch | Retreat | Proj. jump | Recovery | Knockback | Mid-air clash |
|---|---|---|---|---|---|---|---|---|---|
| 16v16 | 28.5 | 26.3 | 11.5 | 8.4 | 4.2 | 7.7 | 6.7 | 4.4 | 1.5 |
| 1v1 mean | 36.0 | 26.7 | 14.0 | 0 | 0 | 8.2 | 9.6 | 5.0 | 0 |

**Also recorded:**
- **Client frame during the 16v16 (Studio, one process with the server):** median 25 ms, p95 32 ms. Pass 62 measured ~10 ms; the generated arena or the camera position may explain it. To recheck before blaming any phase.
- **Earlier 16v16, same code, before the probe's band dead zone was added** (seed 5ABAA6): hit 70.9 %, standing 9 %, answers 39 %, air 10 %, high ground 14.9 %. It agrees with the run above; its band changes (56.5) are not comparable.

### The player's body (Pass 73b, AI frozen, keys through the MCP)

| | Result |
|---|---|
| Run, 0 → 40 studs/s | ~0.7 s |
| Stop from 40 | ~0.45 s |
| 180° reversal (brake, pivot, drive out) | ~0.6 s |
| 90° change while running | carved in ~0.6 s |
| Facing vs velocity | 0.98–1.00 |
| Owner's verdict | "turning is so heavy" |

## What the baseline says, against the design

- **They rarely stand still to decide** (8–10 % of engaged time) and chain many actions. The *stop-and-decide* reset is mostly not a standing pause.
- **The resets are in momentum.**
  - Entering a fight keeps only about a third of the speed (Chase → Fight 0.27–0.46).
  - Strikes start from ~10 studs/s while a run is 40: they plant, then strike.
  - A knockdown keeps 16 % into the get-up.

  This is where phase 2 (continuity) would show.
- **Air is mostly projectile jumps** (about 10 % of the time airborne). Wall runs never happen in natural play (0 in 23 Quin-minutes of 1v1 and 119 of 16v16). Air dashes are rare (0.1 per Quin-minute). The 3D fighting the vision wants exists as moves but barely in play.
- **Fights are long.** No deaths in 150–240 s (1000 health); the pace the owner likes includes this.
- **Answers:** a third to 40 % of strikes come right after the target's own action. This number includes trades; phase 4 should change its *kind*, not only its size.
- **Rhythm:** the 1v1 is bursty (activity varies ±70 %, ~14 swings a minute). The 16v16 is smooth as a whole (±26 %) because many fights overlap.
- **Range:** time spreads across all four bands, with a quarter to a third "far" from the target (chasing, being thrown away).

## Still needed from the owner: recorded fights

Roblox has no replay, so the visual half of the baseline is the owner's screen recordings:
- **2–3 clips** of the 1v1 (the first judge), and **1–2** of the 16v16;
- each a fight or moment the owner *likes*;
- saved in `QUINCORE_BACKUP/baseline/` (`.mp4` is gitignored, so they stay local).

Each phase's changes will be watched against them. A fixed arena seed (`ArenaConfig.ArenaGeneration.FixedSeed`) can make later recordings comparable on the same arena.
