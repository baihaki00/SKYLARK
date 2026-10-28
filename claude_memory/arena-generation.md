---
name: arena-generation
description: Procedural arena generator (Pass 27): where it lives, its rules, test hooks, and the open choices (spawn option meaning, density, biomes)
metadata:
  type: project
---

2026-10-03, Pass 27 (`2cb07ed`): `ServerScriptService.ArenaGenerator`, tunables in `ArenaConfig.ArenaGeneration`, toggle `DefaultToggles.ProceduralTerrain` (on, Arena System menu).

**What it does:**
- **Layout:** generates Alpha's half, then point-mirrors it through the arena centre. Pieces are named `OB` so the AI's PlatformCatalogue and SpatialModule see them.
- **Kept clear:** the centre 200×200 square and the spawn yards.
- **Climbing:** high platforms up to 60 studs get stepping stones; higher ones (up to 300) are projectile-jump perches.
- **Validation:** grid flood fill from Alpha's spawn.
- **Show:** hologram seed sweep → lock → materialize (Neon blue; dark grass green solids).
- **Edit layout:** stashed to `ServerStorage.ArenaEditLayoutStash` and restored on stopMatch.
- **Spawns:** pads moved; `getSpawnPoints` gives scattered, mirrored points.

**Test hooks:** Workspace attribute `ArenaGenDevCommand` = `run <s>` / `restore` / `check <n>`; `ArenaSeed` shows the locked seed.

**Why:** this was the owner's 3rd batch item, after the fixes and the crowd.

**How to apply:**
- "Two edges, two midpoints" was read as edge centres plus diagonal midpoints; ask if the owner meant otherwise.
- Biomes are planned later: add a Biome table rather than hardcoding.
- Optional sounds go in `ArenaSoundFX/GenerationFX` (SeedTick / SeedLock / Materialize); none exist yet.

Related: [[crowdfx-system]], [[studio-git-export]]

Pass 28 (`852323b`, 2026-10-03):
- **Layout:** denser (about 90 pieces per layout), 4–7 platforms per side at 40–80 wide, walls added.
- **Trees:** cloned from the edit-mode Workspace `Tree` model (stashed and restored like OB), placed on the ground and on wide platform tops.
- **Glitch FX:** transparency spread, tears, white flashes, flicker, ParticleEmitter static, and scanner frames. Full-arena neon planes were rejected because they washed everything cyan.
- **Owner baseline (2026-10-03):** crowd mix defaults, and a hologram hover of ±1.75 studs. "3-4 studs" was read as total travel; ask if the owner meant amplitude.
