# Pass 27: procedural arena generation

Owner request:
- **Volume:** ArenaGround (600 × 600) up to 400 studs. Edit-mode parts are replaced only temporarily, never deleted.
- **Fairness:** obstacles and high platforms mirrored on both sides, the same amount each side.
- **Spawns:** 4 options (two edges, two midpoints); scattered but grouped, the same on both sides.
- **Layout:**
  - the central 200 × 200 stays empty;
  - high platforms at most 300 studs up;
  - obstacles randomized in X, Y and Z;
  - not too packed, and traversable (jump points).
- **Show:** a blue hologram that flicks through seeds ("tutututu"), then the good seed locks. Wired to the Arena System menu.
- **Look:** grassy for now; biomes later.

## What was built

**New `ServerScriptService.ArenaGenerator`** (created with MCP `multi_edit`). Tunables are in `ArenaConfig.ArenaGeneration`.

**Layout (pure data, per seed).**
- Spawns: one of 4 spawn options, picked per seed. Each gives TeamAlpha's anchor as a fraction of the arena half size; Beta's anchor is the point mirror.
  - Edge N-S, at (0, 0.8);
  - Edge E-W, at (−0.8, 0);
  - Midpoint NW-SE, at (−0.55, 0.55);
  - Midpoint NE-SW, at (0.55, 0.55).
- **Only Alpha's half is generated.** Every piece is then point-mirrored through the arena centre: position reflected, rotated 180° about Y. Both sides get identical pieces, sizes and heights.
- **Placement rules:**
  - every piece stays clear of the walls (12 studs), the centre square (200 × 200), the mirror line and Alpha's spawn yard (50 studs);
  - pieces keep 18 studs apart sideways, or 10 studs vertically, so a Quin fits through.
- **Pieces per side:**

  | Piece | Count | Size and height |
  |---|---|---|
  | High platforms | 2–4 | Half are laddered (top 24–60 studs). The rest are projectile-jump perches (top 60–300). |
  | Floating blocks | 2–4 | Underside 10–40 studs up, so Quins pass under. |
  | Low platforms | 3–5 | Height 4–10 (a normal jump). |
  | Ground cover | 6–10 | Random size in X, Y and Z; random yaw. |

  Laddered platforms get a spiral of stepping stones (10 × 2 × 10). Each stone is 8 studs up and 13 studs along from the last: a normal jump, since `Jump_MaxReach` is 12.
- **Spawn group:** up to 16 points scattered within 30 studs of the anchor, at least 7 apart, mirrored for Beta.

**Validation.** A 4-stud grid flood fill from Alpha's spawn checks the ground routes.
- A piece blocks walking when it sits below 9 studs (the underpass height) and stands taller than 6.8 studs (the vault height), inflated by half the 6-stud route width.
- Beta's spawn and the centre must be reachable, along with at least 97% of the open floor (no closed pockets).
- Rejected seeds show violet in the hologram, with the reason on the screen.

**Show (inside the ARENA_GENERATION phase, 15 s by default).**
1. A blue scan plane sweeps from the ground up to 400 studs (10% of the phase).
2. **Seed sweep** until 62% of the phase. A new candidate appears every ~0.14 s as Neon blue hologram blocks, with a quarter of them jittering on each switch. The screen shows `SEED 4F7FA9 • EDGE N-S • ROUTES OK` and the progress bar.
3. **Lock:** the first good seed after the sweep pulses 3 times (`SEED … LOCKED`).
4. **Materialize:** a bottom-to-top sweep. Each block flickers, then turns solid: named `OB` (so PlatformCatalogue, SpatialModule and traversal see it), dark grass green, collidable, with a `GenKind` attribute.
5. `ARENA READY • SEED …`. The QuinSpawn pads move to the anchors, `PlatformCatalogue.refresh()` runs, and Workspace `ArenaSeed` holds the seed.

- **SKIP** hurries the sequence: the next good seed materializes in 0.6 s. The phase waits for the sequence, so nobody spawns into a half-built arena, and ARIA's "generation completed" line still comes after it.
- **Optional sounds:** put Sounds named `SeedTick`, `SeedLock` and `Materialize` in `ArenaSoundFX/GenerationFX` and they play; none exist yet.

**Edit-mode layout.**
- When the sequence starts, the parts named in `EditLayoutNames` (`OB`, `highplatform`) on the ground are moved to `ServerStorage.ArenaEditLayoutStash`. That is not replicated, so they disappear for clients.
- When the match stops, the generated blocks are destroyed, the stashed parts return to their parents, and the spawn pads go back. Nothing in Edit mode changes.

**Orchestrator.**
- ARENA_GENERATION runs `ArenaGenerator.runSequence` when the ProceduralTerrain toggle is on.
- Team spawns use `getSpawnPoints`: scattered, mirrored, each fighter facing the other anchor.
- FFA ring spawns stay inside the empty centre.
- `stopMatch` restores the edit-mode arena.

**Menu.** "Procedural Arena Generation (mirrored, seeded)" is now a real toggle (it was a "[not built yet]" stub). `DefaultToggles.ProceduralTerrain` is on.

**Studio hooks.** The Workspace attribute `ArenaGenDevCommand` accepts:
- `run <seconds>`;
- `restore`;
- `check <n>`, which runs layout statistics into `ArenaGenCheck`.

## Measurements (Play)

- **`check 300`:** 300/300 seeds valid, 52.3 pieces on average (about 26 per side), about 15 ms per seed.
- **Standalone run (15 s):**
  - 72 hologram parts at the 4.5 s mark; 34 edit parts stashed.
  - Seed 9DAD5F locked, Edge N-S: 50 OB (Stone 12, Cover 18, Float 4, High 2, Low 10, Perch 4).
  - Highest top 257 studs above the ground.
- **Hologram visibility:** in the first screenshot, ForceField at 0.35 was nearly invisible from the stands. Switched to Neon at 0.55.
- **Colour:** the pieces blended into the green ground, so the greens are now darker (62,104,50 to 44,82,40).
- **Full Arena match (4v4):** the screen stepped through the sequence (36 text changes):
  - `SCANNING ARENA VOLUME`;
  - `SEED … • EDGE N-S • ROUTES OK` …;
  - `SEED 4F7FA9 LOCKED • EDGE N-S`;
  - `MATERIALIZING SECTORS`;
  - `ARENA READY • SEED 4F7FA9`, 19.8 s into the run (the phase ran from 6 to 21 s).
- **Spawns:**
  - Pads moved to (0, −198) and (0, −678).
  - Alpha at (0, −212), (−3, −222), (21, −198), (−16, −207).
  - Beta at (0, −664), (3, −654), (−21, −678), (16, −669), the exact mirror around z = −438.
- **In game (35 s):** all 8 fighters moved 455–2045 studs. Peak heights were 21–35 studs on stones and platforms and up to 396 on projectile jumps. 0 errors.
- **Stop:** 32 OB and 4 highplatform back (all originals), generated folder gone, stash empty, spawn pads back at (158, −605) and (−137, −233).
- **Regression:** 16v16 (`team:16`, which doesn't use the generator), 32 Quins, 0 errors.

## Notes

- **Spawn option names:** "two edges, two midpoints" is read as edge centres (N-S, E-W) and diagonal midpoints (NW-SE, NE-SW). Change `SpawnOptions` if you meant something else.
- **Density:** the layout is fairly open (about 26 pieces per side). Raise the `Pieces.*.Count` ranges for a busier arena; the route check rejects layouts that close off routes.
- **Biomes:** pieces are plain dark-green SmoothPlastic for now. Biomes can become a `Biome` table (colours, materials, piece shapes) chosen per match.
