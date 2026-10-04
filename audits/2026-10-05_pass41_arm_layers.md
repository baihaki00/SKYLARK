# Pass 41 (2026-10-05): arm layers (phase 3 of the lane D port)

## Measured first (16v16, final pose, 45 s)

| | Elbow within 0.95 of the trunk line | Wrist within 0.95 | Either within 0.6 | Elbow straighter than 10 deg |
|---|---|---|---|---|
| Run / chase | 3.8 % (clip alone 2.6 %) | 3.3 % (1.0 %) | 0.0 % | 5.7 % (4.5 %) |
| Circling | 3.7 % (2.9 %) | 1.5 % (0.8 %) | 0.0 % | 4.8 % (4.3 %) |
| Fight, between strikes | 5.0 % | 1.4 % (0.5 %) | 0.1 % | 1.9 % |
| Fight, striking | 2.9 % | 2.8 % | 0.4 % | 0.4 % |

So in the arena arms are almost never deep inside the body (that was the lab's arm IK), but the
existing layers bring a wrist inside the clips' own clearance about three times as often as the
clip alone, and the run and strafe clips lock the elbow straight on about 5 % of frames.

## Built

- **`Procedural/SoftElbows`**: an elbow straighter than 10 deg is bent to 10 about its hinge. The
  hinge is the elbow's axis in the upper arm's frame, learned from the clips whenever the elbow
  is bent past 25 deg (the axis square to both halves of the arm).
- **`Procedural/ArmClear`**: an elbow, then a wrist, inside 0.95 studs of the trunk's line
  (1.2 under the hips to the chest) is turned back out to it; the wrist comes out on the elbow's
  side, two passes.
- **Loose wrists**: two entries in the existing follow-through chain (`SecondaryMotion`): the
  hand's tip follows its clip position on the arm spring, capped at 15 deg.
- All three are layers with HUD rows (`Layer_SoftElbows`, `Layer_ArmClear`, `Layer_LooseWrists`).
- Soft elbows and arm clearance fade out (20/s) while the Quin is striking, guarding, thrown,
  getting up or in a special, and back in at 6/s: a punch still lands on a straight arm.

## A mistake on the way

The first version took the elbow's bend axis from the bind pose, as the lab does ("the axis that
brings the hand forward from arms-out-to-the-sides"). The arena rigs' rest pose is not
arms-out, the wrong axis was picked, and straight elbows went from 4.6 % to 5.2 %. Found by the
split measurement; replaced by the learned hinge.

## Measured after (split on, 45 s, limits tested a little inside the layer's own: 0.9 and 9.5)

| Not striking or guarding | Legacy half | Layered half |
|---|---|---|
| Elbow inside 0.9 of the trunk line | 2.2 % | 0.4 % |
| Wrist inside 0.9 | 1.3 % | 0.2 % |
| Elbow straighter than 9.5 deg | 4.1 % | 0.5 % |
| Elbow bend changing over 900 deg/s | 2.58 % | 2.18 % |
| Hand over 90 studs/s relative to the body | 0.16 % | 0.08 % |

Striking or guarding: 0.4 % straight (legacy) against 0.3 %, clearance the same in both halves:
strikes are left as authored. Strikes in the same match: hit 69 %, whiff 5 %, blocked 5 %,
interrupted 21 % (482 strikes). No script errors.

## Not shown

- Loose wrists were not measured on their own (no added hand or elbow pops in the layered half
  is all the table says). To be judged by eye with the switch.
- Not looked at by eye. Male and female were not split in the table.
