# Pass 66: The males were darker; standing at the edge (items 11 and 2)

## Male Quins a different color

The owner's screenshot: male Quins darker than female ones of the same team; "I think this is
related to the material".

Checked, in order: same `Color` and `Material` on server and client; vertex colors (all white on
both meshes, read with EditableMesh); normals (unit length, facing out on both); texture
(cleared on both). The difference: **QuinMale's body part has `MaterialVariant = "Roblox Grid"`**,
QuinFemale's has none. The variant's own pattern darkens the color.

Fix: `FXService.applyElementAppearance` clears `MaterialVariant` on the body it paints (as it
already clears the skin texture). Checked in play: 16 males and 16 females, variant empty on all.
The QuinMale template itself is unchanged.

## Standing at the edge

Measured first (generated arena, 16v16): Quins standing still within 3 studs of a 6+ stud drop.

- 99 of 135 edge samples were standing still, the longest unbroken 13.2 s.
- 60 of those were **Overwatch**, "Holding high ground (look)": its lookout spot is
  `Overwatch_EdgeInset` (3) from the rim and it stops within 2.5 of the spot, so it stood on the
  rim itself. The rest were short (Recovery, Chase at a ledge).
- Idle at an edge: none.

Changes:

- `Overwatch_EdgeInset` 3 -> 5: a lookout stands clear of the rim.
- New `Modules/EdgeAwareness`: `sense` answers "is there a drop within reach of my feet, and
  which way is in" (eight probes round the feet; never asked on the arena floor). `Main`
  publishes it as the `NearEdge` attribute, and walks the Quin in from the rim when it has
  nothing to do there: in Idle anywhere, and anywhere on the arena wall's top unless it is
  fighting. A Quin that fights, chases or holds high ground at an edge is left to.
  Settings in `CombatConfig.EdgeAwareness` (Reach 3, MinDrop 6, StepIn 6, StepSpeed 10).
- The mind panel has a line for it.

After (another generated arena, 55 s):

| | Before | After |
|---|---|---|
| longest unbroken stand at an edge | 13.2 s | 1.2 s |
| Overwatch standing still at an edge | 60 samples | 3 (of 856 Overwatch samples) |
| `NearEdge` published | - | 165 samples |
| "stepping in" rule fired | - | **0** |

So the visible change comes from the lookout inset. The step-in rule did not fire once: no Quin
idled at an edge and none was on the arena wall in the sample. It is unproven in play.

Not done: what a Quin does about an edge while fighting or circling next to it (it knows now,
through `NearEdge`, but nothing uses that yet).
