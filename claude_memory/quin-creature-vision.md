---
name: quin-creature-vision
description: The owner's core vision (2026-10-07): a Quin is a living creature made for combat; design doc QUIN_CREATURE_DESIGN.md, roadmap phases 0-6; judge changes by flow and the owner's eye
metadata:
  type: project
---

On 2026-10-07 the owner settled the direction after the first Player Quin session.

**The vision.** A Quin is **a living creature made for combat**: fighting is its nature, like a predator. It is not a fighter "trying to win", and not merely "pursuing prowess"; the owner rejected both framings. Throw Quins anywhere (ground, wall, air, ground↔air) and they fight like a fight scene or a stickman fight animation, emergent and never scripted.
- References: Avatar, Naruto, Goku, One Punch Man S1 (Madhouse: timing, contrast), The Legend of Hei 2, Jhanzou's stickman fights.
- Anti-references: ring-based boss combat (God of War), VFX clutter.

**Where it is written down.** `QUINCORE_BACKUP/QUIN_CREATURE_DESIGN.md` (commit after 7dfcce2). It holds:
- layers: perception (Cognition) → reach (3D time-to-contact bands) → instinct → mind → drives/rhythm → one honest body;
- principles: one creature for AI and player, nothing scripted, no resets, every move an answer, range is time, restraint;
- a roadmap: 0 baseline + flow measures; 1 body; 2 continuity; 3 reach + attention lock; 4 instinct + answers; 5 drives + rhythm; 6 impact; later weapons and guns as new verbs.

**Rules for any change.**
- The current 16v16 is owner-approved: protect it with a baseline (numbers plus recorded fights the owner liked), switches, and the owner's eye.
- Better numbers alone don't win.

**Open owner questions** are in section 10 of the doc (sprint cornering sharpness, default pace, player instinct, visible feelings, first test fight).

Related: [[player-quin-mode]], [[combat-markers-future]], [[social-layer]]

**Owner's answers (2026-10-07):**
- Cornering is steered by the mouse, Tales Runner style, and fluid. "Superhuman grip" must NOT mean an instant 90° turn.
- Jog is the default piloting pace.
- A player's Quin acts only on input (no automatic guard or dodge; hit reactions still play).
- Phases 1–2 are judged on a 1v1 first.
- Open: whether feelings show on the body or only in behaviour.
- Agreed (design doc 5.8): a normal Quin moves **free** (body faces travel; S = turn and run) or **engaged** (faces a nearby opponent; S = backpedal, A/D = circle), switched by attention.
- The player's camera drives the Quin's head and gaze (its sight, via Cognition Gaze); the keys drive the body.
- A backpedal clip is needed.
- Feelings on the body are deferred to the personality work.

**Phase 0 done (2026-10-07, `1cf529b`):** baseline in `audits/2026-10-07_phase0_baseline.md`.
- Probe: `scripts/flow_probe.lua`.
  - HOW TO RUN: `python -m http.server 58918` in `scripts/`.
  - On the Server: HttpService GetAsync the file, wrap its source as `return function(LABEL_, DURATION_, MIN_ALIVE_) … end` in a ModuleScript in ServerStorage, require it, and call it.
  - Results land in Workspace `FlowProbe_<label>`.
- Key numbers: 16v16 hit 68 %; standing to decide 9.5 % of engaged time; Chase→Fight keeps 0.37 of speed; strikes start at ~11 studs/s; air 11 %; 0 natural wall runs; no deaths in 240 s.
- 1v1 (3 runs) is similar, with burstier rhythm (activity CV 0.7).
- Waiting on the owner: screen recordings of liked fights in `QUINCORE_BACKUP/baseline/`.

**Phases run on 2026-10-07; the owner (asleep) asked for all phases to be done, and will judge the 1v1 after.**
- **Pass 74 (`edffa87`), player jumps:**
  - air control: no ground drive or brake in the air;
  - tap/hold height via `LocomotionModule.cutJump`;
  - V = projectile jump (tap = style 1, hold = style 2, V again = dive);
  - a second `MAX_JUMP_HEIGHT = 14` had shadowed `Jump_MaxReach`;
  - Studio hook `PilotTestInput` (JSON) drives a piloted Quin without a keyboard. MCP keyboard input did not reach the game while the owner was away.
- **Phase 1 (`0f55e62`):** Body_Agile (grip 200); BodyStamina; SteerIntent head lead; the player's camera drives the head; engaged footwork. 1v1 strikes +40 %, 16v16 unchanged.
- **Phases 2–6 (`7f7d8cf`, committed and measured):**
  - Flow_ArriveHot / DodgeCounter (`CounterUntil` attribute) / WallTech;
  - `Modules/Reach` (Fight↔Chase by time) and the player's lock (T/G);
  - `Modules/Instinct` (reflexes at the `StrikeTellAt` tell; AI only) and FightState `chooseStrike` / `remember`;
  - `Modules/Drives` and `Modules/Rhythm`;
  - `Modules/HitStop`.
  - Every one has a CombatConfig switch.
- **Workflow scripts (scratchpad):**
  - `make_push.py` and the constant push snippet (reads `studio_snapshot/__head/push_list.txt`; compares Studio to the last pushed copy);
  - `record_pushed.py`;
  - `commit_tested.py` commits the pushed copies, not newer disk work.

- **Final numbers (everything on):**
  - 1v1: whiffs 7 → 2 %; speed into a fight 0.36 → 0.50; about 20 strikes per Quin-minute (baseline 16).
  - 16v16: 15.4 strikes per Quin-minute (baseline 13.9), hit 67 %, rhythm CV unchanged; per run 75 counters, 12 wall techs, 136 breaths.
- **TRAP fixed:** the delayed `Attacking = false` compared tick() with `attackFinishTime` once. When the hit-stop extended the finish, `Attacking` stayed true until the next strike (strikes looked 25 % fewer). It now waits out extensions and checks `AttackWindupUntil`.
- **Studio A/B:** Workspace `Ablate_Drives` / `Ablate_Rhythm` / `Ablate_HitStop` / `Ablate_Instinct` / `Ablate_Reach` switch a layer off live.
- **Open after the owner's 1v1 review:**
  - running-strike clips;
  - a backpedal clip;
  - the other states' stud thresholds;
  - feelings shown on the body;
  - reflexes rarely fire in trades.
