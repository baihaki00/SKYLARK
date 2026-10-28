---
name: place-v3
description: The working Studio place is QUIN_COMBATV4 (placeId 95070334615130) since 2026-10-08 (before: V3 106089520796817, from 2026-10-03, after V2 assets failed in a moderation hold)
metadata:
  type: project
---

On 2026-10-03 the owner's account was moderated. In QUIN_COMBAT_V2 (placeId 135832583650579), all of the owner's animations and sounds then failed: "Animation failed to load", sound HTTP 403, mesh "could not fetch". The owner reopened the work as **QUIN_COMBAT_V3 (placeId 106089520796817)**, which holds the same scripts. Once the hold cleared, assets loaded (0 failures).

**Why:** a session where the owner's assets fail gives meaningless combat timing, because clip lengths fall back.

**How to apply:**
- Call `list_roblox_studios` and use the place the owner has open.
- If many owner assets fail to load, stop and tell the owner (account or permissions) before measuring anything.
- `scripts/publish-notes.ps1` defaults its window match to "QUIN_COMBAT", which still matches V3.

Related: [[studio-git-export]]

**2026-10-08:** Studio came back connected to **QUIN_COMBATV4 (placeId 95070334615130)**, with the same scripts (it matched HEAD), so work continues there. The reason was not given.
