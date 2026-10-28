---
name: skylark-performance-plan
description: "2026-10-26 fps work - measured costs (wraps, crowd, server 40 Hz), server-decides/client-shows split, phased plan A-F awaiting owner approval"
metadata:
  node_type: memory
  type: project
  originSessionId: 5cc49fde-c838-4731-aca5-6c5d1df7ad9f
  modified: 2026-10-25T18:41:39.144Z
---

Owner goal (2026-10-26): 60+ fps from start to finish of a match, all Quins dressed, without losing quality. Plan: `D:\SKYLARK\SKYLARK LOCAL REPO\SKYLARK_PERFORMANCE_PLAN.md`. Owner APPROVED the order A→B→D→C→E→F (2026-10-26). A (benchmark) is DONE: Quin Manager > TEST MODES > Performance Benchmark, DevCommand bench:full|nocrowd|noclothes|bare, baseline STEADY fps full 33 / nocrowd 36 / noclothes 51 / bare 74 (TEST_MODES.md). B is DONE (2026-10-26): attribute traffic 2803→1551/s, GetTagged 27→<1 ms/s, footsteps and footprints on the client (QuinFootstepsClient), debug attributes only while the Spectator HUD is open (Modules.DebugReadouts), shared Quin list (Modules.QuinRoster.all(), read-only, refreshed per frame by DistributedGameTime: no signals because of [[quincore-shared-loop-ownership]]), BattleEvent prints only when Workspace.BattleEventLog. Studio fps didn't move (client clothes dominate). D (baked clothes) STARTED 2026-10-26 (owner: "go do D"; an old index line wrongly said rejected). Findings + exporter weight bug in CLOTHING_PIPELINE.md section 15. Bend test PASSED and bench nocrowd: layered 3 items 57 fps / baked 90 fps (= no clothes). Temporary switch Workspace.WardrobeBakedTest in QuinWardrobe + ReplicatedStorage._BakedTest (5 meshes). Then (same day): female fits DONE (build makes Unisex on both bodies; baked export 287 files _M/_F, not imported). Stacking: OVER copies for snug slots work; pushing garments failed (ugly) - clothes clashes (tucked tops vs waistbands, tanks vs skirts, trousers vs boots, vest/coats vs thick tops) must be fixed in builders. Details CLOTHING_PIPELINE.md section 15. UPDATE (same day): reliable pipeline built = build_catalogue (layer contract, quinwear/contract.py) -> bake_stack -> export_roblox baked=1 (372 FBX in export
obloxaked_all: <asset>_M/_F + OVER copies _MO/_FO with overWhen in manifest). Boots swap Bottom->Booted (code K); skirts have a hip yoke. Renders judged fine. DONE same day: owner imported; ReplicatedStorage.ClothingBaked (372 parts), QuinWardrobe wears baked in matches (preview layered; Workspace WardrobeLayered=true for A/B), test switch removed. Bench nocrowd 32 full random outfits: 88 fps. Missing meshes fixed: StarterPlayerScripts.ClothingPreload (gentle batched preload + retries, 372/372); verified by Play screen captures. Fetch-status API is unreliable (see handbook 16). Old test import models deleted. Bounds specks added in export (add_bounds, harmless) but the blinking cause is a Roblox engine bug: too many DIFFERENT skinned meshes in one fight. Owner-judged instant 16v16 + crowd: <=61 different clothing meshes clean, 80 blinks, not a bad mesh (handbook 16). Rule built in: QuinWardrobe W.MESH_BUDGET=60 + W.fightOutfit (random spawn outfits mix freely but cap the fight at 60 different meshes; saved outfits untouched; Workspace ClothingMeshBudget overrides); measured 60 meshes, 32 unique outfits. Owner wants free mix and match and hopes Roblox fixes the bug, then raise the budget. Clothing otherwise parked as future (2026-10-26). Handbook section 16. 2026-10-26: skirt/dress weights follow the stride (shins below knee + cloth over each thigh follows it; dev/render_stride.py); all 372 re-exported again, Owner imported (both old+new versions got imported: picked the higher MeshId per name = newer upload); all 372 swapped, _ClothingBakedOld deleted.

More traps found during B:
- The MCP start_stop_play can hang ("Start play hasn't finished yet"). Recover by focusing Studio with PowerShell AppActivate on the RobloxStudioBeta PID, then SendKeys {F5}.
- The bench flags "unreliable" whenever Studio isn't focused. Run AppActivate just before `bench:`.
- In Studio, the local player's role is Player, so the H key (Spectator HUD) is ignored. To test debug readouts, fire QuinCore.DebugReadoutsEvent(true) from the Client VM.
- RuntimeVisualizer.isEnabled() is true by default, so don't use it as "a debug screen is open".

Measured (Studio, 16v16, fixed cam (0,140,-178)→(0,0,-438)):
- Clothes wraps cost about 14 ms of render CPU per frame on the client (the biggest cost).
- The crowd (1000 avatars, 4.8M triangles) costs about 3.5 ms of render plus its posing scripts.
- The GPU is never the limit.
- The server ticks at 40 Hz instead of 60. Top costs: the AI loops (Main, TacticalPerception, Cognition, Senses), SetAttribute spam, GetTagged, ArenaTerminalQueue during the fight, DebugDraw and RuntimeTracer live, and footprints made on the server.

Measuring traps:
- Studio Play shares one process, so client fps includes the server's cost. Use Team Test for real numbers.
- How to measure from MCP:
  - Stats.RenderCPUFrameTime and RenderBreakdown.Opaque give the client numbers.
  - The server profile comes from ScriptProfilerService:ServerStart/ServerStop/ServerRequestData, called from the Client VM, with OnNewData then DeserializeJSON. ClientStart fails from MCP. Game scripts can't use ScriptProfilerService or Stats.RenderBreakdown at all ('lacking capability Plugin'). In Studio Play the server Hz just follows the client fps, so judge the server by its Lua ms.
- The MCP VM has its own `shared`/`_G`, so shared.IsAdmin and similar can't be checked from it.

**Why:** the owner rejected distance LOD for clothes. Quality must stay.
**How to apply:**
- Measure before and after each step with the bench (step A).
- Protect the 16v16 combat baseline ([[combat-whiff-audit]]).
- Clothes baking: [[clothing-accessories-design]].
