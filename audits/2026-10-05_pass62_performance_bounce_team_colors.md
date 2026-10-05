# Pass 62: Frame rate, wall bounce, team colors, glitch, wall-run arc

The owner's list: continue the unfinished items; the arena wall as an impact surface that a body
bounces off like an obstacle; no white outline in the death glitch and a faster flicker; color
the Quins by team for now; and "increasing fps drop from 16vs16, I think its due to many IKs".

## Performance

Measured in a 16v16 (Studio, client and server on one machine), before anything was changed.

- Frame time settles at **23.1 ms (43 fps)** about 45 s in, once all 32 are fighting, and stays
  there: 43 - 45 fps from 45 s to 135 s. It is not a leak: instances, playing tracks (100 - 130)
  and Lua memory are flat. The "increasing drop" is the match warming up.
- Where the frame goes, by switching client scripts off one at a time:

| | ms per frame |
|---|---|
| **QuinDebugHUD** | **10.7** |
| AIGhostHandler (body layers, IK, head look) | 6.0 |
| LiveFeedScreen | 1.3 |
| the other seven client scripts together | about 0.5 |
| what is left (render, physics, server) | 5.6 |

- The body layers themselves (all switches to "None"): 1.6 ms. So the IK and layers are not the
  main cost; the debug HUD was.

**QuinDebugHUD** rebuilt a rich-text card for every Quin on every frame, **with the HUD closed**.
Now a card is rebuilt every 10th frame (a few cards a frame, in turn) and only while the HUD is
open.

**Main (server), per Quin:** a loop every 0.03 s built the debug state label (two raycasts, the
track list, a formatted string sent to every client) whether the label was shown or not. Now
only while `Debug_StateLabels` is on; with bars and labels both off the loop sleeps 0.25 s.

After (16v16, 50 s in):

| | Before | After |
|---|---|---|
| client frame | 23.1 ms (43 fps) | **9.8 ms (102 fps)**, worst 15 ms |
| server HeartbeatTimeMs | 6.8 | 3.1 |

Not done: the 6 ms in AIGhostHandler (4.4 ms of it is there with every layer off: foot rays,
clip corrections, head look for 32 Quins) and the 400 kbps the server sends, mostly attributes.
Those are the next two places to look.

## Arena wall and obstacles: a real bounce

What existed was not a bounce: one look 15 studs ahead on the first update, which added stun and
played an effect at the wall whether the body ever got there. What came back off obstacles was
the physics engine's own; the arena wall gave almost nothing.

Now, in `KnockbackState.update`: a thrown body about to meet a solid upright surface (any
obstacle's side, the arena wall) has the part of its speed across the ground turned back off the
surface (`Knockback_BounceRestitution` 0.55), keeps its vertical speed, and takes
`Knockback_BounceStun` 0.5 s more stun; up to `Knockback_BounceMax` 2 in one knockback, only
above `Knockback_BounceMinSpeed` 25. `KnockbackModule.wallAhead` finds the surface (solid only,
not Quins, not slopes).

Measured: thrown at 90 studs/s at the arena wall it comes back at 49 - 50, turning 5.9 studs
from the face. (One staged throw at the east wall did not launch: staging, not the bounce.)
In a natural minute of 16v16: 1 bounce.

## Team colors

`CombatConfig.BodyColorBy = "Team"` and `CombatConfig.TeamColors` (Alpha blue 40,110,255; Beta
red 230,45,45). `FXService.applyElementAppearance` colors the body by team when the Quin's team
is listed, otherwise by element as before. Checked: 16 and 16. Element effects are unchanged.
Set `BodyColorBy = "Element"` to go back.

## Death / teleport glitch

`VfxModule.holoGlitch`: no outline at all (the white rim), and it flickers every 0.016 - 0.04 s
(was 0.04 - 0.09). Not looked at.

## Wall run (item 12)

- The arc is integrated every frame by the state's own loop; the 10 Hz update only ends the run.
  Vertical speed changed in steps of 4 studs/s every 0.1 s; now 0.16 per frame (median), 0.35 max.
- The kick: the mover holds only the two ground axes, so gravity has the body from the first
  frame (vertical 18, 17, 16 ... instead of 0.22 s dead level, then a drop).
