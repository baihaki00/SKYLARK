# Pass 64: The stop-run clip only out of a full run. Pass 65: the mind panel says more

## Pass 64: stop-run

The owner: "the run_stop animation, only play that after the quin reached top speed".

`LocomotionModule.brake` played `Movement.StopRun` whenever the Quin braked above 24 studs/s, or
was flagged as sprinting and above 12. Now only when it brakes from at least
`StopRun_TopSpeedShare` (0.9) of its own top speed (its `Speed`); anything slower just slows down
with the gait.

16v16, 55 s each (two matches):

| | Before | After |
|---|---|---|
| stop-run clip played | 108 | 37 |
| ... from a run that reached 90 % of top speed | 72 | 37 |
| slowest run it played from | 60 % of top speed | 92 % |

## Pass 65: mind panel (item 14, "we miss a lot")

The panel only voiced the decision system's reasons and the social layer. Everything added
since (target commitment, traversal, tackles, the wall) was silent. It now also says:

- **Why it turned to someone else**, once per change, naming the new target, from
  `TargetChangedBy` (Pass 59): the utility choice, a rear threat, a passer-by, a dive, an
  interception, a duel.
- **How it is getting about**, from the `ObstacleAwareness` line the states already publish and
  from its state: wall run, slide tackle, sliding under a gap, backing off for a run-up, a jump
  up, stepping stones, a projectile jump, an air dash, getting down, vaulting, going round, no
  room to stand.
- **What is done to it**: thrown, legs taken by a sweep, hopping a slide, getting up.
- **Where it should not be**: on the wall, outside the arena (`Trespass`).

`ThoughtVoice` got the phrasings (bold and careful where it matters), the pattern table from
awareness line to thought, and `say(key, aggression, name)` for lines that name someone. The
"doing" line knows WallRun, Airborne and ReEntry. No new attributes and nothing on the server.

Checked on a spectated Quin in a 16v16: 50 lines in 45 s, among them "I'm in the air. Brace.",
"On your feet.", "Go low. Take his legs.", "Too far to run. Jump it.", "Turn. Quin_Female_BAB2
is on my back.", "Quin_Male_C2AC. You're next."; no client errors. A doubled line (going round a
body said twice) was removed afterwards; that last change was only compile- and call-checked.

Not done: the left column (name, bars, doing, options) is unchanged; the trespass lines were not
seen in play (nobody went on the wall while watched).
