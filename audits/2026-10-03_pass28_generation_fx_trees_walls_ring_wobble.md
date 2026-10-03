# Pass 28: crowd baseline, slower hover, ring "coin dance", generation glitch FX, denser arena with walls and trees

## Changes

**Crowd defaults.** The owner's slider baseline is now the default in `ArenaConfig.CrowdFX`:

| Setting | Value |
|---|---|
| `Volume` | 0.20 |
| `BedVolume` | 0.31 |
| `LayerVolume` | 0.58 |
| `ChantVolume` | 0.37 |
| `ReactVolume` | 0.61 |
| `MajorVolume` | 0.87 |
| `AnthemStemScale` | 0.25 |
| `DuckMultiplier` | 0.15 |

**Hover** (`LiveFeedScreen`).
- Globe and screen: ±1.75 studs (3.5 studs of travel; it was ±10 and ±14).
- Speed: 0.30 and 0.34 rad/s (it was 0.48 and 0.58).

**Ring "coin dancing on a table".** The ring's lean direction travels round the globe (`RingPrecessSpeed` 0.35 rad/s). The lean itself breathes between `RingTiltMin` 6° and `RingTiltMax` 18°, capped so the ticker stays readable (`RingTiltPulseSpeed` 0.45).

**Seed-sweep FX** (`ArenaGenerator`). Each candidate switch:
- spreads block transparency over 0.12–0.85;
- jitters 25% of blocks;
- tears 30% (stretched sideways, squashed);
- flashes 12% white.

Between switches, 15% of blocks blink (nearly gone, or popping bright) 18 times a second. Every hologram block has a "TV static" ParticleEmitter snow inside it (sparkle texture, 0.04–0.12 s life, rate by volume, 8–45 per second).

- **Scanner frames:** three neon bars run round the arena edge and jump height on every switch. Full 600×600 neon planes were tried first and washed the whole arena cyan.
- **Lock:** 3 white flashes.
- **Materialize:** each block's static is removed as it turns solid.

**Denser layout** (per side):

| Piece | Count | Notes |
|---|---|---|
| High platforms | 4–7 | 40–80 wide (was 2–4 at 26–56) |
| Floating blocks | 3–6 | |
| Low platforms | 4–7 | |
| Cover | 10–16 | |
| Walls (new) | 3–6 | 30–70 long, 3–5 thick, 12–28 tall |

Spacing went from 18 to 14 studs. The route check still guards traversal.

**Trees.**
- **Template:** a clone of the edit-mode Workspace model `Tree` (`ArenaGeneration.Trees.Template`).
- **Placement:** 4–7 on the ground per side. Platforms at least 34 wide get one 60% of the time.
- **Size and spacing:** scale 0.85–1.2 with random yaw, a 12-stud footprint kept free, and an 8-stud trunk that counts in the route check.
- **Show:** in the hologram each tree is a trunk plus a canopy block. When it materializes, the real tree fades in on the spot.
- **Stash:** edit-mode trees on the arena floor (`EditLayoutModels`) are stashed and restored like the OB parts. Trees outside the arena are untouched.

## Measurements (Play)

- **`check 200`:** 200/200 valid, 89.8 pieces on average (was 52.3).
- **Standalone run, mid-sweep:** 154 hologram blocks, 130 with static on, 3 scanner frames; 42 edit items stashed (8 of them trees).
- **Locked seed 074470:** 92 OB (Stone 24, Wall 6, Cover 32, Float 10, High 4, Low 12, Perch 4) and 12 trees, 4 on platforms. No leftovers.
- **Client:** ring tilt 8.7–16.5°, lean direction −101° → −43° → −5° → 32° over 10 s.
  - Hover measured 6.6 studs of travel at ±3.5; halved to ±1.75 after.
- **Full match** (seed ED5D7F): IN_GAME with 0 errors.
  - All 8 fighters moved 313–1333 studs in 30 s.
  - Peak heights reached 22, 203–210 and 353–386 (platforms and perches).
- **16v16:** 32 Quins, 0 errors.

## Sound prompts (ElevenLabs sound effects) for `ArenaSoundFX/GenerationFX`

| Sound | Prompt |
|---|---|
| `SeedTick` | short digital glitch blip, hologram data flicker, 0.15 s, crisp, sci-fi UI |
| `SeedLock` | futuristic hologram lock-in, bright confirming chime with a bass thump, 1 s |
| `Materialize` | sci-fi energy materialization sweep, rising shimmer into a solid whoosh, 3 s |
| `ScanSweep` (optional, not wired) | low hologram scanner hum rising in pitch, 1.5 s |
