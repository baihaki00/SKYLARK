# 16v16 pass 12: landing slide, mid-air clash outcomes, sky awareness, intercepts, platform overwatch

Backup: `ServerStorage.backup_pre_16v16audit12_20261001`. Base: pass 11 (`43680a5`).

## Requests (owner, after pass 11)

1. Keep the 5-25 stud landing scatter, but add a little physics on landing: a slide based on the arrival angle and a little X/Z tilt, down to a full stop.
2. Use the platforms: walk the edge and look down for opponents, regroup on high platforms, scan the sky for Quins high in the air (from platforms and from the ground) and intercept them.
3. Interceptions lead to a mid-air clash that ends one of three ways: a brawl and a tie, a brawl and one loses, or an immediate smash-down with no brawl. The winner then free-falls.

## What changed

### Landing slide and tilt (ProjectileJumpState, RecoveryState, AirborneState, ProceduralCombatReactionController)
- The flight guard records the arrival velocity every frame (except the last set-down frames).
- On touchdown, the horizontal part of that velocity becomes a slide: `0.03` studs per stud/s, at most 14 studs (2 when landing on a chosen platform spot), easing to a stop over 0.5 s. A steep dive stops where it lands and a shallow arc skids.
- During the slide the whole body leans back against the skid (up to 22 degrees at 40 studs/s) and rights itself as the slide runs out.
- Config: `CombatConfig.ProjectileJump_Landing*`.

### Mid-air clash outcomes (MidAirClashState)
- The leader decides the result and writes it on both Quins (`ClashResult`). Before this, the follower read it from a leader that had already left and cleared it, so the follower played a tie while the leader played a smash.
- Immediate smash: 30% of clashes have no brawl. The Quin that came in faster smashes the other down. If the target was not flying under its own power (thrown up by a hit, or falling), it is smashed down 75% of the time.
- The loser is driven down at 260 studs/s (`ForceLimitMode = PerAxis`, as in pass 11) and takes the 20 damage. Before this, the damage went to the winner.
- The winner hovers for 0.45 s, then drops PlatformStand and free-falls through AirborneState.
- A Quin already clashing cannot be pulled into a second clash, and neither can one standing on something. Both cases used to create three-way clashes in which both sides "won".
- AirborneState waits 3 s after a clash before starting another one with either Quin (`MidAirClash_Cooldown`). The two-jumpers-meet check in ProjectileJumpState does not use this cooldown.

### Looking up and down (Cognition.Gaze, Senses, LookController)
- New `Cognition/Gaze`: each Quin has an eye pitch. The eyes follow the current target up or down (up to 75 degrees). From high ground (12+ studs above the floor) they look down over the edge. Now and then the Quin glances at the sky (45 degrees); more aware Quins glance more often (every 2.5-7 s).
- Senses now has a vertical field of view (±35 degrees around the eye pitch). A Quin only sees a jumper high above it if it was looking up. LookController turns the head with the gaze.

### Sky intercept (Modules/AirInterceptModule, ProjectileJumpState style 8)
- A Quin that sees an enemy 40+ studs above it, off the ground, within 300 studs, not already claimed by another interceptor, not clashing and not diving may go up after it. The chance is 3% + 15% × aggression, rolled once per sighting every 3 s.
- Style 8 is a straight rocket line at 480 studs/s, steered every frame with a short lead. The first version used a ballistic arc and was too slow to catch anything. Contact (15 studs) starts a mid-air clash. If the target lands, gets away, drops below the interceptor or 2.5 s pass, the jump turns into a normal style-2 dive.
- Considered from Chase and Overwatch (not from Retreat).

### Overwatch (States/OverwatchState, RetreatTacticsModule)
- A Quin on a platform 12+ studs above the floor with nobody near walks the edge on its enemies' side, stops and looks down, and recovers.
- It leaves when:
  - an enemy comes up to its level within 30 studs: it fights there;
  - it spots a jumper: it intercepts;
  - it has watched for 4-12 s (shorter for aggressive Quins) and sees someone below: it dives on them;
  - 25 s have passed: it comes down.
- Rendezvous: retreating Quins value a platform 15 more per ally already on it (up to 3 allies), so wounded Quins gather on the same platform.

## Measurements (16v16, one run, about 3 min, 0 script errors)

First 89 s:

| | |
|---|---|
| Intercept launches (style 8) | 12 |
| Mid-air clashes | 26 (all sources) |
| Clash results | 14 one-side win (brawl or immediate smash), 3 ties |
| Overwatch entries | 8 (2.4% of Quin time) |
| Quin-seconds standing on a platform 13+ studs up | 107 |
| State share | Fight 41.6%, Chase 24.4%, Circling 12.8%, Recovery 6.5%, PJ 4.1%, Knockback 3.9%, Overwatch 2.4%, MidAirClash 1.8%, Retreat 0.7% |

Intercept trace (next 90 s, every style-8 flight recorded frame by frame):

| start gap | height above | target | closest | result |
|---|---|---|---|---|
| 61 | 47 | rising jumper (173 up) | 26.5 at 0.32 s | clash |
| 77 | 45 | rising jumper | 28.5 at 0.31 s | clash |
| 62 | 59 | airborne Quin | 14.7 at 0.19 s | clash |
| 52 | 46 | rising jumper | 33.9 at 0.20 s | clash |
| 66 | 64 | knocked-up Quin | 12.1 at 0.25 s | clash |
| 235 | 180 | jumper at apex | never closed | Recovery after 0.43 s |

- 5 of 6 intercepts became clashes within 0.2-0.35 s. Four started at 26-34 studs through the general "two jumpers within 40 studs" check, before the intercept's own 15-stud contact check, so `InterceptHits` (1 in the first window) undercounts. Count clashes, not `InterceptHits`.
- The 235-stud flight never closed the gap and ended in Recovery after 0.43 s. From one sample I could not tell why (no arena clamp on height, flight speed was 480). It is open below.

## Open
- The long-range (200+ studs) intercept miss above. If it repeats, `Intercept_MaxRange` (300) could drop to about 150.
- The clash counter does not say which clashes came from an intercept and which from two jumpers meeting.
- Overwatch, the gaze glances and the landing tilt are verified by counters and earlier forced tests only. Screen capture cannot show the head pitch reliably.
- Not done from earlier passes: IK foot placement, rerouting when a jump is rejected.
