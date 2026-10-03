# Pass 31 (Social layer, phase 2): Pack Leaders

Plan phase 2 of 4. Place: QUIN_COMBAT_V3.

## What was built: `Modules/SocialLeaders`

It's a `SocialSystem` part, listed in `CombatConfig.Social.Parts`. Tunables are in `CombatConfig.Social.Leaders`.

**Standing.** Each Quin's battlefield record only: kills, damage dealt / 150, health × 0.6, and accepted signals × 0.15. No personality.

**Leaders emerge.**
- **Caps by team size:** 1 → 0, 2–4 → 1, 5–8 → 2, 9 or more → 4.
- **A slot fills only for a standout:** standing at least 2.0 and at least the team average + 1.0, alive, not down, and 60 studs or more from the team's other leaders (each leads its own part of the field).
- **Every ally follows the nearest leader within 120 studs** (`FollowingLeader`, `LeaderTrust`).
- **On emergence,** nearby allies glance at the new leader, some with a nod.

**Transfer** (no timer). A leader stops leading when it:
- falls;
- is down (Knockback / Recovery / Airborne / ReEntry) for more than 5 s;
- loses credibility below 0.25;
- gives up (health under 22% with no ally within 70 studs);
- is outshone (another Quin's standing is 1.5 higher for 8 s).

A Quin that loses the role can't lead again for 30 s. It used to be re-promoted in the same check.

**Signals** (intent, not commands). Each leader signals at most every 6 s, with allies within 70 studs. It looks at its nearest ally, then at the target, then nods. The signals:
- **Protect:** the leader is under 35% health with enemies near.
- **Regroup:** enemies are near and outnumber allies by 2. The point is 20 studs away from the enemies.
- **Attack:** the leader is in Fight or Chase against an enemy target.

**Following is each ally's own decision:**
- **Chance:** p = trust × 0.6 + credibility × 0.4 − 0.15 if busy in its own fight − danger × 0.3 − distance × 0.2.
- **Never follows** when trust is under 0.2. A Quin in Fight never walks off for a regroup.
- **Reaction time:** 0.3–1.4 s, faster when it trusts the leader.
- **Following:**
  - it looks at the leader, sometimes nods;
  - Attack: a `SocialFocus` targeting bonus of +70 for 8 s, and it looks at the target;
  - Regroup: a move intent, jog or run (Chase / Circling / Idle walk there first). A hit cancels it.
  - Protect: `SocialGuard` for 10 s.
- **Refusing:** it looks at the leader, then back at its own enemy, and keeps fighting.
- **Witnesses** within 30 studs who aren't fighting react to a refusal:
  - look at the refuser (35%);
  - follow the leader anyway (20%);
  - go with the refuser and copy its target (13%);
  - ignore it.

**Reputation.** Each signal is judged after 8 s.
- **Attack is good** when the target fell or lost 4% of its max health and no follower died.
- **Regroup and Protect are good** when no follower died.
- **Disaster:** two or more followers died.
- **Unheeded:** an attack nobody followed doesn't count against the leader.
- **Credibility:** +0.06 / −0.08 / −0.15 (good / bad / disaster).
- **Trust:** followers ±0.06 / 0.08; refusers learn ±0.03 / 0.02.
- **Effect:** low trust means fewer and slower follows. Trust of 0.65 or more makes a follower **intercept** enemies that target its leader (+45 × trust; ×1.3 while guarding).

## Hooks (small)

- **TargetingModule:** term 13, `socialScore = SocialSystem.targetScore` (−1e6 for `SocialHoldOff`, plus leader focus and intercept).
- **TeamCoordinationSystem:** roles now come from SocialLeaders (PackLeader / Follower / Squad). The Follower branch no longer pulls a Quin onto the leader's target automatically, since following is a decision now.
- **Chase / Circling / Idle:** walk to a social move intent first.

## Bugs found and fixed

**1. The social loop died after the first match.**
- `Main` is cloned into every Quin, and the loop's thread belonged to the first Quin's script. When that Quin was cleaned up, the loop died. It was silent: the tick counter froze at 232.
- **Fix:** `ServerScriptService.Server` (which lives all session) starts the social layer at game start. `start()` restarts a loop that has stopped beating, and a generation token keeps one loop. Workspace telemetry: `SocialTicks`, `SocialLastError`.
- **Test:** an 8v8 then a 16v16 in one session. Ticks went 40 → 136 → 248 → 424, with leaders in both matches.

**2. Attack signals were judged bad almost every time.**
- The bar was 25% of target health in 8 s: 22 of 24 attacks were judged bad, and leaders lost credibility unfairly. At 0.08 it was still 27 of 33 bad.
- One attacker deals about 26 HP in 8 s (1000 HP Quins). Now the bar is 4%, and unheeded attacks don't count.

**3. The follow rate was too low early in a 16v16** (11%; almost everyone is busy fighting). The busy-fighting penalty went from 0.25 to 0.15.

## Measurements (V3)

**16v16, 116 s** (after fixes 1 and 2):
- **Combat:** hit 68%, whiff 6%, blocked 5%, interrupted 21%, 0 errors.
- **Leaders:** Alpha 4, Beta 3, within the cap of 4.
- **Credibility:** 0.44–0.76; trust 0.42–0.63.
- **Signals:** 58 Attack (15 good, 12 bad, 26 unheeded) and 4 Regroup (3 good). 49 followed, 117 refused.
- **Witness reactions:** 32 looks, 17 followed the leader, 10 went with the refuser, 29 ignored.

**Earlier run** (before fix 2): 7 emerged and 4 transfers (lost credibility ×2, outshone, gave up hurt and alone).

**8v8 dev mode, fresh session:** 1 leader per team, within the cap of 2.

**Arena match 8v8** (generated arena, orchestrator teams): 2 Beta leaders (cap 2), 4 of 9 signals followed, IN_GAME, 0 errors.

**P possess:** OK.

## Notes

- **Nobody died in 116 s of 16v16** (1000 HP Quins), so death-driven transfers ("fell") were not seen in this run. The code path exists and is trivial.
- **Telemetry:**
  - Workspace `SocialStats` (JSON: leaders and credibility, signals and outcomes, follow/ignore, witnesses, transfers);
  - per Quin: `SocialRole`, `LeaderCred`, `FollowingLeader`, `LeaderTrust`, `LeaderSignal`, `SocialFocus`, `SocialGuard`.

Next: phase 3, the emergent Leader Showdown.
