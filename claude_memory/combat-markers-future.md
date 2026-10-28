---
name: combat-markers-future
description: "Parked combat follow-ups after the strike marker reader (Pass 72, 2026-10-06) — owner said keep them for the future, don't start unasked"
metadata:
  node_type: memory
  type: project
  originSessionId: ea7205bd-c408-40a5-bbb1-9f9da28928a4
  modified: 2026-10-06T16:04:39.111Z
---

On 2026-10-07 the owner said: "keep the uncovered stuff as for the future". These are parked. Don't start them unless the owner asks; offer them when combat work resumes.

Where things stand: Pass 72 (`b98f515`) added `Modules/StrikeMarkers`. FightState strikes check contact every frame from HitStart to HitEnd and free the Quin at Recover.

**Parked items**
1. **Limb-following hitbox.** The hit box is still `HitboxModule.castInFront` (a box ahead of the body). StrikeMarkers already reads the HitStart limb (`markers.limb`, e.g. `RightFoot`) but nothing uses it.
2. **Other strikes on markers.** The desperate counter (FightState ~line 528, own impactRatio), MidAirClashState strikes and SpecialState still use their own fixed timing.
3. **`Whoosh` marker → swing sound.** The owner said "no need to play whoosh yet". All 8 clips carry it.
4. **`Windup` marker.** It could drive when defenders read the attack; today `AttackWindupUntil` ends at HitStart.
5. **`Cancel` marker** (early combo follow-up). None of the clips have it yet.
6. **Specials and rival finisher need their own clips.** They borrow HighKickRight / WheelDriveRight.
7. **Owner's clip fix.** Both punches have an empty `HitEnd` parameter; it should name the hand.
8. **Watch the strike rate.** Pass 72 raised it about 29 % (Quins are free at Recover). If fights look frantic: move Recover later in the clips, or raise `AttackCooldownMin/Max`.

Related: [[combat-animation-guide]], [[combat-whiff-audit]]
