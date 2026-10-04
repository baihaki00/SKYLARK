# Pass 49 (2026-10-05): the arena wall and the outside are playable, at a price (item 13)

Owner: the wall is part of the game (wall run, walk, run, fight on it) but being off the arena
floor is a penalty: a performance score deduction and a forced return after N seconds. A Quin
may be knocked out of the arena; it is brought back after N seconds or comes back itself; the
Quin that knocked it out gets a score deduction. The check must be dynamic because the wall
overlaps the floor.

## The arena as it is

Floor 600 x 600, top at y 2. Four walls 148 studs tall (top at y 144), 47-70 thick, whose inner
faces overlap the floor's footprint by up to 4 studs. A baseplate lies outside at y 0.

## Before

Anything within 5 studs of the floor's edge counted as out of bounds; after 1 s there the Quin
was forced into ReEntry (the cinematic leap back). Wall runs were exempt.

## Now: `Modules/ArenaTrespass`, called from `Main` every AI tick

- **Where a Quin is** comes from the surface under it: a ray straight down. On (or over) a part
  named `ArenaWall` -> "Wall". Otherwise inside the floor's footprint -> "Ground". Otherwise
  "Outside". The floor right beside a wall is Ground; the wall's top above the same X/Z is Wall.
- **Cost:** after 1 s off the floor (`Grace`), 0.2 points per second (`PenaltyPerSecond`) are
  added to the Quin's `MatchPenalty` attribute.
- **Forced back:** after 8 s on the wall (`MaxTimeOnWall`) or 4 s outside (`MaxTimeOutside`),
  `Main` forces ReEntry. Not while it wall-runs or is still being thrown. Back on the floor the
  clock is cleared.
- **Thrown out:** a Quin that leaves the floor within 3 s of being in Knockback was thrown out:
  its last attacker loses 1 point once (`KnockoutPenalty`), gets `KnockedOutOfArena` +1, and the
  thrown Quin carries `ThrownOutBy`.
- **The score.** No single "performance score" exists in the code; the two that rank Quins are
  `SocialLeaders.standing` (who leads) and `SocialRespect.contribution` (who earns a respect
  duel). `MatchPenalty` is subtracted from both.
- **The void** is unchanged: more than 80 studs beyond the floor or below y -5 is an immediate
  teleport to the centre.
- Attributes for the HUD / mind panel: `Trespass` ("Wall" / "Outside"), `TrespassTime`,
  `MatchPenalty`. Config: `CombatConfig.Trespass`.

## Staged test (16v16, three Quins moved by hand)

| Quin | What was done | Result |
|---|---|---|
| A | put on top of the east wall | "Wall"; came down by itself after 5.8 s; penalty 0.70 |
| B | put in Knockback with C as last attacker, then on the wall 0.5 s later | "Wall"; forced ReEntry at 8.5 s; penalty 1.50; C charged 1.00, `KnockedOutOfArena` 1 |
| D | put outside at x = 420 (120 beyond the floor) | "Outside" for 0.2 s, then the void net teleported it (it was past the 80-stud band) |
| the other 28 | fighting on the floor | none flagged, none penalised |

No script errors.

## Not done / not shown

- **Nothing in the AI chooses the wall.** A Quin gets up there only by a projectile jump or by
  being launched. Wall run reach (item 20), awareness of the wall's rim (11) and the lag after
  touching a wall (12) are not touched yet.
- A Quin on the wall is not told to come back before the limit; A did because its target was
  below and Chase dives off high ground.
- The 4 s outside limit was not seen: the only outside test was beyond the void band.
- The penalty figures are first guesses; the owner has not set N or the points.
- Tested by moving Quins by hand, not by play.
