---
name: quin-open-requests-20261001
description: "The user's request list after movement passes 3-4 (shuffling, circling, walking by choice, GASP removal, landing clips, slides, realism), what pass 5 closed, and what is left before combat polish"
metadata:
  node_type: memory
  type: project
  originSessionId: aab93d9f-4a24-4c2a-9a6e-34e1919e40d6
  modified: 2026-10-01T04:38:24.072Z
---

After passes 3-4 the user asked for, "fix this first, then we polish the combat": shuffling (legs vs ground), a rigorous Circling audit, walking by choice with readable intent (emergent, "like inventing chess", not scripted), removal of all GASP leftovers, three landing clips (`94804914683754` superhero, `110436967972328` hard, `136234480688142` soft), more Unreal-like fluidity, slides back, and (minor) a "lightning" Quin at both spawns.

**Pass 5 (commit `f422a4b`, branch `audit/16v16-baseline-20261001`, write-up `audits/2026-10-01_16v16_movement_pass5.md`) closed:** Circling rewritten around clip ground speed and exact-lateral motion; gait releases at standstill; start-run overlay hands over to gait; Run clip speed 29.5; walk 7.5 / sprint 40 / acceleration 55; HipHeight from rig; GASP code removed; landing clips wired; slides 9 -> ~60 per 75 s; `PaceReason` attribute explains chase pace.

**Still open (told to the user):**
- Start-from-rest acceleration still slips (~0.5 s per start); needs distance-matched start clips.
- Fight lunges / attack slides drag the feet: belongs to the combat pass.
- The spawn "lightning" Quin is the opening Dash at 110 studs/s for aggression > 0.72 (IdleState `openingAction`); unchanged, waiting for the user's call.
- Earlier leftovers: wall-run frequency, AirborneState unreachable, style 7 projectile jump has no dive, `Tactics.RetreatBackstep` uses the StrafeLeftWalk asset.

**Why:** the user judges by watching the 16v16 and wants this list done before combat polish.
**How to apply:** same loop as [[quin-movement-audit-workflow]]; next step after their feedback is combat polish. Clip ground speeds and the slip probe method are in the pass 5 audit file; the Edit-mode stance-chord measurement is the trustworthy one (in-play contact metrics overstate slip at sprint and for low-clearance walks).
