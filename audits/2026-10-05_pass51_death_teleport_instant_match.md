# Pass 51 (2026-10-05): death, deployment teleport, instant match (items 15, 16)

## Death (item 15)

Owner: the death animation clips through the ground; do not turn anything off during death, only
after the animation is finished; add a holographic glitch effect (check VfxModule).

**Measured before** (two Quins killed in a 4v4):

- About 1 s after the knockout the root dropped from 4.9 studs above the floor to 0.9 (a dead
  Humanoid stops holding its root up) while the Standard death clip was lowering the body from
  that same root: the feet ended 1.0 to 3.3 studs under the floor.
- No fade of any kind (the dissolve only exists in the unused ghost render mode).
- The body was removed exactly 3.0 s after the knockout, whatever the clip was doing.
- `VfxModule` had no glitch or hologram effect for Quins; only the arena generator has one, for
  its own pieces.

**Now** (`States/DeathState`, `VfxModule.holoGlitch`):

- The body is held where a living Quin stands (an AlignPosition at floor + stand height and an
  upright AlignOrientation on the root). A Quin that dies in the air is brought down to the
  floor at 90 studs/s.
- The death clip plays to its end and is held on its last frame.
- It lies there 0.6 s (`Death_RestTime`), breaks up in the glitch for 1.1 s (`Death_GlitchTime`)
  and only then is removed.
- `VfxModule.holoGlitch(model, duration, "out" | "in")`: a cyan Highlight whose fill and outline
  flicker, the body's transparency following the dissolve with random flicker and "tears" (gone
  for a beat). Server-side, so every client sees the same.

**Measured after** (three Quins):

| | Root above the floor | Lowest bone above the floor | Glitch | Removed |
|---|---|---|---|---|
| Standard, killed mid projectile jump (318 studs up) | 5.4 once down (3.3 s) | 0.2 | from 4.9 s | 6.29 s |
| On the spot | 5.5 throughout | 0.2 to 1.1 | from 4.6 s | 5.72 s |
| Standard, lifted 30 studs and killed | 5.4 once down (2.1 s) | 0.2 to 0.6 | from 4.9 s | 6.30 s |

No bone went under the floor. No script errors.

## Deployment teleport (item 16)

Fighters were already placed only in the TELEPORTING_QUINS phase (after the preparation room),
all in one frame.

**Now** (`ArenaSystemOrchestrator.spawnFighters`): every placement is a job; the jobs are
shuffled across both sides and run one at a time over `ArenaConfig.Teleport.Window` (5 s, at most
80 % of the phase), each fighter taking shape with `holoGlitch(..., 0.9, "in")`. A SKIP places
the rest at once.

**Measured** (8v8, an 8 s teleport phase): 16 fighters arrived between 3.1 s and 7.9 s after the
start command, 0.3 s apart, teams mixed (B B B A A A A A B B A B A B A B), each with the glitch
on it. The fight started at 12.3 s.

## Instant match

New toggle `InstantMatch` (Arena menu: "Instant Match (skip the lead-in, straight to the
fight)", off by default). While it leads in, the ceremonial toggles (announcer, fireworks, music,
countdown) read as off and the lead-in phases last no time (generation 1 s, teleport 0.5 s);
fighters are placed at once. From the start of the fight it is an ordinary match.

**Measured:** 16 fighters placed at 1.0 s, fight started at 2.7 s, all 16 active. No errors or
orchestrator warnings.

## Not shown

- Not looked at by eye: how the glitch reads, and the straight 90 studs/s descent of a Quin that
  dies high in the air (it plays its collapse on the way down).
- The teleport and instant match were started through the dev hook, not the Arena menu; the new
  menu row was not clicked.
- The procedural layers on the client still stop for a dead Quin (look, feet). Nothing the death
  clips need was found to depend on them.
- "Only teleport during aria_teleporting": the placement starts when the phase starts, alongside
  ARIA's line, not after the line finishes.
