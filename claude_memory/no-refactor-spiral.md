---
name: no-refactor-spiral
description: Owner rule 2026-10-29 - respect the current QuinCore architecture and pipeline; no refactor/audit spirals; any refactor must come with its damage and risk stated first
metadata:
  node_type: memory
  type: feedback
  originSessionId: 39f307c0-e7ae-44a5-b9b9-669ff151cd89
  modified: 2026-10-28T16:11:51.148Z
---

Build new work (e.g. the fighting programme) as additions inside the existing QuinCore seams: AnimationConfig as the single source of truth, FightState children (Strike, Decide), DamageModule, ProceduralCombatReactionController on the client (QuinRenderMode "Direct" by default: the QuinServer body is drawn in place; "Ghost" clones are the old mode), Procedural/Layers switches, the CombatConfig switches and Ablate_ attributes.

**Why:** the owner said "what we already have right now is good enough... I know when to stop" and does not want work turned into another refactor and audit spiral (the 2026-10-27 audit was the last one).

**How to apply:**
- Name the module and file every change lands in.
- Fold a needed cleanup into the step that needs it, never into its own pass.
- If a real refactor seems necessary, tell the owner how much breaks and the risk first, and wait for a yes.

Related: [[quincore-audit-20261027]], [[quins-improve-in-general]]
