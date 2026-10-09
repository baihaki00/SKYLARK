"""
Cascadeur -> Quin (Mixamo) retarget, run inside Blender (headless).

  blender -b --python cascadeur_to_quin_blender.py -- <cascadeur.fbx> <quin_template.fbx> <out.json> [mirror]

The two skeletons differ in bone names, bone axes (Cascadeur's right side points backwards),
rest pose (Cascadeur: A-pose, Mixamo: T-pose), spine count (2 vs 3) and finger count, so the
clip is not renamed but retargeted in world space: every Quin bone takes the world-space
rotation its Cascadeur twin made away from rest. Arms and fingers are first swung from the
Mixamo T-pose onto the Cascadeur rest directions, so A-pose vs T-pose does not matter.
The hips follow the pelvis's travel (scaled by hip height). Out comes every Quin bone's local
transform per frame (JSON); quin_fbx.py writes them into the template FBX. The clip's own
motion (travel included) is kept as authored.

`mirror`: the clip mirrored left <-> right (a left sidestep becomes a right one): each Quin bone
takes its twin's turn away from rest (Left <-> Right), reflected across the body's left-right
plane, and the hips' travel flips sideways. (The Mixamo rig is symmetric, so twin rests mirror.)
"""
import sys
import bpy
from mathutils import Matrix, Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
SRC_PATH, TEMPLATE_PATH, OUT_PATH = argv[0], argv[1], argv[2]
MIRROR = len(argv) > 3 and argv[3] == "mirror"

P = "mixamorig:"

# Quin bone <- Cascadeur bone. `swing` bones (limbs, fingers) are first turned from the Mixamo
# rest direction onto the Cascadeur rest direction, joint to joint (T-pose vs A-pose, the legs'
# stance width), so each limb segment points exactly where Cascadeur's does. The torso, neck,
# head and toes carry the Cascadeur rotation away from rest as it is.
MAP = {
    "Hips": "pelvis", "Spine": "stomach", "Spine2": "chest", "Neck": "neck", "Head": "head",
}
SWING = set()
for side, s in (("Left", "l"), ("Right", "r")):
    MAP[side + "UpLeg"] = "thigh_" + s
    MAP[side + "Leg"] = "calf_" + s
    MAP[side + "Foot"] = "foot_" + s
    SWING.update((side + "UpLeg", side + "Leg", side + "Foot"))
    MAP[side + "ToeBase"] = "toe_" + s
    MAP[side + "Shoulder"] = "clavicle_" + s
    for q, c in (("Arm", "arm_"), ("ForeArm", "forearm_"), ("Hand", "hand_")):
        MAP[side + q] = c + s
        SWING.add(side + q)
    for finger in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            q = "%sHand%s%d" % (side, finger, i)
            MAP[q] = "f_%s%d_%s" % (finger.lower(), i, s)
            SWING.add(q)
# Spine1 (no twin) takes half way between Spine and Spine2
BLEND = {"Spine1": ("Spine", "Spine2", 0.5)}


def import_armature(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o is not arm:
            bpy.data.objects.remove(o, do_unlink=True)
    arm.name = name
    return arm


def rot(m):
    return m.to_3x3().normalized().to_quaternion()


def anat_dir(arm, bone):
    """World direction the bone actually points along (to its child; Cascadeur's right-side
    bones have their tails behind them)."""
    mw = arm.matrix_world
    head = mw @ bone.head_local
    kids = bone.children
    if bone.name.endswith(("hand_l", "hand_r")) or bone.name.endswith("Hand"):
        mid = [k for k in kids if "iddle" in k.name]
        kids = mid or kids
    kids = [k for k in kids if "twist" not in k.name and "weapon" not in k.name]
    if kids:
        tip = mw @ kids[0].head_local
    else:
        tip = mw @ bone.tail_local
    return (tip - head).normalized()


bpy.ops.wm.read_factory_settings(use_empty=True)
src = import_armature(SRC_PATH, "Cascadeur")
tgt = import_armature(TEMPLATE_PATH, "Quin")

src_action = src.animation_data.action
f0, f1 = (int(round(v)) for v in src_action.frame_range)
scene = bpy.context.scene
scene.frame_start, scene.frame_end = f0, f1

# the template's own clip goes; the Quin rig is posed from scratch
if tgt.animation_data:
    tgt.animation_data.action = None
else:
    tgt.animation_data_create()

sb = src.data.bones
tb = tgt.data.bones
missing = [q for q, c in MAP.items() if P + q not in tb or c not in sb]
for q in missing:
    print("  (skipped, not on both rigs:", q, "<-", MAP[q], ")")
    del MAP[q]

src_mw_q = rot(src.matrix_world)
tgt_mw_q = rot(tgt.matrix_world)
src_rest_w = {b.name: src_mw_q @ rot(b.matrix_local) for b in sb}
tgt_rest_w = {b.name: tgt_mw_q @ rot(b.matrix_local) for b in tb}

# swing: Mixamo rest direction onto Cascadeur rest direction
swing = {}
for q in SWING:
    if q in MAP:
        swing[q] = anat_dir(tgt, tb[P + q]).rotation_difference(anat_dir(src, sb[MAP[q]]))

# hips travel scale (hip heights above the feet)
src_hip_h = (src.matrix_world @ sb[MAP["Hips"]].head_local).z - (src.matrix_world @ sb["foot_l"].head_local).z
tgt_hip_h = (tgt.matrix_world @ tb[P + "Hips"].head_local).z - (tgt.matrix_world @ tb[P + "LeftFoot"].head_local).z
travel_scale = tgt_hip_h / src_hip_h if src_hip_h > 1e-6 else 1.0
src_pelvis_rest = src.matrix_world @ sb[MAP["Hips"]].head_local
tgt_hips_rest = tgt.matrix_world @ tb[P + "Hips"].head_local

order = []  # parents before children
def walk(b):
    order.append(b)
    for k in b.children:
        walk(k)
for b in tb:
    if b.parent is None:
        walk(b)

for pb in tgt.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)

def twin(q):
    """the bone on the other side (Left <-> Right); the middle ones are their own twins"""
    if q.startswith("Left"):
        return "Right" + q[4:]
    if q.startswith("Right"):
        return "Left" + q[5:]
    return q


def mirror_q(r):
    """a world turn reflected across the body's left-right plane (world X is the body's side
    axis: Cascadeur's and the Quin's left both sit at +X)"""
    return Quaternion((r.w, r.x, -r.y, -r.z))


last_q = {}
for f in range(f0, f1 + 1):
    scene.frame_set(f)
    deltas = {}
    for q, c in MAP.items():
        src_w = src_mw_q @ rot(src.pose.bones[c].matrix)
        deltas[q] = src_w @ src_rest_w[c].inverted()
    # each Quin bone's world turn away from its own rest this frame
    turn = {q: deltas[q] @ swing.get(q, Quaternion()) for q in deltas}
    for q, (a, z, t) in BLEND.items():
        if a in deltas and z in deltas:
            turn[q] = deltas[a].slerp(deltas[z], t)
    if MIRROR:
        turn = {q: mirror_q(turn[twin(q)]) for q in turn if twin(q) in turn}
    pose_w = {}  # world rotation of each Quin bone this frame
    for b in order:
        q = b.name[len(P):] if b.name.startswith(P) else b.name
        rest_w = tgt_rest_w[b.name]
        want = turn[q] @ rest_w if q in turn else None
        if b.parent:
            parent_rest_w = tgt_rest_w[b.parent.name]
            follow = pose_w[b.parent.name] @ parent_rest_w.inverted() @ rest_w  # rest relative to the posed parent
        else:
            follow = rest_w
        if want is None:
            want = follow
        pose_w[b.name] = want
        # Blender: posed world = follow @ basis, so the bone's own rotation is follow^-1 @ want
        pb = tgt.pose.bones[b.name]
        qv = (follow.inverted() @ want).normalized()
        prev = last_q.get(b.name)
        if prev is not None and prev.dot(qv) < 0:
            qv.negate()
        last_q[b.name] = qv.copy()
        pb.rotation_quaternion = qv
        pb.keyframe_insert("rotation_quaternion", frame=f - f0)
        if b.parent is None:
            src_pelvis = src.matrix_world @ src.pose.bones[MAP["Hips"]].head
            want_pos = tgt_hips_rest + (src_pelvis - src_pelvis_rest) * travel_scale
            # world offset -> the bone's rest frame (armature scale and axes)
            off_world = want_pos - tgt_hips_rest
            if MIRROR:
                off_world.x = -off_world.x
            off_arm = tgt.matrix_world.inverted().to_3x3() @ off_world
            off_bone = b.matrix_local.to_3x3().inverted() @ off_arm
            pb.location = off_bone
            pb.keyframe_insert("location", frame=f - f0)

# Each Quin bone's transform relative to its parent, per frame, in the template's own FBX space
# (the armature space of an FBX import is the file's space, in its centimetres). quin_fbx.py
# writes these into the template file itself, so the result is laid out exactly like a Mixamo
# download (rest angles in PreRotation, the motion in the rotation curves).
import json
bpy.data.objects.remove(src, do_unlink=True)
frames = []
for i in range(0, f1 - f0 + 1):
    scene.frame_set(i)
    pose = {}
    for pb in tgt.pose.bones:
        rel = pb.parent.matrix.inverted() @ pb.matrix if pb.parent else pb.matrix
        pose[pb.name] = [list(row) for row in rel]
    frames.append(pose)
with open(OUT_PATH, "w") as f:
    json.dump({"fps": scene.render.fps / scene.render.fps_base, "frames": frames}, f)
print("RETARGET_OK", OUT_PATH, "frames", f0, f1, "bones", len(MAP))
