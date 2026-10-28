---
name: animation-placeholders-body-awareness
description: Pass 36 - AnimationConfig placeholders (`borrows`), strafe clip facts and the open rename, BodyAwareness (Quins steer round bodies)
metadata:
  type: project
---

Pass 36 (2026-10-04, `ab7c727`), from the owner's requests.

**Animation ids:** the owner wants one id per animation. `AnimationConfig` had 19 ids shared by 56 entries. Now each id is written once on its owner; the other 37 entries are placeholders with `borrows = "Owner.Path"` (resolved into `entry.id` at load and after `update()`; `AnimationConfig.placeholders()` lists them; `exportLuau()` keeps `borrows`). The owner of each id was my guess from `AnimationModule`'s id-to-name table: the owner has not confirmed the list (table in `audits/2026-10-04_pass36_animation_ids_body_awareness.md`).

**Strafe clips (measured):** they travel 90 deg left / right of the root; hips face 68-78 deg toward the travel, chest about 50 deg. So they are forward walks with the upper body turned part-way back, baked a quarter turn from every other clip (the owner's "football player looking sideways"). Speeds: Run 17.9, Walk 7.3, Tired 2.6 studs/s. `Tactics.RetreatBackstep` borrows the left strafe walk.
- **Owner's answer (2026-10-04):** no rename ("nothing is jog, it's already ok"). They want the strafes to read as moving 90 deg left/right while looking forward; the chest fix is being tried on IK Lab lane D first (`SquareUp`), not yet in QuinCore.

**BodyAwareness** (`Modules/BodyAwareness`, called from `LocomotionModule`'s steer driver; tunables `CombatConfig.BodyAwareness`; switches Workspace `BodyAwareness` / `BodyPersonalSpace` = false): the owner hates Quins shoving through each other ("no directional awareness, lifeless"). A moving Quin steers round bodies on its path and eases off one beside it; its own opponent is not in the way. Measured effect is real but modest and noisy (running into a body: 0.27% -> 0.09% of Quin time in one run, 0.19 -> 0.15 in another). Most contact left is two Quins on the same opponent, or bodies carried by knockback. `BodyInWay` attribute feeds the mind panel.

**How to apply:** A/B a movement rule by switching it off and on every 10-12 s inside one match; whole-run comparisons differ more between runs than the rule changes.

Related: [[social-layer]], [[quin-movement-audit-workflow]]
