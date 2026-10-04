# Pass 38 (2026-10-05): knee over toe, footfall weight, mind panel moved

Phase 2 (legs) of `PROCEDURAL_PORT_PLAN.md`, plus the owner's request to move the mind panel.

## Measured first (16v16, arena leg solver, before any change)

- **Thigh roll off the clip: 0.0 deg** on every solved leg. The arena solver swings the thigh by
  the shortest turn, so the roll lane D had to correct (an `IKControl` side effect) does not
  exist here. `ThighTwist` is not ported.
- **Knee inside the foot** by more than 5 deg on 36-60 % of grounded frames, 17-28 deg past the
  limit on average. This is in the clips (the lab's animation-only lane showed the same).

## Built

- **`Modules/Procedural/KneeOverToe`**: a knee more than 5 deg inside or 25 deg outside its foot
  is swung round the hip-ankle line (hip and ankle stay put) and the foot is turned back by the
  same amount. Full within 0.15 studs of the ground, fading to none at 0.6; capped at 35 deg;
  eased at 18/s. Runs after the leg solve, on solved and unsolved legs alike. The controller
  now records each foot's lift above its ground (`self.footLift`) for it.
- **Footfall** (in the controller, 8 lines): each foot that becomes planted adds a downward
  kick to the existing hips spring (1.2 studs/s at 8 studs/s of travel, scaled 0.4-1.6).
- Both are layers in `Procedural/Layers` (`Layer_KneeOverToe`, `Layer_Footfall`), with HUD rows.
  Config: `CombatConfig.ProceduralLayers`.
- **`QuinMindPanel`**: moved from the left middle to the bottom middle, wide and low (42 % of the
  screen width, 460-700 px, 150 high): details on the left, thoughts beside them. At 1618 px wide
  it spans x 509-1189; the Spectator HUD ends at 375.

## Measured after (16v16, split on, 45 s, feet within 0.15 studs of the ground by raycast)

Share of grounded frames with the knee more than 15 deg inside the foot:

| | Legacy half | Layered half |
|---|---|---|
| Standing | 28 % | 4 % |
| Walking | 18 % | 5 % |
| Running | 15 % | 8 % |

Mean excess past 5 deg: standing 18.8 -> 5.1, walking 15.8 -> 8.2, running 21.5 -> 17.0.
Knee jumps (over 80 studs/s relative to the root): 0.22-0.25 % of frames legacy, 0.21-0.35 %
layered: no clear change. No script errors.

## Not done / not shown

- **Running is only partly fixed** (15 % -> 8 %, and knees more than 25 deg outside the foot stay
  near 10 % in both halves). Some running frames are not reached by the layer; cause not found
  (candidates: feet the solver treats as free during dashes and slides, the 35 deg cap).
- **Footfall is not confirmed by measurement.** Expected dip is about 0.035 studs; hip height
  varies 0.3-0.5 studs from the clips alone, so it did not show.
- A first probe judged "planted" by the lowest foot height seen and gave misleading run numbers;
  the table above uses a raycast under each foot.
- Not looked at by eye. The mind panel was checked by its screen rectangle only.
- The permanent ablation probe is still open.
