# QUIN TEST MATRIX & VALIDATION BENCHMARKS

This document defines the standardized test suites, test configurations, assertions, and invariant criteria used to validate the Quin codebase.

---

## 1. Automated Deterministic Scenarios (`BattleSimulationHarness.lua`)

The `BattleSimulationHarness` executes 11 programmatic scenarios covering combat edge cases, tactical decisions, and state transitions without human intervention.

| Scenario ID | Name | Fighters | Invariant Criteria | Pass Condition |
| :--- | :--- | :--- | :--- | :--- |
| **01** | `Scenario_01_OneVsOne` | 2 | Symmetric 1v1 duel. Both fighters target each other; states cycle dynamically. | Exactly 2 fighters; dynamic state cycling (Fight, Circling, Dash). |
| **02** | `Scenario_02_TwoVsOne` | 3 | Asymmetric pressure. Lone defender evaluates outnumbered tactical retreat. | Lone defender does not freeze; evaluates disengage when health drops. |
| **03** | `Scenario_03_IsolatedTarget` | 4 | 2v2 with one fighter isolated from team. AI detects separated opponent. | Both allies prioritize the isolated target via distance weighting. |
| **04** | `Scenario_04_Rescue` | 3 | Distressed ally with low HP ($< 300$). Guardian personality triggers rescue dash. | Guardian intervenes between threat and wounded ally. |
| **05** | `Scenario_05_LocalNumericalAdvantage` | 4 | 3v1 local clustering. AI exploits advantage with aggressive melee. | Attack cadence increases; flanking positions adopted. |
| **06** | `Scenario_06_OutnumberedRetreat` | 4 | Outnumbered fighter backs away from 3 converging opponents. | Retreat state triggers; fighter maintains distance from swarm. |
| **07** | `Scenario_07_Pursuit` | 2 | Target flees at high speed. Chaser engages sprint/dash pursuit. | Chaser switches to `ChaseState` / `DashState`; closes distance. |
| **08** | `Scenario_08_TargetSwitch` | 3 | Wounded target enters engagement radius. Opportunist personality switches target. | Utility evaluation re-ranks target; opportunistic switch confirmed. |
| **09** | `Scenario_09_ResourceExhaustion` | 2 | Critical stamina/energy ($< 30$). Fighter enters defensive circling to regen. | Fighter paces at perimeter; avoids high-cost moves until recovered. |
| **10** | `Scenario_10_LastStand` | 3 | Defender at critical health ($\le 20\%$). Triggers desperate counter-attack profile. | Aggression surges; high-risk finishers prioritized before defeat. |
| **11** | `Scenario_11_BenchmarkQuin` | 5 | 4 combatants + 1 Benchmark telemetry recorder logging 60 Hz performance. | Zero memory leaks; stable frame rate; full telemetry JSON emitted. |

Execution:
```powershell
python Tools/Benchmarks/SimulationHarnessBenchmark.py
```

---

## 2. Match Stress Suites (`GameModeManager.lua`)

### Suite A: 1v1 Sparring Match
- **Spawn Count**: 2 Quins (Team A vs Team B).
- **Spectator HUD Cards**: Exactly 2 cards.
- **Camera**: Centroid midpoint tracking.
- **Duration**: Until one fighter HP drops to 0 or timeout (60s).
- **Invariants**:
  - Gaze tracking (`LookController`) active across both fighters.
  - Directional hit recoil (`ProceduralCombatReactionController`) triggers on hit confirmation.
  - Zero state deadlocks (neither fighter remains in `IdleState` while enemy is alive).

### Suite B: 2v2 Team Battle
- **Spawn Count**: 4 Quins (2 Team A vs 2 Team B) + dynamic ghosts (Total 8 models across Server and Ghost).
- **Spectator HUD Cards**: Exactly 4 arena cards (or 8 ghost representations).
- **Invariants**:
  - Friendly fire disabled between teammates.
  - Tactical perception detects teammate proximity and distributes targets.
  - Spectator camera dynamically expands viewport to encompass all 4 combatants.

### Suite C: 4v4 Skirmish & 16v16 Battle
- **Spawn Count**: 8 to 32 combatants.
- **Purpose**: Measure spatial perception clustering, spatial hash performance, and physics solver load.
- **Invariants**:
  - Frame rate $\ge 55\text{ FPS}$ on test hardware.
  - Memory consumption remains stable without continuous linear growth.
  - Zero collision snags between invisible HRP colliders.

---

## 3. Physical State & Animation Invariants

1. **Grounded Invariant**: `RecoveryState` must never trigger while physical clearance from collider bottom to floor is $> 0.5\text{ studs}$ (unless hard watchdog timeout expires).
2. **Animation Track Mutual Exclusivity**: `FallAirKnockback` must be strictly stopped upon entering `RecoveryState` or returning to combat.
3. **Idempotent Pose Invariant**: Skeletal bone transforms must return to within $0.05\text{ studs}$ and $0.05\text{ rad}$ of the base animation pose within $0.5\text{s}$ of combat recoil settling.
4. **Arena Isolation Invariant**: Static scenery rigs (`QuinTest`, `QuinTypeA`) must never be added to `QuinRosterService`, targeted by combat AI, or rendered on `QuinDebugHUD`.
