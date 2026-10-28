---
name: social-layer
description: "Pack Leaders / Respect Custom / emergent arena events — the approved 4-phase plan, what phase each is at, the attribute contract, and scope rules"
metadata:
  node_type: memory
  type: project
  originSessionId: 47a04467-99e0-402c-9621-1043e0dec9de
  modified: 2026-10-03T14:41:01.233Z
---

**Brief:** the owner's "Pack Leaders, Respect Customs & Emergent Arena Events" (2026-10-03). The plan is in `C:\Users\User\.claude\plans\woolly-juggling-emerson.md`.

**Scope (owner):**
- In-game events only. Skip personality, moods, moodlets and anything unrelated.
- New animations stay **blank slots** (`AnimationConfig.Registry.Social`) with procedural fallbacks.
- Quins never speak: body language only.

**Owner decisions:**
- The old scripted LeaderShowdown is deleted entirely.
- The Respect Custom ceremony is at the arena centre, but it must **look agreed**: no snap-turning chasers. The stronger side eases off ("cool down, he's alone"), with staggered slow walks, some jogs or runs, random but organized.

**Phases:**
1. Foundation, done in Pass 30 (`6e20693`): `Modules/SocialSystem`, attribute contract, social head look and nod, removal of the old showdown.
2. Pack Leaders, done in Pass 31 (`dda04cd`): `Modules/SocialLeaders`, tunables in `CombatConfig.Social.Leaders`, telemetry in Workspace `SocialStats`.
3. Emergent Leader Showdown, done in Pass 32 (`db0e75d`): `Modules/SocialShowdown`. Duels are held via TargetingModule `TargetOverride`, because `selectTarget` only scores the local `NearbyEnemies`, so a score term alone can't reach a distant opponent. Dev hook: `ShowdownDevCommand`.
4. Respect Custom → final fight → Honorable Comeback → Big Clutch, plus the escalation tracker. First pass done in Pass 33 (`4308a4e`): `Modules/SocialRespect`, tunables in `CombatConfig.Social.Respect`.
   - **Test recipe:** `ArenaGenDevCommand "run 10"`, `DevCommand "team:8"`, kill 7 Beta, then `RespectDevCommand "seed <survivor> 5 2000"`.
   - **Still open:** BigClutch / Historic not yet measured (low-HP opponents stall: they circle and retreat), crowd hush in a live Arena match, and the 16v16 / Arena / P-possess regression.
   - **Gotcha:** a Quin's only collider is `CollisionBody`, 0.5 studs off the floor, so any step taller than 0.5 stops it dead. Ceremony dais tiers are 0.4 (`CeremonyTierHeight`).
   - **Gotcha:** the constraint hooks (`constrainToCeremony`) run for every Quin, so they must filter by role.

5. Pass 34 (`d244621`), from the owner's notes on Pass 33: spectators idle / pace the dais edge, a standoff that spirals in before the duel (`SocialStandoff`), lulls (`Modules/SocialTension`, `CombatConfig.Social.Tension`: `SocialUrgency`, `SocialPosture` Waiting / Restless, Workspace `TensionStats`, `CrowdPhase`), and a hunting pack after a comeback (`SocialHunt`, 12% speed edge, flee only under 8%).
   - The session that wrote it hit its usage limit before committing; the next one exported and committed. Leaders emerging again right after the leader falls is **correct behaviour** (owner).
   - **Still open:** Big Clutch / Historic not seen in Play, crowd in a live Arena match, P possess. 16v16 regression is fine (hit 67%, whiff 6%).
   - **Lull test recipe:** a full 16v16 does not thin out within ~110 s; force it (4 per side at 30% health).

6. Pass 35 (`2aff3ef`, 2026-10-04): late-game pressure in `SocialTension` (owner: timid late game is fine "but not too long"; they must weigh the match clock). Sources: kill drought (only while the field is hurt), match clock (side losing on time feels it all; Arena publishes `MatchEndsAt` / `MatchLength`, else `NominalMatchTime` 300), per-Quin stall meter, `SocialLastStand` (DecisionSystem's survival instinct off), `SocialWhy`. 16v16 5 min: 1 knockout -> 13; early game untouched until 180 s; hit rate unchanged.
   - **Baseline fact:** without it the fight dies at about 220 s / 28% average health (Retreat + Overwatch + Circling 60%).
   - Follow-up (owner approved): a fleeing Quin under 25% health runs up to 20% slower (`Retreat_WoundedFrom` / `Retreat_WoundedSlow`, RetreatState only). One 16v16 then ended by elimination at 403 s (21 knockouts).
   - **Open:** only one full-length run; a real Arena match with the clock not run.
   - **Test shortcut:** start the field hurt (`Humanoid.Health = 0.38 * Max`) and `TensionDevCommand "clock 99999"` to isolate drought + stalling.

**Mind panel (Pass 35):** `StarterPlayerScripts/QuinMindPanel` + `Modules/ThoughtVoice`; shows for Workspace `SpectatedQuin`; server marks `MindWatched` via `ReplicatedStorage.MindWatchEvent`; DecisionSystem reasons carry keys (`because(key, text)`) and the watched Quin publishes `Mind`. The owner wants the Spectator HUD (QuinDebugHUD) left alone: new spectator info goes in this panel. New reasons need a phrasing in ThoughtVoice (an unknown key shows as its name).

**Attribute contract:**
- `SocialRole`, `LeaderCred`, `FollowingLeader`, `LeaderSignal` / `LeaderSignalAt`
- `SocialMoveTo` / `SocialMovePace` / `SocialMoveUntil`
- `SocialLookAt` / `SocialLookUntil`, `NodAt`
- `RespectRole` (Hesitating / Watching / Spectator / Duelist / Honored), `SocialHoldOff`
- Workspace `ArenaEventLevel` / `ArenaEvent`, `RespectCustomActive`
- BindableEvent `ReplicatedStorage.ArenaSocialEvent`

**How to apply:**
- Add each phase through `SocialSystem.addTicker` and attributes; don't rewrite states.
- Measure head motion at **PreAnimation**: Heartbeat shows the next animation step, and RenderStepped connection order isn't guaranteed.

Related: [[combat-whiff-audit]], [[arena-generation]], [[crowdfx-system]]

**Gotcha (Pass 31):** `Main` is **cloned into every Quin** (QuinSpawner). Any thread or connection started from Main dies when that Quin is cleaned up. Long-lived loops must be started from a persistent script (`ServerScriptService.Server`). `SocialSystem.start()` self-heals using a heartbeat and a generation token.
