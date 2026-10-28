---
name: skylark-many-arenas
description: Skylark will have more than one arena; never word or design anything as "the arena" — name the arena, keep code per-arena
metadata:
  type: feedback
---

On 2026-10-24 the owner said: "we are assuming like its the only arena in this game, like most of your wordings, its not, in future versions i might add more arenas, think big please."

**Why:** Skylark is meant to grow into a world of arenas. Single-arena wording and assumptions will have to be ripped out later.

**How to apply:**
- In player-facing text, name the arena ("Argonia Arena terminal"), never "the arena" or "an Arena Terminal".
- New UI and data should be per arena. Draw from `ReplicatedStorage.QuinCore.SkylarkArenas` (list / get / current) and put arena things under that arena's section.
- The server side is still single-arena: ArenaSchedule, the Workspace ArenaReg* attributes, ArenaRegistration and the orchestrator. Making it multi-arena is a design to discuss with the owner before building, not to slip in.
- Keep the HUD arena-neutral (time only). Arena detail goes in the player menu's SCHEDULE.

Related: [[skylark-time-schedule]], [[skylark-mvp-target]]
