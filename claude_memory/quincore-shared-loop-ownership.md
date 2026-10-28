---
name: quincore-shared-loop-ownership
description: QuinCore trap - a module-level RunService connection made from Main (cloned per Quin) dies with that Quin; shared loops must be started from ServerScriptService.Server
metadata:
  type: project
---

`QuinCore.Main` is cloned into every Quin and destroyed with it. A connection made inside a shared ModuleScript belongs to the script whose call created it, so a module-level "one loop for everyone" connected lazily on first use dies when that first Quin is removed, while the module still holds the dead connection.

**Found 2026-10-05 (Pass 40):** `ImpulseModule` (lunges, step backs, flinches, knockback skids) stopped for all Quins after the first owner was removed or a match was restarted. Symptom the owner reported: Quins "playfully" striking at air 7-8 studs apart, never hitting (100% whiff, all standing still, nobody knocked out). Probably also fed the late-game stalling of [[social-layer]] Pass 35.

**How to apply:** shared loops get a `start()` called from `ServerScriptService.Server` (as `SocialSystem.start()` and `ImpulseModule.start()` do), and any lazy connect checks `connection.Connected`, not just non-nil. When a behaviour is fine in the first match and breaks after a restart or late in a match, suspect this first. A match restart in one Play session (`DevCommand "team:16"` again) reproduces it. Not yet audited for the same weakness: `DebugDraw`, other module singletons.

Strike health check: hook `StrikeSeq` / `StrikeResult` on every Quin; healthy is about 66-71% hit, 5-8% whiff ([[combat-whiff-audit]]).
