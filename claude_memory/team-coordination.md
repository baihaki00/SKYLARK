---
name: team-coordination
description: "Team coordination plan (owner-approved 2026-10-27, 5 steps) and what steps 1-2 built in TargetingModule; baseline numbers; open steps 3-5"
metadata:
  node_type: memory
  type: project
  originSessionId: 11e382ae-5247-4176-93d5-d6257bc05aff
  modified: 2026-10-26T20:26:17.495Z
---

**Plan (owner said yes to doing 1+2 first, 2026-10-27):** a team is a pack that reads the fight; leanings, never fixed rules.
1. Team picture from what each Quin sees (NearbyAllies only): which ally is on which enemy, who is hurt, who is free.
2. Target choice: an enemy allies are already on is less attractive; temperament bends it (confident wants own fight, aggressive still finishes a weak one, protective goes to an ally in trouble).
3. Roles from the moment: engager, flanker (circles to the back), interceptor, rescuer, breather.
4. Visible intent: head looks at the helped ally / flank target, nods, leader focus call, debug lines per role.
5. Purposeful jumping: tag every jump/leap/dash with a reason, measure per minute, cut reasonless ones (owner: "creatures obsessed with jumping", wants intentional).

**Built (commit 2f058a7):** TargetingModule: takers per enemy (allies in Fight/Chase/Circling within Targeting_CrowdRadius 45 of their target), crowdScore = -Targeting_CrowdPenalty 40 x min(n,3) x lean; coverScore 45 x (0.5+protectiveness) for an enemy going for an ally busy with someone else; TargetReason strings "N allies already on it" / "Cutting off one going for a busy ally". TeamCoordinationSystem: Wingman no longer gets its ally's opponent as focus (Bodyguard still does).

**Measure:** per-second snapshot, per alive Quin how many enemies are engaged on it within 45. Old: 0:55% 1:28% 2:11% 3:4% 4+:2%. New run1: 56/31/11/2/0, run2: 65/25/5/2/3. Modest, noisy - owner's eye decides; possible next lever: persistence bias 49 + isolation 45 outweigh the penalty.

**Side fixes same day (commit 75675bf):** head bumps under platforms: PJ headroom gate in Main.server.lua before any ProjectileJump transition (ProjectileJump_Headroom 45 up + a third across toward the target; JumpSkip "ceiling"); AirInterceptModule needs a clear line to the jumper; duel dash/leap check `blocked`; Momentum bounce off a ceiling drops (no up kick, no redash - that looped). Left: PJ mid-flight hits on floating parts 60-200 studs up (PJ's own arc; owner protects PJ, asked). Evasion: only ~20% of strikes are "seen" by Instinct (tell + reaction timing); SlipChance 0.45, FocusDash_OpeningChance 0.5; slip fallback now plays QuickEvade clip.

Related: [[social-layer]], [[quin-momentum]], [[quin-temperament-habits]]

**Combat correctness pass (2026-10-27, commit ca30d3e):** "knockback with no strike" = mostly FightState desperate_counter casting its hitbox on the clip's first frame (now at 0.22 s impact, skipped if interrupted/out of Fight; riposte too); a knocked-flying attacker now loses its strike (DamageModule interrupt no longer skips isKnocked); strike impact also skipped if CurrentState ~= Fight. Strike-visible knockbacks 57% -> 73% (rest = trades, air/landing slams). Hit owns the legs (Main, Combat_HitOwnsLegs): WalkSpeed 0 during StunEndTime in non-Fight states, hit clips fade once walking/self-lunging; walking-in-hit-clip 10.6% -> 3.2% of hit samples. Duel dash: Dash pose (Action3) blended 50/50 with leftover LedgeDropLanding/NinjaJump -> Momentum clearPose stops Action+ tracks at leap/dash/bounce start (pushed, NOT yet measured: Studio MCP play got stuck). Steps 3-5 not started.

**Steps 3-5 built (2026-10-27, commit ccab0f6, NOT yet measured in Play - Studio MCP start_stop_play got stuck "Start play hasn't finished yet"; owner pressing Play unsticks it):**
- Step 3: TargetingModule sets PackIntent / PackIntentAlly / PackIntentAt after choosing (Engager, Flanker or Joiner [awareness roll once per ally, sticky], Interceptor, Rescuer, Breather [label only]). ChaseState: Flanker aims at target + unit(mine+back)*Team_FlankRadius 12 until dot >= Team_FlankBehindDot 0.55 (attr Flanking). Config Team_Flank/FlankLean/FlankRadius/FlankBehindDot.
- Step 4: Gaze glances at PackIntentAlly when PackIntentAt changes (not in engaged states; GazeIntentGlance switch); QuinDebugHUD Role line shows "TeamRole / PackIntent for X (going round)". Nods + leader focus call NOT done (no nod clip).
- Step 5: Modules/JumpLog (mark/why/reset; counts on ServerStorage.JumpLog attrs "<kind>__<reason>" (non-alnum -> _; TRAP: attribute names allow only letters/digits/_ - the first version threw and broke dashes/jumps), Quin attrs JumpKind/JumpReason/JumpAt). Callers set attr JumpWhy before LocomotionModule.jump/dash and PJ returns; Main marks PJ transitions ("? from X" = reasonless). MomentumDuel marks its moves. Cut: duel ground hops now only "over something low" (HopWithoutReason false); FightState mid-fight PJ needs a reason (target >8 up, fleeing >14 studs/s, or unreachable; ProjectileJump_FightWithoutReason).
- Measured (commit after ccab0f6): ~5.3 moves per Quin per min, only 5 of ~185 without a reason; top = FightState "fight dash" 32/min, standoff-snapped dashes 13/min, duel moves. Stone spot-hop (PJ arc to a stepping stone) was 22/min on one arena seed. Flankers: far-side arrivals 4/14 -> 13/20 after Chase holds Fight entry while Flanking (Team_FlankCommitRange 0.9); joiners arrive beside the ally. Studio MCP play can get stuck: owner pressing Play unsticks it.
