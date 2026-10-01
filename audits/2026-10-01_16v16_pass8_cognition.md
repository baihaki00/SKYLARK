# Pass 8 (2026-10-01): cognition layers (plan phase 3)

Studio backup: `ServerStorage.backup_pre_16v16audit8_20261001`.

## Structure

`QuinCore.Cognition` runs once per reasoning tick for each Quin and keeps every layer's result
on that Quin's blackboard:

```
WORLD -> Senses -> Attention -> Memory -> SelfAwareness -> EnvironmentAwareness
      -> SituationAwareness -> TargetingModule / DecisionSystem / states
```

| Module (`QuinCore/Cognition/`) | Answers | Notes |
|---|---|---|
| `Senses` | what reaches me this tick | sight (200 degree cone, 260 studs, clear line of sight), hearing (12-40 studs by awareness, noisy Quins only), touch (within 10 studs, or whoever just hit me); allies always known |
| `Attention` | what matters most | salience per noticed enemy (distance, my target, after me, swinging at me, in my face, wounded); only the top N are attended; N = 2-6 by awareness, fewer while fighting (aggressive Quins tunnel most) |
| `Memory` | who do I know about, how well | tracks with last position / velocity / time; confidence decays (4-14 s by awareness), believed position dead-reckoned 1.5 s, forgotten below 15%; allies within 60 studs pass on what they see; with no contact at all, a low-confidence "rumour" of the nearest enemy |
| `SelfAwareness` | what is happening to me | health, energy, velocity, airborne / grounded, recent damage, how long my movement has been stalled |
| `EnvironmentAwareness` | what is around me | retreat room and direction, platforms within reach (spatial queries stay in `SpatialModule`) |
| `SituationAwareness` | what does it mean | the tactical context (numbers, quadrants, surround, pursuer, escape feasibility, team state), built only from contacts + self + environment |
| `Blackboard` | — | per-Quin store of the above |
| `Layers` | — | on/off switches for Senses / Attention / Memory |

`Modules/TacticalPerception` is now a facade over the pipeline (same name, same returned
fields). `TargetingModule.getNearest` picks from the Quin's contacts instead of scanning every
living Quin.

Strategy, tactical reasoning and action are unchanged: `DecisionSystem` and the FSM states.

## Ablation

`CombatConfig.Cognition.{Senses, Attention, Memory}` are the defaults; the Spectator HUD has
three "AI:" switches that change them live for every Quin (workspace `Cognition_<Name>`).
A switched-off layer returns its neutral result:

- Senses off: every living enemy is noticed wherever it is (the old behaviour).
- Attention off: everything noticed is attended.
- Memory off: no persistence; a Quin knows only what it attends this tick.

New debug layers: "Senses: cone + what it notices", "Attention: focus list",
"Memory: remembered enemies". The overhead label shows how many enemies the Quin knows and
notices, and through which channel it knows its target.

## Verification

- **Refactor is behaviour-preserving**: with all three layers off, the new pipeline and the
  previous `TacticalPerception` were evaluated on the same Quins in the same frame — 192
  evaluations, 35 scalar fields, 5 model fields, 8 list sizes and the target info: no
  differences.
- **Layers on**: no script errors; idle time 1%; fights continue (12-18 hits/s).
- **Each switch changes what Quins know** (20 s windows in one match, so the battle phase
  differs between rows — this shows the switches work, it is not a controlled comparison):

  | Config | Enemies known | Noticed and attended | Attention capacity |
  |---|---|---|---|
  | all on | 15.5 | 3.9 | 4.1 |
  | Memory off | 4.0 | 4.0 | 4.3 |
  | Attention off | 16.0 | 9.7 | 9.7 |
  | all off | 15.1 | 15.1 | 15.1 |

  With all on, a Quin's target is known by sight 38-45% of the time, touch 42-51%, hearing 7%,
  memory or report 2-5%.

## Limits

- In a 16v16 brawl everyone is close, so memory plus reports still gives each Quin a track on
  nearly every enemy; the layers matter more as fights spread out (phase 4).
- States still read the target's true position once it is the target; believed / predicted
  positions are used for the tactical context and the debug layers only. Chase already walks
  to the last seen position when it has no line of sight.
- No behaviour was added for searching; "rumour" keeps a blind Quin heading for the nearest
  enemy.
