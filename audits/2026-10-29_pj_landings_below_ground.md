# Projectile-jump landings: bodies drawn under the ground (owner's bookmarks 3 and 9)

2026-10-29, Studio (QUIN_COMBATV4), 16v16 TeamBattle. Measured only: the two client-side tries were reverted, and nothing has changed in the game.

## Measured

**Client side (what the owner sees).** Each projectile-jump landing, from 0.2 s before the jump ends to 0.6 s after:
- The ground is the first hit straight down from the hips. Depth is that ground's height minus the lowest foot or toe.
- About 99 landings in 80 s.
- **The feet were more than 0.5 studs under the ground in 58 of them.** p90 depth was 5.3-5.4 studs; the worst was 7.4.
- It happens both on the main floor and on raised tops (boxes, platforms, stones).

**Where the drawn body was, on the deep frames:**
- **Case A, the root itself under the surface:** −0.6 to −1.5 studs, in ProjectileJump with PlatformStand on, for 10-16 frames.
- **Case B, the root at standing height but the hips drawn about 8 studs below it:** also in ProjectileJump with PlatformStand on. Not explained yet.
- After the jump, in Recovery: a LandingHard or get-up clip with the feet about 2.5 studs under the ground while the root is at standing height.

**Server side.** 667 ProjectileJump frames in 40 s; in 65 of them the root was within 0.5 studs of a surface or under it:
- All of them had `PlatformStand` on and the root's `CanCollide` off.
- **"Arcing" frames with the root inside a Part, moving upward:** the body flies through boxes and platforms.
- **"Arcing" frames at vertical speed 0 with the root right at a part's surface (−0.05):** the body rests on its torso collision, and the legs are inside the part.
- **"Impact" frames:** the root 2-3 studs under the ground.

## Cause

In `States/ProjectileJumpState`, the jump runs in PlatformStand with the root's collision off, so nothing holds the root at standing height. The body stops on its torso collision parts: the root sits at the surface and the legs are drawn in the floor.

What sets the body down at standing height:
- **The set-down snap:** only for a fall faster than 20 studs/s, and only for dives.
- **The Impact placing:** `finalY` from `standGap`.

Two paths get neither:
- **Climbs** (`climbing()`: landings kept physical, no snap, by the owner's call on 2026-10-28) and slow arrivals sit sunk until the jump ends.
- **Impact while the body is already in the floor:** `standGap` is measured from a body that is already under the surface.

## Tried and reverted (client, `AIGhostHandler`)

| Try | Switch | Result |
|---|---|---|
| Launch-lead floor clamp: the drawn root never below standing height | `LaunchLeadFloorOff` | no change: p90 depth 5.2-5.5 either way |
| Smoother on after a projectile jump that lands higher than it took off | `PJPlatformSmoothOff` | no change: raised landings showed 0-1 snaps either way |

Both were taken out. AIGhostHandler is back to the backed-up copy (29,870 bytes).

## Proposed fix (needs the owner's go-ahead: it touches the dive, which the owner wanted kept as it was)

In `ProjectileJumpState`, with a switch:

1. Wherever the body comes to rest on a surface (touchdown, a climb's physical landing, Impact), lift the root to standing height physically. That means a short upward velocity or a stand-height hold, not a CFrame write, so the client sees no snap.
2. Measure Impact's ground from above the body, not from the sunk root.
3. Optional: end the climbing PlatformStand as soon as the body is on a top, so the Humanoid holds it up.

Then re-run the same client probe. Target: feet under the ground in under 10% of landings.

Case B (hips drawn about 8 studs below a normal root) needs its own look after this.

## Fix built (2026-10-29, the owner said "Yes, fix the jump")

**First try, the server stand lift: built, measured, taken out.**
- In `ProjectileJumpState`, a body under standing height was pushed up through its mover (switch `PJStandLiftOff`), and Impact measured its ground from above.
- It fired on only 4 frames in 50 s, and the client A/B showed no difference.
- A server probe (25 s, every ProjectileJump frame plus 0.6 s after) found the root under standing height in about 1% of frames. **The server body is not where the problem is.**
- ProjectileJumpState is back as it was (53,765 characters).

**The real cause: the landing clip.**
- A client probe of the deep frames found the root at standing height (rootRel ≈ 0), but the hips drawn 4-5 studs under the root. A normal stance is −1.3.
- By clip, the deep frames were almost all **NinjaLanding** (`92021932752253`, NINJA CONFIDENT LANDING), the clip played on landing from the jump:

| NinjaLanding, quarter of the clip | Hips under the root (normal −1.3) | Frames with feet under the floor |
|---|---|---|
| 1st | −4.93 | 86% (avg 2.4 studs) |
| 2nd | −3.63 | 100% (avg 1.3) |
| 3rd and 4th | −1.3 | 0% |

- Its crouch goes deeper than the body stands. The get-up clips (GetUpBackFastNinja, GetUpFrontFast) lower their hips as much, but they fold the legs and stay above the floor.

**The fix: a `floorFeet` clip correction** (client, `ProceduralCombatReactionController.applyFloorFeet`).
- While a clip marked `floorFeet` in `CombatConfig.ClipCorrections` is the main clip, the hips are raised until the lowest foot or toe is on the floor (at most 4 studs).
- Only NinjaLanding is marked.
- Switch: Workspace `ClipFloorFeetOff = true`.

**A/B in one 16v16** (switch toggled every 10 s, 100 s, client):

| | Off | On |
|---|---|---|
| NinjaLanding frames with feet under the floor | 103 / 263 (**39%**) | 0 / 199 (**0%**) |
| Jump landings with any frame over 0.5 studs deep (0.2 s before to 0.6 s after) | 32% | 42% |
| p90 depth of those landings | 2.53 | **1.37** |
| Sudden drawn jumps after landings | 23 | 12 |

No script errors.

**What's left** is spread thin over other clips. Each is a handful of frames in 45 s, and one frame is enough to count a landing:
- Recovery with clip `110436967972328`: 8 of 347 frames, about 0.9 studs.
- Dash with DiveFly: the server root itself 6 studs under the ground (the dive going into the floor at speed; the dive is kept as it was).
- ComboWait with the PROJECTILE JUMP clip: root 2.5 under.
- Arcing with 180 RUN TURN LEFT: hips 4.9 under the root.
- **Case B** (Init with the Run clip, hips 8 under the root at take-off): still unexplained.

**Not checked:** how the raised crouch looks. That needs the owner's eye.
