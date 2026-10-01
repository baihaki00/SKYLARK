# Pass 7 (2026-10-01): debug overlays (plan phase 2)

Studio backup: `ServerStorage.backup_pre_16v16audit7_20261001`.

## What it is

The Spectator HUD (H) has a panel of checkboxes, one per overlay layer, plus
"All Quins (off: spectated only)". Every layer starts off.

| Layer | Source | Shows |
|---|---|---|
| Overhead label | client | name, state, HP, energy, speed, tactical state, obstacle report |
| Target + line of sight | client | eye-to-eye line to the target, green with sight, red without |
| Last seen position | client | ring + line to where the target was last seen, while unseen |
| Velocity + facing | client | half a second of travel (cyan) and facing (white) |
| Flight prediction | client | ballistic arc of a body in flight and its landing point |
| Raycasts | server | every ray a Quin casts: red to the hit, green when nothing was hit |
| Steering goal + heading | server | where it is told to go (yellow) and its turn-limited heading (orange) |
| Pursuit / intercept | server | predicted target position (magenta), actual goal (white), pace reason |
| Jump plans | server | the arc a jump was launched on, with type, height and distance |
| Retreat options | server | the eight open-ground candidates by score, and each escape objective with its score |
| Decision scores | server | tactical state, chosen action, top three scores |

## How it works

- `Modules/DebugDraw` (new, shared): reasoning code submits lines / spheres / text to a named
  layer for a Quin. The server only records a primitive when some client has that layer on for
  that Quin, batches every 0.1 s (700 primitives per client per batch) and sends it over
  `QuinCore.DebugDrawEvent` (a RemoteEvent created in the place). `DebugDraw.raycast(owner, ...)`
  is `Workspace:Raycast` plus the Rays layer; the 44 raycasts in SpatialModule, TraversalModule,
  RetreatTacticsModule, ChaseState, WallRunState and ProjectileJumpState now go through it.
- `Modules/RuntimeVisualizer` (rewritten, client): layer switches, scope, pooled immediate-mode
  drawing. Client layers are computed from replicated state; server layers are drawn as received.
- New layers register by adding an entry to `DebugDraw.Layers` and calling `DebugDraw.line /
  sphere / text` (later phases: attention, memory, routes).
- The old per-ray debug parts (`Workspace.Debug_Rays`) are gone from SpatialModule.

## Verified

- All 11 layers on for one Quin: lines, spheres and rays render (screenshots); no script errors.
- "All Quins": ~1,400 lines + ~580 spheres on screen; Studio frame rate 60 -> 40 on both sides.
- With no layer on, nothing is recorded or sent.
- Text labels: the BillboardGuis exist with the right text, but the screenshot tool used for
  verification does not capture any BillboardGui, so they were not confirmed visually.

Two rendering traps found on the way: an AlwaysOnTop adornment with a non-default `ZIndex` is
not drawn at all, and adornments are culled with the part they adorn (an anchor at the world
origin or Terrain draws nothing from across the arena) — the pools use an invisible anchor part
kept in front of the camera.

## Ghost torso (item 1 from the owner's list) — actual cause

The mesh fidelity change in pass 6 was not it. `QuinSpawner` took its templates from rigs
standing in the Workspace (`Workspace.QuinMale`, `Workspace.QuinFemale`,
`ArenaOne.QuinMale`), and two more test rigs (`ArenaOne.QUINTEST`) stood there too: five live,
unanimated, unanchored bodies in a T-pose that physics moved around in view of the spawn.
The spawner now uses `ReplicatedStorage.QuinType` only (identical rigs), and the five world rigs
were moved to `ServerStorage.WorldRigs_removed_20261001` (kept, not deleted).

## Noted for later phases

- `RetreatTacticsModule`'s open-ground escape target is 35 studs away and
  `RetreatSearchRadius` is 30: retreat is scored inside a 30-35 stud bubble in a 600-stud arena.
