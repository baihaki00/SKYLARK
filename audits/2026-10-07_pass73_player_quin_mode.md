# Pass 73: Player Quin match mode (you against AI Quins on the dais)

**The owner asked for:**
- a match mode in the Arena System where they pilot a Quin against AI Quins: me vs 1, 2, 4 and up;
- spawning on the round dais, with or without obstacles;
- additions shared between the player and AI Quins, so only the inputs differ;
- focus on chase, retreat and combat;
- player vs AI only, no PvP yet. It should still be a base for PvP later.

## How it is built

| Piece | What it does |
|---|---|
| Arena System panel | New mode **Player Quin**; the size buttons read "Me vs 1/2/4/8/16". *Procedural Arena Generation* is the obstacles switch (off: an empty arena round the dais). |
| `ArenaSystemOrchestrator` | Mode `PlayerQuin`: the player who presses START pilots. During generation, the obstacles-off case calls `ArenaGenerator.clearArena()`. The dais rises in the arena centre (`SocialRespect.buildDais`, the respect ceremony's own dais). Your Quin (TeamAlpha) and the AI line (TeamBeta) spawn on it, `SpawnGap` apart. The AI Quins get `EnableProjectileJump = false` (`CombatConfig.PlayerQuin.AIProjectileJumps`). The usual phases, winner and STOP apply; the dais sinks on stop. |
| `ArenaGenerator` | `clearArena()` (edit-mode obstacles stashed, nothing generated), `getCenter()`. |
| `SocialRespect` | Exposes its dais: `buildDais`, `sinkDais`, `daisRadius`, `daisTop`. |
| `StarterPlayerScripts.PilotClient` (new) | Reads keys and sends them over `ReplicatedStorage.PilotInput`. Sets `shared.PlayerControlledQuin`, so SmoothCamera's existing orbit follows the Quin. |
| `Modules/PilotInput` (new) | Server side of the input. Only the player in the Quin's `PilotedBy` attribute can drive it. Started from `Server.server.lua`. |
| `States/PilotedState` (new) | Stands where the AI's decision states would. Moving: `LocomotionModule.steer` + `GaitModule`. Standing: `brake`. Strike: `FightState.throwStrike`, after `FightState.faceTarget` on the nearest enemy within 12 studs (favouring the one pushed toward). Guard: `IsGuarding` + the block clip, held. Dash / slide / jump: `LocomotionModule`. A click mid-strike is buffered 0.35 s and thrown at Recover, so a click chain becomes the combo. |
| `Main` | A Quin with `PilotedBy`: no AI targeting / decision overrides / headroom or edge corrections. Every voluntary state becomes `Piloted`. Knockback, Recovery, Death and ReEntry stay the shared states (`PILOT_STATES`). |
| `FightState` | `throwStrike(fighter, humanoid, root, target, "Light"/"Heavy", data)` and `faceTarget(root, targetHRP, data)` are now public. The AI's own light and heavy strikes go through `throwStrike` too. `executeAttack` accepts no target (a strike at the air). |

**The server owns your Quin's body**, the same as an AI's: no network-ownership change, and every effect (knockback, lunges, hit outcomes) is the AI path. The cost is input latency equal to ping. That is invisible in Studio; a live PvP mode would later want client prediction.

**Keys:**
- WASD move (camera-relative); hold Shift to run (the Quin's own `Speed`); Z toggles walk; the default is a jog;
- left click strike; hold right click guard;
- Space jump, C slide, Q / E dash.

**Untouched:** the old Play As Quin costume (P) still exists for free roam. P is ignored while piloting a match Quin.

## Measured (Studio, keys and mouse sent through the MCP)

- **Spawn:** you 20 studs from the centre and the AI line opposite, all on the risen dais (top +3 studs).
- **Obstacles on:** a generated arena (123 pieces) round the dais. **Off:** an empty arena.
- **Jog:** a steady 12 studs/s while W is held (AI frozen for the test), and it stops on release.
- **Strikes:** 4 clicks gave 4 strikes on marker timing, the first the Wheeldrive kick. 2 hits (12 damage each); the last 2 whiffed because the frozen target had been pushed out of reach.
- **Getting hit:** guard on and off, dash (~54 studs/s), jump; Knockback → Recovery → Piloted works.
- **Camera:** SmoothCamera in `QUIN_SPECTATE` on your Quin, 14.7 studs behind.
- **Me vs 4, obstacles on:** all four AIs target your Quin.
- **Me vs 2, 45 s, AI projectile jumps off:** AI time Chase 82 %, Fight 11 %, Circling 8 %.
- **Errors:** none (only Studio's DataStore notices).

**Also fixed:** IdleState's opening projectile jump ignored the per-Quin `EnableProjectileJump` attribute.

## Not done / open

- **By feel (owner):** how piloting and the fights feel. The pace scheme is the Play As Quin one: jog by default, Shift run.
- **No heavy strike input** (only Light combos).
- **No AI teammates on your side:** solo vs N.
- **Social layer:** respect customs and leaders still run among the AI Quins.
- **No PvP**, by the owner's choice.
