# Pass 70: Dash off the wall from the top of the run; the wall run keeps its target; demo loop clean

The owner asked for one plain demo sequence with two Quins, looping, camera free:
- run and slide, the other hops over it;
- run and slide, the other is tackled (flip, fall pose, landing);
- a wall run;
- a wall run with a dash off the wall.

Pass 58 (the flip and sprint-only wall runs) was already in. This pass is what the loop showed was still broken.

## 1. The dash off the wall never fired

**Measured:** every "+ dash" step ended `ArcSpent 1.34s`, `AirDashSkip = "air left 0.02s"`.

**Cause:** since Pass 62 the wall-run arc is flown per frame and runs until the body is back at its start height. The kick therefore leaves from about floor height, with ~0.17 s of air. The air dash (which only looked after the kick) refuses with less than `AirDash_MinAirLeft` 0.3 s.

**Change:** `AirDash.fromWall`, asked once per run by `WallRunState.update` at the top of the arc:
- conditions: `rise <= 0`, at least `AirDash_WallMinHeight` 4 studs above the start, after `MIN_COMMIT_TIME`;
- the same cooldown, energy, reach (`WallRange` 45), sight and chance rules as the other air dashes;
- the target must not be behind the wall (`AirDash_WallMinOut`).

When it dashes, the run's movers are released first. A small shockwave marks the push-off, `WallKickReason = "WallDash <t>"`, and the state goes to Chase. The kick at the end of a full arc still offers the old check.

## 2. Every wall run wiped its own target (a real bug, not only in the demo)

**Measured:** `CurrentTarget` went nil 0.2 s into every wall run.

**Cause:** `WallRunState.update` looked for an intercept with `TargetingModule.getNearest(rootPart, 18)`. `getNearest` is not a query: it assigns targets, and calls `clearTarget` when nobody is in range. `AirborneState` had the same call with 30 studs, so a Quin in mid-air with nobody within 30 lost its target.

**Change:**
- Both now use the read-only `getEnemiesInRange(...)[1]`.
- WallRun is added to Main's `NO_RETARGET_STATES` (it keeps the target it has, like a jump).

## 3. Slide tackle in the demo

**Hurdle:** a forced hurdle (Studio `TackleOutcome = "hurdle"`) was still refused when the target had just started an attack (`Attacking`, the "busy" gate). The forced outcome now skips facing and busy; natural play is unchanged.

**Sweep:** `SlideTackle_Width` 2.5 → 3.0. A target 2.6 studs off the slide's line was passed untouched.

## Measured (server, 1v1 demo loop, two rounds after the fixes)

| step | result |
|---|---|
| hurdle | 2 / 2 hopped |
| sweep | 2 / 2 swept |
| wall run | 2 / 2 full arcs, 1.34 s |
| wall run + dash | 2 / 2 dashed off the wall at 0.82 s, 11.3 studs up; landed beside the target ~0.3 s later |

Before the fixes, the same loop gave hurdles 1/4, sweeps 3/4 and wall dashes 0/4.

## Not checked

- By eye (owner): the dash off the wall, and the flip and landing from Pass 58/61.
- Natural 16v16 rate of wall dashes, and whether keeping the target on the wall changes anything else in play.
