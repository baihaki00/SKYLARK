# Pass 34 (2026-10-03): standoff, spectators, lulls, the hunt after a comeback

Owner's notes on Pass 33: (1) spectators stayed frozen in their last pose; (2) the duel started at
once, wanted a real standoff that spirals in, with a sudden break, not strictly on the dais;
(3) late in a 16v16 both sides chase and retreat for ever: keep it, but they should get restless
("this is taking too long, the crowd is watching") or wait each other out; (4, 5) after the leader
falls the rest should be shocked, then hunt the survivor together, some holding back, and not
retreat casually. The crowd follows the story.

Written by the previous session (which hit its usage limit after testing, before the commit);
exported, checked against Studio and committed by the next one. The figures below are the
previous session's own, from its Play runs.

## What changed

- **Spectators** (`SocialRespect`, `IdleState`, `SocialSystem.watch`): a stopped spectator settles
  into idle and turns to face the fight; every `WatchThink` seconds it stays, paces along the dais
  edge (more when the fight is heated or it is aggressive) or steps back; it drifts with the fight.
- **Standoff** (`SocialRespect`; `Chase` / `Circling` / `Fight` read `SocialStandoff`): the two
  circle, closing from `StandoffStartGap` 34 to `StandoffMinGap` 9 over 7-16 s, a walk that becomes
  a prowl; one of them breaks it (chance grows as the circle tightens). The dais edge is a pull
  (`DuelGravity`), not a wall.
- **Lulls** (new `Modules/SocialTension`, tunables `CombatConfig.Social.Tension`): a lull clock
  runs while field damage is below `LullDamageRate`, faster with a crowd (`CrowdPhase`, published
  by `ArenaCrowdManager`). Patient Quins wait ("you move first", the side ahead longer); then they
  turn restless one by one (`SocialUrgency`), allies near one that goes go with it, the enemy it
  goes for answers. `DecisionSystem` cuts Retreat and raises Pursue / Attack / Dash with urgency.
- **Comeback** (`SocialRespect`): `ShockTime` 1.4-2.4 s, then `pack` 0.6 / `avenge` 0.15 hunt the
  survivor (`SocialHunt`), `reserved` 0.25 watch and join later. Hunters only flee below 8% health
  and run 12% faster (`HuntSpeedBoost`).
- **Crowd** (`ArenaConfig`): StandoffBreak, ComebackHunt, ComebackKill, BigClutch, ComebackFall,
  Historic, StalemateTense, StalemateBroken.

## Found while testing, fixed

- Hunters ran at the survivor's speed and never closed: the 12% speed edge. Median gap 80 -> 29
  studs; hunters' time fighting 5% -> 13%.
- A false "stalemate broken" cheer at the start of a match: the lull clock counted before anyone
  had fought (`fightingSeen`).
- Restless Quins still spent about 20% of the time in Overwatch and 13% in Retreat: urgency now
  shortens Overwatch (watch time up to -80%, hard cap up to -75%) and the Circling standoff (up to
  -60%); a restless or hunting Quin leaving Recovery goes after someone instead of holding a
  platform; at full urgency the near-death flee threshold drops from 20% to 4% (`SurvivalCut`);
  a restless or hunting Quin cuts a retreat short.

## Runs

- Comeback, 8v8, survivor at normal health: leader falls, hunt with reserved Quins joining,
  survivor worn down, crowd disappointment, dais sinks, clean-up, done at 265 s, no errors.
  The Big Clutch / Historic path did not fire (the survivor scored no further kills).
- Lull, 4v4 forced to 30% health: before the last fixes, no kill after 100 s and 3-8% fighting
  with all eight restless. After: the stalemate broke at 28 s, restless Quins fight 30-44% of the
  time, Retreat 0-6%, Overwatch gone, no errors.
- A full 16v16 did not reach a lull by itself within 113 s.

## Open

- Big Clutch / Historic not seen in Play.
- The standoff and the spectators were watched by the owner, not measured.
- Crowd reactions in a live Arena match not checked.
