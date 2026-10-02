# Pass 18: the owner's MovementTestArena courses (skid, hurdle, slide-under, stepping stones, laps)

Base: pass 17 (`a84134a`) + WIP `196e57c`.

## Owner requests
- Skid-over only for obstacles 3-5 studs tall; jumps take everything else.
- Above 11 studs: "you figure it out".
- Lock the Y axis during the skid (the clip carries the body up and over).
- New courses in MovementTestArena:
  - JUMPLANE, SKIDLANE, VAULTUNDERLANE (slide under) and JUMPONOBSTACLES: elevated lanes, "the floor is lava";
  - a slab for running in circles of different radius.
- "Traverse beautifully without hardcoding."

## Results (fresh runner per lane, target at the far end)

| course | before this pass | after |
|---|---|---|
| JUMPLANE (bars 1-8 studs) | fell off at the start | 4.5 s, no falls |
| SKIDLANE (bars 2-8) | fell / dead stops | 4.5-6.0 s, no falls |
| VAULTUNDERLANE (gaps 4-8) | bumped onto the first bar, fell | 4.5 s, slid under all six |
| JUMPONOBSTACLES (target on the 35-stud top) | ran under the platforms, stuck under one for 20 s | 3.7 s, three hops: lane → 9 up → 19 up → 7 up |

**Moves per bar (JUMPLANE):**
- h1: walked over
- h2: hop
- h3, h4, h5: skid-over (Y held, 0.41-0.50 s)
- h6, h7, h8: hurdles, clearance 2.1-2.7

**Pacing:** approach speed drops to 26-34 studs/s through the dense part.

**Circles (lap driver, R = 8 / 14 / 20 / 27):**
- radius within 0.4-1.6 studs;
- speed 25 / 34 / 40 / 40 (the lateral-grip limit √(90R));
- the facing leads the motion by 9-17°. This is a general locomotion trait (the body faces its steering heading); not changed here, see Open.

**16v16:** 0 errors; state shares normal.

## Causes found and fixed

### Obstacle reading
- **SpatialModule.analyzeObstacleAhead** probed the top straight down from the hit point on the face. On thin bars the ray grazed past the top to the floor, so a 3-stud bar read as 0 high. It now probes 0.4 studs inside.
- **Lips under `Locomotion_StepHeight` (1.5)** are walked over. They used to be "avoided" with a swerve, which on a raised lane is a fall.
- **Floating bars** (open space under them) are no longer jump obstacles; the slide-under check handles them.

### Skid-over and hurdle
- **Height bands:** skid only for heights `SkidOver_MinRise` 3 to `SkidOver_MaxRise` 5. Below 3 the Quin hops; above 5, up to `Hurdle_MaxRise` 11, it hurdles. Taller obstacles go to the climb / stepping-stone logic.
- **Skid-over with Y locked (owner's suggestion):**
  - no ballistic arc: the body keeps its running height and speed on a mover, with its collision off for the crossing;
  - the clip's airborne part is fitted to the crossing time;
  - 4-5-stud bars get an eased lift of (h - 3) at the middle.
- **Hurdles** use the same solve as the skid, T² = (L/v)² + 8(h+c)/g: apex over the middle, clearing both edges. The old hurdle peaked over the near edge and landed on top of tall bars.
- **Late takeoff:** when the ideal takeoff has passed (planned on a landing, or a 10 Hz tick late), it searches horizontal speeds for the lowest arc that still clears both edges, a shortened jump, instead of refusing.
- **Pacing for the next obstacle:** with another obstacle close behind, the approach speed is capped on the ground so this landing plus the next takeoff fit the gap:
  - v ≤ (2(gap−1) + L₁ + L₂)/(T₁ + T₂).
  - Slowing in the air did not work (see the speed cap below).

### Why jumps silently failed
- **Humanoid boost:** the Humanoid added its own JumpPower (50 studs/s) on the step after entering Jumping, so every solved jump below that flew at 50. JumpPower is now set to the jump's own launch speed for the takeoff.
- **Lagging ground state:** `FloorMaterial` and the Humanoid state lag a landing by a few tenths of a second, so crossings planned on a landing were refused. Ground contact is now a ray (`LocomotionModule.isOnGround`).
- **Debounce:** crossings use a 0.15 s debounce instead of 0.35.
- **Arc check:** the coarse arc trace's HitsWall / NoHeadroom vetoed solved crossings. For crossings only the landing is checked.
- **Diagnostics:** silent refusals now write `JumpSkip`; plans write `SkidPlan`.
- **Air speed cap:** in the air the Humanoid kept accelerating the body to its run speed. The air speed is now capped at the launch speed for every jump.

### The floor is lava
- **`SpatialModule.keepOnSurface`**, applied in `LocomotionModule.steer` (every state):
  - when the target is at the same level, a heading that would leave raised ground (a drop of more than 10) bends up to 50° toward ground that continues, needing ground 1.2 studs to either side of the path;
  - otherwise the Quin stops at the edge;
  - a target well below is a reason to go down.
- **Arena-edge check:** in Chase it now only reacts to the true void. On an 8-wide lane both sides read as ledges and it steered the runner off one of them.
- **Reachability while airborne:** at the top of a hurdle, "target too high" sent the runner on a path round. Airborne Quins now keep their last verdict, with hysteresis (0.5 s of clear line before leaving a path).
- **NavigationModule:**
  - sweep radius 2.0 (body width) and sweep height 7, so jumpable bars are not walls;
  - a path is replanned when the Quin is off it (24 studs).

### Slide-under
- **Detection** (`detectLowOverheadGap`): any part, gaps 2.5-8.5, along the motion, up to 18 studs ahead. It used to need "OB" in the name, gaps 0.8-3.5, and 8 studs of look-ahead.
- **Timing:** started ~0.3 s before the bar, with no cooldown or energy gate.
- **The slide itself (`opts.underGap`):**
  - collision off;
  - PlatformStand with Y held, because the root (5.4 up) was above a 4-stud gap's underside and the Humanoid stood up on the bar;
  - does not rise while something is low overhead, so close bars become one slide;
  - its direction is edge-checked along the whole glide;
  - it ends at once if there is no ground under it.

### Stepping stones (`NavigationModule.nextStone`)
- **Candidate surfaces:** a target standing above is climbed through any solid, level top within 70 studs that is at least 2.5 wide and has room to stand.
- **Scoring:** height still to climb + half the flat distance left, plus 0.3 × hop length, plus 6 for hops higher than 12.
- **Which hop:** the best one, if it improves by at least 4.
- **When used:** targets 8+ above (`Nav_StoneMinClimb`), or 2+ above and not reachable on foot.
- **Limits:** hops up to 60 across and 40 up.
- **The hop:** a precise spot projectile jump (the game's point jump), because running jumps onto 3-deep tops carried their speed off the far side. For these hops:
  - minimum flight 0.35 + d/90 s (the arc used to zip at 120 studs/s);
  - energy cost 8 instead of 40;
  - no shockwave;
  - a quick soft landing (`traversal_landing`, 0.3 s).
- **Main.server:** ProjectileJump and WallRun now skip the 0.8 s Chase dwell, which made every hop wait 1.3 s while its spot request expired.

### Test hooks (Studio only)
- GameModeManager listens to Workspace `DevCommand` (`movement_test`, `team:N`, `ffa:N`). The restarted Studio MCP runs sandboxed and cannot fire GameCommand.
- Main.server runs a Quin around a circle while it has `DevLapRadius` / `DevLapCenter` (real locomotion, states skipped).
- `ServerStorage.QuinTestTools.CourseRunner` is a test harness (the sandbox cannot require it; runs are inlined).

## Open
- **Curves:** facing leads the motion by 9-17° on sustained curves (all running Quins). Needs an A/B with the body tilt (owner's regression guard) before changing.
- **SKIDLANE variance:** one run took 6.0 s with a re-plan at bar 6.
- **Not visually checked:** none of this was watched on screen; the measurements come from the server.
