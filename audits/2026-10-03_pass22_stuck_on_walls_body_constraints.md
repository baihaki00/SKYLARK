# Pass 22: body constraints, starting with Quins "stuck on tall walls like a spider"

Base: pass 21f (`debb367`). Plan: `plans/cached-orbiting-flurry.md`, items A-G.

## A. Stuck at high obstacles

### Measured (16v16, 2 min, server; Quins more than 20 studs up, by the OB part under them)
Quins dived onto the **tops of the arena's tall thin walls** and stayed there in Overwatch:
- 7 × 18 wall tops at 57 and 107 studs up;
- an 8 × 36 slab top at 80 studs up.

Each perch lasted **15-30 s**. Seen from the ground, that is a Quin stuck up a wall.

### Cause
- `OverwatchState.heldPlatform` accepted any `PlatformCatalogue` platform at least 12 studs above the floor.
- The catalogue's minimum top width is 5 studs, so wall and pillar tops counted as lookouts worth holding.

### Fixes
- **Overwatch** only holds tops at least `Overwatch_MinTopWidth` (10) studs wide in both directions. A Quin landing on a narrower top goes on chasing and drops down.
- **ProjectileJump dive (every style except 5):** the dive had no path check and no time limit, so a dive line crossing a tall obstacle pressed the body into the wall face with unlimited force, indefinitely. Not caught in a run, but it is a real failure mode in the code. Three guards:
  - **wall probe:** the dive probes ahead along its line (`ProjectileJump_DashWallProbeTime`). A wall (|normal.Y| < 0.5) goes to Impact, which drops the body, easing off the wall face;
  - **stall guard:** a driven phase that moves less than 1.5 studs in 0.4 s comes down (`ProjectileJump_StallTime`, `_StallDistance`);
  - **hard cap:** a whole jump lasts at most `ProjectileJump_MaxStateTime` (8 s).
  - The debug attribute `PJGuard` shows which guard fired.

### After (16v16, 2 min)
- Narrow tops (7 × 18, 7 × 25, 2 × 8 × 36): left within about 1 s (Chase).
- Overwatch now held only the big tops (47 × 59 block, 70 × 77 slabs).
- 107 projectile jumps; the stall guard fired once; 0 errors.

### Found during regression (Play As Quin)
- **Every punch errored:** `executePlayerAttack` passed an options table to `AnimationModule.play`, which takes positional arguments ("Unable to assign property Priority"). Fixed.
- **Release fired 21 times:** `Release` yields on the server while the per-frame loop, seeing the costume gone, called release again every frame. Each call reloaded the avatar, which could undo the next possession. The session now stops locally first, then releases once.
- **Verified:** possess → punches (no error) → release (once) → possess again. Arena System 4v4 reaches IN_GAME with 8 Quins and 0 errors.
