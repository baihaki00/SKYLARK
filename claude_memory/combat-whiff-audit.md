---
name: combat-whiff-audit
description: Pass 29 16v16 strike audit — whiff causes, fixes, baseline numbers, the Y-axis race fix, and how to re-measure
metadata:
  type: project
---

2026-10-03, Pass 29 (`3ce737c`). The owner saw Quins whiff a lot, from too far away, and spin under targets on platforms.

**Causes found:**
- strikes thrown before facing the target;
- the step-in lunge went along the body's facing toward the target's old position, while the target strafed out during the ~0.34 s wind-up;
- a whiffed clip played out in full.

**Fixes** (CombatConfig `Combat_StrikeFacingDot` / `StrikeFacingWait` / `StrikeLead` / `StrikeTracking` / `WhiffRecovery`, in FightState):
- the strike waits until the body faces the target;
- the step-in is aimed ahead of the target and re-aimed halfway through the wind-up;
- a whiff recovers in 0.2 s.

**Baseline after the fix (16v16):** hit 66%, whiff 8%, blocked 8%, interrupted 18%. Interrupted means hit during the wind-up: the clip stops, so it's a trade, not a whiff.

**The "Y-axis race":** ChaseState's high-ground vantage point was computed from the body's own facing every tick, so the Quin span in circles. It is now a fixed spot 24 studs out from the target, with a slow creep while the target is out of jump reach.

**How to re-measure:**
- Hook every Quin's `Attacking`, `StrikeSeq` and `StrikeResult`.
- Record the target's local position at impact (`rootPart.CFrame:PointToObjectSpace`).
- Run collectors in a server `task.spawn` that writes a Workspace attribute; the MCP calls time out at about 60 s.

**Open watch items:**
- Short stuck moments (6 in 45 s).
- Idle blips after a kill (0.1–1 s), left as a natural beat.

Related: [[quin-movement-audit-workflow]], [[combat-animation-guide]]

**Re-measured 2026-10-05 (Pass 69, after passes 52-68):** hit 67 %, whiff 7 %, blocked 7 %, interrupted 19 %: unchanged. TRAP: count strikes on `StrikeSeq` changes and read `StrikeResult` then; counting `StrikeResult` changes drops repeated identical results (it read 45 % hits). Match pace: 1000 health, first knockouts only after ~200 s.
