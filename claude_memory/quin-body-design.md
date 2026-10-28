---
name: quin-body-design
description: "The real Quin body template (started 2026-10-12): mannequin/marionette look, ball-BEARING joints (not ball joints), 3 colour zones, team wristbands, accessories pipeline; files in D:\\SKYLARK\\QUIN_DESIGN"
metadata:
  node_type: memory
  type: project
  originSessionId: 3855b131-0e43-4a7a-aa69-6de4596d5e71
  modified: 2026-10-12T02:06:12.248Z
---

On 2026-10-12 the owner started designing the actual Quin.

**Owner's direction**
- Look: a sleek marionette / mannequin, NOT super futuristic. References: a mannequin turnaround sheet, a linen-and-wood dress form, a jointed doll.
- Joints: ball **bearings** (the owner rejected ball joints). Built as race | ring of balls | race over a dark core, flush in the gap between plates.
- Customisable: plate colour and material, accessories head to toe, working for both male and female.
- Team identity: bodies are no longer painted blue/red. Every Quin wears blue or red **wristbands**; Pack Leaders get a slightly different colour.
- Future: a "Create Your Quin" window (body, material, accessories), not yet.
- The plan's phases: 1 bodies, 2 import beside the old ones, 3 appearance system and wristbands, 4 accessory pipeline, 5 Create Your Quin.

**Facts**
- `QUIN_DESIGN\reference\ybot.fbx` = the MALE segmented bot (Alpha_Surface + Alpha_Joints).
- `xbot.fbx` = the curvy FEMALE bot (Beta_Surface + Beta_Joints, ball joints, posed in the file).
- The owner's ybot.blend and xbot.blend are edited copies (meshes merged, decimated); use the FBXs.
- Both bots use the Mixamo skeleton, so the animations fit.
- Current game: one skinned `Alpha_Surface` per Quin, painted by `FXService.applyElementAppearance` (TeamColors). `QuinAccessoryModule` has 5 procedural items on bones.

**Done (male v0)**
- `scripts/build_quin.py` (headless Blender) produces the three zones `Quin_Shell` / `Quin_Bearings` / `Quin_Core`:
  - egg head;
  - the bot's joint bands turned into bone-aligned bearings that follow the band's cross-section;
  - small finger bands kept as core.
- Each mesh is under 18.5k tris (the Roblox limit is 20k).
- Render scripts: `turnaround.py`, `closeup.py`, `presets.py`. Renders go to `renders/male_v0*`.
- Sent to the owner for review: **REJECTED** (2026-10-12, "goofy", "why egg looking head"). The owner will model the body themselves.
- Don't generate body art procedurally again unasked. Offer the pipeline side instead: Studio import and skinning test, colour zones as separate skinned meshes, wristbands, accessory attachment points, export.

**Open owner questions:** proportions (keep the bots', or go taller and slimmer); one or two wristbands; material wishes.

Related: [[cascadeur-to-quin-converter]], [[social-layer]]

**2026-10-12, faces and eyes (agreed direction; the owner is modelling for a couple of days):**
- The base head stays faceless and smooth in front.
- Faces are a sellable add-on (Robux), as a face plate on a `Face` attachment on the Head bone. Expressions are texture swaps driven by game state.
- Premium "Living Eyes": eyeballs (plus optional eyelids) inside the plate's sockets, turned client-side to look at the target (Cognition gaze), with darts, blinks, and emotion (wide, narrowed, half-lidded, KO).
- The owner makes: the body (Blender, on the bot skeleton: one rigid piece per bone, joints at bone heads, a mesh per zone, under 20k tris each, no leaf bones), the face plate, the eyeball and the eyelids.
- Claude does the Roblox side when the files arrive in `QUIN_DESIGN\export\`.

**2026-10-21:** the owner finished a rough first prototype of the male body themselves (day ~10 of learning Blender): wood plates shrinkwrapped over a guide mesh, bronze joints, T-pose. Next: fit the ybot skeleton and skin it, split into zones (P → By Material), export to `QUIN_DESIGN\export\`, then Claude imports it into Studio.

**2026-10-21, the owner's body rigged (workflow trial):**
- The owner's files are in `D:\SKYLARK\QUINBASEMESH\`; the skeleton is `Male\ybot.fbx` (= the Studio Quin rig, hips 99.8 cm).
- Mirror editing needs .L/.R names: `scripts\bones_to_LR.py` / `bones_back_to_mixamo.py`. They rename in **Edit Mode**, because plain renames silently fail when a file was saved in Edit Mode. The round trip is verified identical (65 names).
- `scripts\rig_it.py` (restore names, apply modifiers, join wood → `Quin_Shell`, `basemesh` → `Quin_Joints`, automatic weights, limit 4, normalise) plus `slim_and_test.py` (decimate the shell 62k → 18k tris, then play Standard Run.fbx and render).
- Output: `BASE2_rigged.blend`. It runs cleanly.
- TRAP: the owner's Subdivision + Solidify plates convert to 62k tris. Keep Subsurf at 0–1 or decimate.
- Next: UVs, then export, then Claude imports into Studio beside the old Quin, behind a switch.

**2026-10-21, rig v2: `scriptsuild_rig.py` (one click: modelling file + fitted file → rigged file).**
- What it does:
  - Subdivision off (plates about 18.6k tris with no decimation);
  - modifiers applied;
  - the model mapped onto the skeleton through the body's bounding box;
  - the fitted Armature appended, with Mixamo names restored;
  - zones made, smooth shading by angle at 35°;
  - `Quin_Joints` gets Automatic Weights; `Quin_Shell` copies its weights from the body (Data Transfer, nearest face);
  - each plate drops bones under 12% of its weight, then limit 4 and normalise.
- Output: `BASE2_rigged_v2.blend`. The first `BASE2_rigged.blend` is superseded.
- TRAPS:
  - decimating thin Solidify plates tore them;
  - Automatic Weights on double-walled plates split the walls;
  - the torso plate's sides took weight from the upper arm.
- Left over: a small fold on the torso's side, where one plate spans the whole spine. Advise splitting it into chest + abdomen plates, or weight painting.

**2026-10-21, `BASE2_rigged_full_fixed.blend`** (`scripts\fix_weights.py`, `find_stretch.py`, `find_spike.py`).
- Cause of the spike: the owner's weight painting (saved 20:55) put `RightToe_End` (a tip bone) on the neck, at 0.7–0.8.
- The fix:
  - empty every tip bone (`*_End`, finger 4s);
  - normalise, smooth 4 passes in Weight Paint mode (the smooth operator needs that mode);
  - limit 4 bones per vertex;
  - the head plate rigid on Head.
- `find_stretch.py` ranks pieces by edge stretch through the run, and `find_spike.py` lists the bad vertices with their weights. Use them to diagnose rig glitches.

**2026-10-21, one mesh: `BASE2_rigged_body.blend`** (`scripts\join_body.py`; the owner's pre-join file is backed up as `BASE2_rigged_full_fixed_BACKUP.blend`).
- The owner wanted a single mesh to paint as a whole.
- How it was made:
  - the body gets Automatic Weights; the plates copy from the body (with the per-plate 12% rule, head rigid);
  - then joined into `Quin_Body` (materials BRONZE + WARM IVORY LACQUER kept, for splitting into zones at export);
  - tip bones emptied, smoothed, limit 4.
- Removed a leftover `Armature.001` (the imported run skeleton).
- The run test is clean. NOTE: this re-weighted from scratch, so any weight painting the owner did in the fixed file was replaced (their geometry edits are kept).

**2026-10-21, export.**
- The owner reduced `Quin_Body` to 20.7k tris themselves; the run test is clean.
- `scripts\export_quin.py` (rest pose, split by material, regions split if over 20k, FBX with no leaf bones and no animation) wrote `QUIN_DESIGN\export\QuinMale_v2.fbx`:
  - Quin_Shell 15.7k tris, Quin_Joints 5.0k;
  - 65 Mixamo bones, hips 0.998 m;
  - verified by re-import.
- (`QuinMale_v1.fbx` = the unreduced version split into 4 wood regions.)
- Next: the owner imports it into Studio (Custom rig, Imported Rig; about 8 studs tall, or Stud ×0.044 if giant). Then Claude compares its bones with the current QuinMale and wires it in behind a switch. The Studio MCP was disconnected at the time.

**2026-10-21, Studio check of the v2 import (`Workspace.QuinMale_v2`).**
- The import is about 7.93 studs tall: correct scale with the default settings.
- Structure: RootPart (holding the bones), Quin_Shell, Quin_Joints, AnimationController, and an InitialPoses folder.
- Compared with `QUINTESTMALE`:
  - head-to-toe height identical;
  - 4 bones missing (Thumb3 and Pinky3 had no weight: Roblox drops unweighted bones);
  - the collarbones rested 32° off (the owner moved their start while fitting);
  - the hips and knees sit 0.35–0.58 studs off (fitting).
- Clip test (the poses applied to both rigs): the run is within 1.4°; kicks and the wheel drive up to 16° off in the arms.
- Fix in `scripts\fix_shoulders_fingers.py` + `thumb_tips.py`:
  - the collarbones keep the ybot's direction, length and roll, ending at the fitted arm joint;
  - the tip bones take weight.
- Output: `BASE2_rigged_body_v3.blend` → `QuinMale_v3.fbx` (52 weighted bones, the same as the old rig).
- Next: the owner re-imports v3; Claude re-runs the clip comparison, then builds a QuinMale_New template behind a CombatConfig switch.

**2026-10-21, in the game: template `ReplicatedStorage.QuinType.QuinMale_New`** (built in Studio from `Workspace.QuinMale_v3`).
- How it was built:
  - a clone of QuinMale (HRP, Humanoid, Sounds, RootJoint kept);
  - the old Alpha_Surface (with its bones) replaced by the owner's wood shell, renamed `Alpha_Surface` and holding the skeleton (moved out of the importer's RootPart, world rest kept);
  - plus `Quin_Joints`, welded to it;
  - the body moved so the new Hips land exactly on the old Hips (feet 5.238 below the root, the same); RootJoint.C1 recomputed;
  - attributes KeepBodyColors=true, BodyVersion=QuinMale_v3, Zone=Shell/Joints;
  - colours ivory E8D3B5 SmoothPlastic and bronze 8A5A2E Metal.
- Code (commit after a1… "Owner's own male Quin body"):
  - `CombatConfig.Body_UseNewMale` (false);
  - QuinSpawner picks QuinMale_New when it is on;
  - FXService skips the team body paint when KeepBodyColors is set.
- Tested in Play: a male spawned on the new body, chased, and played walk/jog/idle; HipHeight 4.07, the same as before.
- Open:
  - team identity on the new body (the wristbands, the owner's plan);
  - the arms differ up to 12° on kicks (fitting);
  - the 16v16 is not measured with the switch on.

**2026-10-21, LIVE: the owner's body IS `QuinType.QuinMale`** (commit d847a89).
- Built by `QUINCORE_BACKUP/scripts/build_quin_template.lua`. Run it in Studio Edit via loadstring from HTTP 58918, prefixed with `local IMPORT, TEMPLATE = "<WorkspaceModel>", "QuinMale"`.
- It backs the old template up to `ServerStorage.QuinBodyBackups.<TEMPLATE>_<date>`; the old Mixamo male is `QuinMale_20261021_143006`.
- The Body_UseNewMale switch and QuinMale_New were removed. FXService still honours KeepBodyColors.
- The full pipeline and its rules are in `tools/quin_body_pipeline/README.md`. The owner's one-click export is `D:\SKYLARK\QUINBASEMESH\export_quin.bat` (drag a rigged .blend onto it).
- 16v16 probe with the new male: 16.7 strikes per Quin-minute, 69 % hit, 6.2 % whiff (Pass 79 baseline: 16.1 / 67 / 6.6).
- Open: team identity (wristbands); the female body (same pipeline, X Bot skeleton).

**2026-10-22, v4 (neck).**
- The owner saw a constant shrug at the neck in game.
- Cause: collarbone weight on the neck area (lopsided, left about 10x right, from painting). Most idle and fight clips lift the collarbones, which dragged the neck's base up.
- `scripts\fix_neck.py`: within 7 cm (x), 8 cm (z), 9 cm (y) of the neck joint, the Shoulder/Arm/Hand weights are removed, then normalised.
- `BASE2_rigged_body_v4.blend` → `QuinMale_v4.fbx` → the template (backup `QuinMale_20261022_045350` = v3). The owner asked to touch ONLY the neck.

**2026-10-22, female v1 and versioning.**
- The owner reshaped the male v4 rig into `BASE2_rigged_body_v4 - Female.blend`: same ybot skeleton, weights intact, already split into wood/bronze meshes.
- Exported as `QUIN_DESIGN\export\Female\QuinFemale_v1.fbx` (65 bones, all weighted that matter).
- Versioning:
  - `export_quin.bat` → `scripts\export_versioned.py` writes `export\<Gender>\Quin<Gender>_vN.fbx` (gender from "female" in the .blend name; N = next) and appends `versions.txt`;
  - male v1–v4 moved into `export\Male\`.
  - TRAP: the subprocess must decode utf-8 (the blenderkit log has emoji).
- Next: the owner imports QuinFemale_v1; Claude runs build_quin_template with TEMPLATE=QuinFemale (it aligns the hips to the old X Bot female; HipHeight comes from the bones at spawn).

**2026-10-22, female v1 LIVE as `QuinType.QuinFemale`** (backup `QuinFemale_20261022_102529` = the old X Bot female). Her soles sit 5.05 below the root (was 5.39: ybot legs); HipHeight from bones; the toe stands 0.14 above the floor (correct).
- TRAP, "shell missing in game": in Play the client gets AssetFetchStatus.Failure for freshly uploaded shell meshes (male v4 131638278150506, female v1 96360191472840), while Edit shows them and their bronze Quin_Joints meshes load.
- Yesterday's v3 shell (88335886514685) loads fine in Play, so it is upload processing/moderation, not the pipeline. It looks fine right after import only because of Studio's local cache.
- Check: Creator Hub → Development Items → Meshes ("Quin_Shell" status). If rejected: re-import / appeal. To test: clone the MeshPart into Workspace on a Play client and read ContentProvider:GetAssetFetchStatus(MeshId) (PreloadAsync on raw mesh ids always reports Failure, so don't use it).
- Resolved the same day: about 6 h after upload (re-checked 2026-10-22) both shells loaded in Play (Success). So it is a temporary processing/moderation delay. Wait, re-test, and only re-upload if it stays Failure.
