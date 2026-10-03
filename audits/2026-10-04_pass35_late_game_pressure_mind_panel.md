# Pass 35 (2026-10-04): late-game stalling has a limit; a mind panel for the spectated Quin

## A. Late-game pressure

Owner: once most Quins are hurt they turn timid. Keep that, but not for long: "this is taking too
long, I can't keep retreating, I should make a move", or wait the other side out; and they should
weigh the match clock ("if I stall like this I lose anyway").

### Baseline (16v16, 5 minutes, flat arena, before any change)

- Health falls steadily (about 0.4% per second each) to an average of about 30% at 210 s.
- From about 220 s the fight dies off: time in Fight 35% -> 7-13%; Retreat + Overwatch + Circling
  up to 60%. Average health barely moves after that (28% at 220 s, 22% at 300 s).
- 1 knockout in 300 s (at 234 s). The Pass 34 lull clock never fired (longest lull 9 s): hits keep
  landing somewhere, so it never "goes quiet".

### What was added (`Modules/SocialTension`, tunables `CombatConfig.Social.Tension`)

Three more things press on a Quin, into the Pass 34 outlet (urgency, Waiting / Restless,
contagion, DecisionSystem):

- **Drought**: seconds without a knockout, counted only while the field is hurt (average health
  below `KillHurtFrom` 0.45, full weight at 0.25); presses after `KillGrace` 20, full after
  `KillFull` 30 more; a knockout takes `KillRelief` 15 off.
- **Clock**: the last 40% of the match (`ClockFrom` 0.6). The side losing on time (fewer alive,
  else less health, as `decideWinner`) feels all of it, the side ahead a quarter, a level field
  0.6. The Arena publishes `MatchEndsAt` / `MatchLength` (three lines in
  `ArenaSystemOrchestrator`); other modes use `NominalMatchTime` 300 s from the first exchange.
- **Stalling**: a per-Quin meter that fills while it is in Retreat / Overwatch / Circling / Idle
  (faster the later it is) and drains while it fights; it lowers that Quin's patience.
- **Not running** (`SocialLastStand`, read by DecisionSystem's survival instinct): a nearly dead
  Quin on the side losing on time, a side whose clock is all but gone, or a Quin whose stall meter
  is full ("I have run enough": it turns and fights until that has worn off).
- `SocialWhy` says which of them it was (Lull / Drought / Clock / Stall / Futile).
- Crowd: `ClockRunningOut` (mapped to ExcitedCrowd in `ArenaConfig`).
- Dev hooks: `TensionDevCommand "nokill <s>"`, `"clock <seconds left>"`.

### Results

| Run | Knockouts | Notes |
|---|---|---|
| Baseline, 300 s | 1 | fight share 7-13% from 230 s |
| All sources, 300 s (first version) | 11 | restless from 190 s; nearly dead Quins still fled at the end |
| Clock off, field started at 38% health, 230 s | 20 | all Waiting at 40 s, all Restless at 50 s |
| **Final, 300 s** | **13** | first at 194 s; 19 left (4 v 15), average health 10% |

Final run, by time: untouched until 180 s (nobody Restless or Waiting); 25 Restless at 190 s; fight
share back to 25-35% from 200 to 270 s, 13-17% in the last 30 s. 4-5 Quins Waiting from 250 s.
Strikes over the run: hit 66%, whiff 7%, interrupted 21%, blocked 6% (baseline 66 / 8 / 18 / 8).
No script errors.

### Follow-up: a badly hurt Quin flees slower (owner: "go ahead")

`RetreatState`: below `Retreat_WoundedFrom` (25% health) the flee speed falls off, down to
`Retreat_WoundedSlow` (20%) less at death's door. Only the flee is slowed; chasing and fighting
speeds are unchanged.

16v16, run to the end: 17 knockouts by 300 s (13 before this, 1 at baseline); fight share stays
24-27% through 280-310 s (was 13-17%); 1 v 11 at 340 s; the match ended by elimination at 403 s
(21 knockouts; the last minute is the respect custom for the lone survivor). Strikes: hit 65%,
whiff 7%, interrupted 20%, blocked 7%. No script errors.

### Open

- Before the follow-up the match did not end inside the nominal 300 s (19 of 32 left). With it,
  one run ended at 403 s; one run is not a distribution.
- A real Arena match (`MatchEndsAt` published and cleared) was not run. The `clock` dev hook and
  the forced 6 v 4 "battle of wits" case were not run on their own; the Pass 34 lull recipe was
  not re-run.

## B. Mind panel

Owner: when spectating a Quin, show its HP, mana and what it is thinking, as thought lines; leave
the Spectator HUD alone.

- `StarterPlayerScripts/QuinMindPanel` (new, own ScreenGui, left edge): name, team, role, HP and
  mana bars, what it is doing, the three best options it weighed, and a stream of first-person
  thoughts (newest at the bottom, time-stamped, older lines dim, 60 kept). Shows while Workspace
  `SpectatedQuin` names a Quin (set by the Spectator HUD and the Quin Manager).
- `Modules/ThoughtVoice` (new): phrasings per key; bold and careful Quins say some things
  differently; an unknown key shows as its own name.
- `DecisionSystem`: every reason now has a key (`because("HealthLow", ...)`, 26 of them), and a
  Quin marked `MindWatched` publishes `Mind` = "action|tactical state|reason keys|three best options".
- `ServerScriptService/Server`: `MindWatchEvent` marks the Quin each spectator watches (one per
  viewer; the old one is unmarked and its `Mind` cleared). The other Quins publish nothing.
- Checked in Play: panel fills for a watched Quin (HP 788 / 1000, mana 74 / 100, options, thoughts);
  switching Quin moves the mark; clearing `SpectatedQuin` hides the panel and unmarks. Late game a
  restless Quin read "Time's running out. If I stall, we lose." The check set the attribute
  directly; it was not driven through the Spectator HUD's own buttons.
- A thought is not repeated within 4 s; the stream is still fast when decisions flip.
