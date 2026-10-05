# Pass 61: The tackled Quin hangs in the air; a strafe plays on the wall

The owner: "a slight delay and 'stuck in mid air' during a quin being tackled, its the ground
check sitting under the head of the quin whos tackling or the baked animation original Y axis";
"wall run, make sure it only plays run animation and not strafe".

## Tackle: three causes, one of them the real hang

Measured on the server and on the client (the client is what is seen).

1. **The hang (client only).** The server's body came down smoothly. On the client the root sat
   at 9.2 studs above the floor from 0.51 to 0.68 s (about 0.17 s), then caught up. Cause: the
   sweep's flip wrote the root's CFrame every frame. A CFrame written each frame reaches clients
   outside the physics stream; when the writes stopped (the flip done), the client held the body
   where it was until the stream caught up.
   **Fix:** the flip is turned by a rigid `AlignOrientation` (`SweepFlip`) whose target is
   stepped every frame. Position is left to physics. After: 12.4, 12.3, 11.8, 11.0, 9.9, 8.4,
   6.4, 4.8 at 0.04 s steps, no plateau; the flip still turns right over (179 degrees at the top).
2. **The delay.** The server's Knockback state noticed the touchdown on its next 0.1 s tick:
   0.02 - 0.10 s on the ground still in the airborne pose. **Fix:** a state may ask for a
   shorter tick (`tickInterval`, read by `Main`); `KnockbackState.tickInterval = 0.03`. Measured
   wait between root down and Recovery: 0.00 s in 3 of 3.
3. **The ground check (the owner's guess).** `SpatialModule.isGrounded` excluded only the Quin
   itself: the slider's `CollisionBody` under the victim was hit by it while airborne (seen in
   1 of 2 trials; it did not end the fall early in those, the "descending" condition held it).
   **Fix:** only solid ground counts: other Quins are excluded and `RespectCanCollide` is set.

Also changed, for the "baked Y" part: **`settle`** on `FallFront` / `FallBack`
(`ClipCorrections`). A fall pose is flown at hip height; over the last
`ClipCorrections_SettleHeight` (6) studs of the fall it is let down so the body is on the floor
at touchdown, where the get-up starts. Not when the Quin will land on its feet (front, not
knocked flat: the same rule as RecoveryState). The correction is now never larger than the
body's real room above the floor, so it cannot push a bone under it while it eases out.
**Not confirmed by measurement:** the samples after the change were mostly landings on the feet.

Left as it is: on a client the landing clip starts about 0.1 s before the body is seen to
arrive (state and animation replicate ahead of the interpolated position).

## Wall run: only the run

Reproduced: with a strafe clip on the body when the wall run starts, 0.7 s into the run both
`STRAFE` (weight 1.0) and `Run` (1.0) were playing at Movement priority. Nothing updates the
gait during a wall run (it is excluded from the automatic drive), so whatever the last state
left stayed at full weight.

**Fix:** `WallRunState.enter` stops the gait and every looped Movement-priority clip before it
starts the run. Same test after: `Run` 1.0 only, 3 of 3.

## Not checked

- By eye (owner).
- `isGrounded` is used in 45 places; the change only removes Quins and non-solid parts from what
  counts as ground. A 16v16 was not re-run after it.
- The shorter Knockback tick runs the Quin's whole think-step three times as often while it is
  being thrown (about half a second each time); frame rate in a 16v16 not measured.
