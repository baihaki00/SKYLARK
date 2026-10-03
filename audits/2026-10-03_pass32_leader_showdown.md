# Pass 32 (Social layer, phase 3): emergent Leader Showdown

Plan phase 3 of 4. Place: QUIN_COMBAT_V3.

## What was built: `Modules/SocialShowdown`

It's a SocialSystem part. Tunables are in `CombatConfig.Social.Showdown`. Nobody is paired by a script.

**Recognition.** Two opposing pack leaders build up recognition while each sees the other: within 60 studs with a clear line of sight (`SpatialModule.checkLineOfSight`). Recognition decays when they lose sight. At 2 s they look at each other, and that pair decides once (45 s cooldown per pair, at most 1 showdown at a time).

**Outcomes** (weighted roll):

| Outcome | Weight | What happens |
|---|---|---|
| Engage | 0.3 + both leaders' credibility × 0.15 + the weaker one's health × 0.2 | Both acknowledge each other (look and nod). |
| Approach | 0.25 | The stronger one (credibility + health) walks over; the other turns to it and nods. |
| Refuse | 0.15 + the weaker one's injury × 0.4 | The weaker one jogs 15 studs away and avoids the other for 10 s; the other may still come for it. |
| Ignore | 0.2, +0.35 if either is swamped | Both carry on. |

**During a showdown** (up to 30 s):
- **The duellists hold each other** through TargetingModule's explicit `TargetOverride`, and `SocialDuel` records who they're fighting.
- **Interceptors** ("you want him? you go through me"): allies within 35 studs of their leader, with trust at least 0.45, step in 60% of the time. Each runs to a point between its leader and the challenger, targets the challenger (`TargetOverride` + `SocialFocus`) and looks at it.
- **Space-makers:** other Quins within 45 studs leave the opposing duellist alone (`SocialAvoid`, −80 targeting) and glance over now and then.
- The arena event rises to **LeaderShowdown**, which phase 4 will hand to the crowd, ARIA and the screen.
- **It ends** when a duellist falls (recorded as "X won"), at 30 s, or when they drift more than 120 studs apart for 5 s. Overrides, avoids and roles are cleared.

**SocialSystem change:** `addTargetTerm` lets each part add targeting terms (showdown: duel +150, avoid −80).

**Studio hook:** Workspace `ShowdownDevCommand = "start <a> <b>"`. **Telemetry:** Workspace `ShowdownStats`, and per Quin `ShowdownRole` (Duelist / Interceptor / Watcher).

## Problems found and fixed

1. **The duel didn't hold** (0 of 24 seconds on the opponent).
   - `TargetingModule.selectTarget` only scores the Quin's local `NearbyEnemies`, so a +150 term never reached an opponent outside that list.
   - **Fix:** the duel uses the existing explicit `TargetOverride` path (it was unused anywhere else).
   - **After the fix:** both duellists stayed on each other for 25 of 25 seconds. They closed from 56 studs and traded blows at 6–18. Excursions of 250–360 were knockback and projectile jumps, and each time they came back.
2. **Nobody intercepted.** Trust starts at 0.5, so a minimum of 0.55 excluded everyone early. Now 0.45, and the radius went from 25 to 35 studs.

## Measurements (16v16)

- **Natural recognitions:** 3 in 120 s (refuse 2, ignore 1), 2 in 150 s (engage 1, ignore 1), and 1 more in a later run (engage). So a showdown is an occasional event, not a constant one.
- **Natural engage:** duellists on their opponent 29 of 30 duellist-seconds; 5 space-makers; event level LeaderShowdown.
- **Later natural engage:** 2 interceptors, each committed to the opposing leader (one chasing it, one targeting it while getting up). 7 space-makers.
- **Combat** during these runs: hit 64–68%, whiff 6%, 0 errors.

Next: phase 4, Respect Custom → final fight → Honorable Comeback → Big Clutch, plus the escalation tracker (crowd, ARIA, screen).
