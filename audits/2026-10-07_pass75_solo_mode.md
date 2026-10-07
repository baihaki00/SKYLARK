# Pass 75: Solo mode (the player's Quin alone)

The owner asked for a Player Quin mode with no other Quin, to work on movement by itself.

## What

- **Arena System panel:** a fifth match mode, **Solo** (`Mode = "PlayerSolo"`). The team size buttons grey out as for a duel.
- **Spawn:** the player's Quin alone, in the middle of the dais (the same dais and arena handling as Player Quin; Procedural Arena Generation on keeps the obstacles).
- **The match:** ends only when the game time runs out or the player's Quin dies. The winner line reads the player's name, "Solo Session Over".
- **The panel's five mode buttons** are 76 px wide (was 100) to fit the 425 px column.

## A bug found on the way

`PilotClient`'s lock diamond set `Adornee = false` every frame while nothing was locked (`locked and ...` gives `false`, not `nil`). That threw an error every frame in every Player Quin match. Fixed.

## Checked (Studio, InstantMatch)

| Check | Result |
|---|---|
| Quins spawned | 1, piloted, `Piloted` state |
| Match still running after 40 s | yes |
| Server / client errors | 0 / 0 (after the fix) |
| Mode buttons | all five inside the column, text fits |

Not checked: driving the Quin by hand in Solo (the owner's test).
