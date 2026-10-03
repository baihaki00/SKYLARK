# Pass 33: Respect Custom, Final Fight, Comeback and Big Clutch (Social layer, Phase 4)

## What it does

New part `SocialRespect` (`CombatConfig.Social.Parts`), with tunables in `CombatConfig.Social.Respect`.

### 1. Qualifying

A lone survivor qualifies only when:
- it faces at least `MinRatio` (3) opponents, **and**
- its contribution passes this match's threshold.

Contribution is kills × 1 + damage / 250 + 0.5 per minute. The threshold is `ContributionThreshold` (3) × a per-match random factor of 0.8–1.6, so most N-v-1 situations never qualify.

### 2. Recognition

Each opponent that perceives the survivor raises its own recognition:
- Perceiving means within 25 studs, or within 70 studs with line of sight.
- The rate is `RecRate` × the survivor's contribution strength, plus `ContagionRate` per ally within 30 studs who is already hesitating (capped at `ContagionCap`).

As recognition builds, each Quin goes through three stages:
1. **Hesitating:** a step back, a look at the survivor, then a look and a nod at an ally ("cool down, he's alone").
2. **Watching:** stands off 20–28 studs.
3. **Making space:** backs off 32–40 studs.

A hit from the survivor sets that Quin's recognition back. Quins that have stood down pick no target, and the candidate survivor leaves them alone.

### 3. Agreement

The custom is agreed once enough opponents are making space: max(`AcceptMin`, share × count).
- The survivor becomes **Honored**: it stops attacking and looks round at them.
- Each spectator picks a spot on its own bearing, measured from the ceremony edge:
  - close: 3–8 studs out
  - ring: 10–40 studs out
  - far: 50–70 studs out
- Each spectator leaves after its own 0.5–4 s delay, at its own pace: walk 70% / jog 20% / run 10%.
- The two duellists wait just outside the ceremony space.

### 4. Ceremony platform

- It rises at the arena centre only if the centre is clear and nobody stands in its footprint. Anyone idling there is walked out first.
- It is built as **tiers of 0.4 studs**, each lower than a Quin's collision-body clearance of 0.5 studs, so Quins walk straight up it.
- After it rises, the leader (or the opponents' best Quin) walks in, and the survivor answers 1.2 s later.

### 5. The duel

- It starts when the two are within 30 studs of each other near the centre. A 30 s timeout is the fallback.
- Only the two duellists may fight.
- The duellists are held on the dais:
  - outward velocity is cancelled past `CeremonyRadius − DuelEdgeMargin`;
  - a duellist who ends up off the dais jogs back.
- The ceremony constraint now applies only to duellists.

### 6. Outcomes

- **The leader wins:** the custom ends, the platform sinks, and spectators drift back at their own times.
- **The survivor wins:** events UnexpectedLeaderDefeat, then HonorableComeback. Each remaining opponent rolls its own reaction from the weighted list: hesitate / attack / back away / one at a time / coordinated / avenge (`GrudgeTarget`) / finish.
- **+2 kills:** BigClutch. Everyone holds still, looks at each other, then looks at the survivor.
- **Clearing the field:** Historic. The after-clutch response is picked from HP and energy, using blank animation slots.

### 7. Crowd

`ArenaCrowdManager` hushes on RespectCustom and un-hushes on the end or a leader defeat. It plays one reaction per event from `ArenaConfig.CrowdFX.SocialReactions`.

## Measured (Studio Play, generated arena, 8v8, 7 Beta killed, survivor seeded 5 kills / 2000 damage)

| Check | Before fixes | After |
|---|---|---|
| Recognition, first hesitation to agreement | ~4 s | ~10 s, staggered per Quin (5.5 to 15.6 s) |
| Platform rises | never: a "close" spectator stood inside the footprint (radius 84 < 92) | 11 s after agreement |
| Duellists reach the dais | no: they stalled at the 1.5-stud step edge (radius 87); the duel started by timeout at radius 90–125, ground level | yes: they walk up the tiers (y 10.4 on the dais vs 7.4 on the ground); the duel starts by proximity |
| Duel position (35 s sample) | max radius 132 | median 30, p90 81, max 88; ceremony edge is 92 |
| Spectator hits on duellists during the duel | — | 0 |
| Leader-win path | — | "leader won"; platform gone; 0 leftover roles |
| Comeback path | — | UnexpectedLeaderDefeat then HonorableComeback; reactions rolled (e.g. hesitate 4 / one-at-a-time 2 / coordinated 1); "survivor fell after the comeback"; clean-up OK |
| `SocialLastError` | — | nil |

## Not yet measured

- The BigClutch and Historic paths. A test with 40-HP opponents stalled (low-HP Quins circle and retreat), and Studio's Play control then hung.
- The crowd hush in a live Arena match.
- The regression set: 16v16 hit rate, Arena match to IN_GAME, P possess.

## Files

- `Modules/SocialRespect.lua` (new)
- `SocialSystem`: `standsDown`; plain signals
- `SocialLeaders`: `standingOf`
- States Chase, Circling, Fight, Idle and Retreat; `Main`; `TargetingModule`: stood-down Quins pick no target
- `CombatConfig.Social.Respect`
- `ArenaCrowdManager` (hush and reactions)
- `ArenaConfig.CrowdFX.SocialReactions`
