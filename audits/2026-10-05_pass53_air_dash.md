# Pass 53: Air dash (combination moves, items 18 and 19)

Owner items:
- **18:** a normal jump, then immediately a dash (to the target, or to move).
- **19:** a wall run, then a dash off the wall (to attack, or to move).

## What was there

Quins only jump as traversal, in ChaseState: onto platforms, over gaps and obstacles. The only dash was a ground slide (`LocomotionModule.dash`, horizontal only). A wall run ended in a fixed kick off the wall and handed over to Chase or Fight. Nothing could dash in the air.

## What it does now

There is a new module, `Modules/AirDash`. Nothing schedules a dash. A Quin that is already in the air checks once per airtime whether a dash would get it somewhere useful.

**The checks:**

| Case | When it dashes |
|---|---|
| At a target | The target is 8–36 studs away (45 off a wall), at most 8 above or 30 below, and in sight. Chance = `AirDash_Chance` 0.3 (`WallChance` 0.55 off a wall) × (0.5 + dash preference) × (0.5 + aggression). |
| To a ledge | A jump onto a platform is coming down short of where it meant to land. The jump records its aim with `AirDash.noteJump`, called from both platform-jump sites in ChaseState. |
| After a target | Off a wall, the target is 45–90 studs away and in sight. |

**Shared rules:**
- once per airtime;
- the dash cooldown (`LastDashTime`, 5 s, shared with the ground dash) and energy (minimum 20, costs 15);
- at least 0.3 s of air left, worked out from the vertical speed the dash itself will set. In this place gravity is about 210 studs/s², so a hop or short drop lands before a 0.26 s burst is through.

**Physics:**
- The horizontal burst is a single request on `ImpulseModule` (tag `airdash`, "hold" profile, 0.26 s, up to 115 studs/s). It carries up to 40 studs, and an attack dash stops short at striking range.
- Vertical speed is set once at the start: a small lift of 6 (14 to make a ledge), or downward toward a target below. Gravity does the rest, so the dash flattens the jump into a fast, low arc rather than a hover.

**Presentation:**
- New `AnimationConfig.Movement.AirDash` slot. It borrows the ground dash clip until the owner authors an air one.
- The ground dash's sound and vapour cone.

**Wall runs:** `WallRunState` now marks the kick (`AirDash.noteWallKick`). The dash waits 0.24 s so the kick carries the Quin clear of the wall first.

**Config and debug:**
- Tunables are `CombatConfig.AirDash_*`.
- Debug attributes:
  - `AirDashReason` and `AirDashAt` on a Quin that dashed;
  - `AirDashSkip`: why its last airtime did not dash;
  - `WallKickReason`: why a wall run ended;
  - Workspace `AirDashStats`.
- Studio-only test switches: Workspace `AirDashAlways` (every eligible airtime dashes) and `AirDashDevCommand = "reset"`.

## Measured

All runs used Studio Play, a generated arena (`run 4`) and 16v16.

### 1. First version, natural play

- 12 dashes, nearly all useless: touchdown 0.11–0.18 s after the start, 2–15 studs covered.
- Cause: the airtime was hops and short drops.
- Fix: the air-left rule.

### 2. Controlled jumps

- Chase Quins were tossed up at 80 studs/s (about 15 studs high) when 18–40 studs from their target.
- 52 tosses; 14 dashed at the target (the natural chance roll took about half).
- The gap to the target went from 14–31 studs to typically 5–15 (median about 9). The dasher went into Fight or Circling in about half the cases, and was hit (Knockback) twice.

### 3. Staged wall runs

- 20 trials: a Quin beside the arena wall, forced into `WallRun` with `WallRunEntrySpeed` 48.
- Most staged runs lost the wall 0.11–0.14 s in. This staging is unreliable, as noted in Pass 50.
- The two full runs (2.3 s, `ArcSpent`) kicked off 14–15 studs up, dashed at the target 0.25 s later, closed to 5–6 studs and went into Fight.
- The early-ended runs kicked off only 3 studs up, and the air dash correctly declined (0.00–0.14 s of air left).

### 4. Natural 16v16, 2 minutes, no switches

- 7 attack dashes, 1 declined.
- 5 real wall runs, lasting 0.56–1.15 s. They ended by `TargetIntercept`, `WallEnd` or `ArcSpent`, not the instant cut-off seen in staging.
- Airtimes skipped:
  - not enough air left: 123
  - target out of reach: 41
  - on cooldown: 7
  - no sight: 1
  - not enough energy: 1

### Health

No script errors.

## Not shown

- **"To a ledge":** never happened. No platform jump fell short in these runs.
- **"After a target off a wall":** never happened; no full staged wall run got that far.
- **By eye:** nothing has been checked. Placeholder clip; the ground dash clip in the air may look odd.
