"""Running long jump flight, in place, for phase-driven playback in Roblox.
Frames 1..31 at 30 fps = phase 0..1 (takeoff .. touchdown). Poses are set by aiming each bone in
armature space (Y up, +Z forward, the character's left is +X), parents first.
Run: blender --background xbot.blend --python make_longjump.py -- <outdir>
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.dirname(bpy.data.filepath)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
scene = bpy.context.scene
scene.render.fps = 30

# A fresh action (the file's mixamo clip is left alone, unassigned)
if arm.animation_data is None:
    arm.animation_data_create()
action = bpy.data.actions.new("QuinLongJumpPhase")
arm.animation_data.action = action
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'
    pb.matrix_basis = Matrix.Identity(4)

def P(name):
    return arm.pose.bones["mixamorig:" + name]

def leg_dir(theta):  # theta degrees from straight down, + forward
    t = math.radians(theta)
    return Vector((0, -math.cos(t), math.sin(t)))

def lean_dir(phi):  # an upright bone leaned phi degrees forward (+) / back (-)
    p = math.radians(phi)
    return Vector((0, math.cos(p), math.sin(p)))

def aim(name, direction):
    pb = P(name)
    rest = pb.bone.matrix_local
    rest_dir = rest.to_3x3().col[1].normalized()
    q = rest_dir.rotation_difference(direction.normalized())
    rot = q.to_matrix() @ rest.to_3x3()
    bpy.context.view_layer.update()
    m = rot.to_4x4()
    m.translation = pb.head.copy()
    pb.matrix = m
    bpy.context.view_layer.update()

FOOT_REST = 129  # the foot bone points this far round from straight down (ankle to ball)

def pose(p):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    lean = p["lean"]
    aim("Spine", lean_dir(lean * 0.35))
    aim("Spine1", lean_dir(lean * 0.7))
    aim("Spine2", lean_dir(lean))
    aim("Neck", lean_dir(lean * 0.5))
    aim("Head", lean_dir(lean * 0.1 - 10 + 10))
    for side, s in (("Left", 1), ("Right", -1)):
        leg = p[side + "Leg"]
        aim(side + "UpLeg", leg_dir(leg[0]))
        aim(side + "Leg", leg_dir(leg[1]))
        aim(side + "Foot", leg_dir(leg[1] + FOOT_REST - leg[2]))
        ua, fa = p[side + "Arm"]
        aim(side + "Arm", Vector((ua[0] * s, ua[1], ua[2])))
        aim(side + "ForeArm", Vector((fa[0] * s, fa[1], fa[2])))

# (legs: thigh angle, shin angle, foot plantar flexion; arms: upper and fore arm directions with
# x toward the arm's own side)
POSES = [
    (1, "takeoff", dict(lean=12,
        RightLeg=(72, -20, 15), LeftLeg=(-28, -38, 45),
        LeftArm=((0.15, 0.25, 0.95), (0.05, 0.85, 0.5)), RightArm=((0.25, -0.55, -0.8), (0.1, -0.85, -0.5)))),
    (8, "rise", dict(lean=6,
        RightLeg=(62, -5, 15), LeftLeg=(-30, -75, 40),
        LeftArm=((0.25, 0.8, 0.55), (0.1, 0.95, 0.3)), RightArm=((0.6, 0.35, -0.45), (0.5, 0.65, -0.3)))),
    (16, "apex hang", dict(lean=-16,
        RightLeg=(-14, -100, 35), LeftLeg=(-20, -108, 35),
        LeftArm=((0.35, 0.7, -0.65), (0.25, 0.75, -0.6)), RightArm=((0.35, 0.7, -0.65), (0.25, 0.75, -0.6)))),
    (23, "sail", dict(lean=35,
        RightLeg=(85, 68, 5), LeftLeg=(82, 66, 5),
        LeftArm=((0.3, 0.15, 0.95), (0.25, -0.15, 0.95)), RightArm=((0.3, 0.15, 0.95), (0.25, -0.15, 0.95)))),
    (31, "landing reach", dict(lean=48,
        RightLeg=(95, 82, 0), LeftLeg=(92, 80, 0),
        LeftArm=((0.3, -0.75, -0.6), (0.2, -0.85, -0.5)), RightArm=((0.3, -0.75, -0.6), (0.2, -0.85, -0.5)))),
]
KEYED = ["Spine", "Spine1", "Spine2", "Neck", "Head"] + [s + b for s in ("Left", "Right") for b in ("UpLeg", "Leg", "Foot", "Arm", "ForeArm")]
for frame, label, p in POSES:
    pose(p)
    for name in KEYED:
        P(name).keyframe_insert("rotation_quaternion", frame=frame)
    print("keyed", frame, label)
scene.frame_start, scene.frame_end = 1, 31
bpy.ops.object.mode_set(mode='OBJECT')

# --- Side-view renders of each key pose (workbench) ---
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
center = arm.matrix_world @ Vector((0, 100, 0))  # (hip height, armature space cm)
cam_data = bpy.data.cameras.new("SideCam")
cam = bpy.data.objects.new("SideCam", cam_data)
scene.collection.objects.link(cam)
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.8
fwd = (arm.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()
up = (arm.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()
left = (arm.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
cam.location = center - left * 6  # from the character's right side: forward is to the right of the image
look = left  # (camera axes: X = forward, Y = up, -Z = look; this side keeps them right-handed)
cam.matrix_world = Matrix.LocRotScale(cam.location, (Matrix((
    (fwd.x, up.x, -look.x), (fwd.y, up.y, -look.y), (fwd.z, up.z, -look.z))).to_quaternion()), None)
scene.camera = cam
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x, scene.render.resolution_y = 360, 420
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'SINGLE'
for frame, label, _ in POSES:
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(out_dir, "longjump_%02d_%s.png" % (frame, label.replace(" ", "_")))
    bpy.ops.render.render(write_still=True)
print("renders written to", out_dir)

# One strip of the five poses (left to right = takeoff .. landing)
import numpy as np
imgs = []
for frame, label, _ in POSES:
    path = os.path.join(out_dir, "longjump_%02d_%s.png" % (frame, label.replace(" ", "_")))
    im = bpy.data.images.load(path)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    imgs.append(px)
strip = np.concatenate(imgs, axis=1)
sheet = bpy.data.images.new("strip", strip.shape[1], strip.shape[0], alpha=True)
sheet.pixels = strip.ravel()
sheet.filepath_raw = os.path.join(out_dir, "QuinLongJumpPhase_poses.png")
sheet.file_format = 'PNG'
sheet.save()

# FBX for the Roblox Animation Editor (Import > From FBX Animation): the armature and its action,
# Mixamo bone names, in place
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.fbx(filepath=os.path.join(out_dir, "QuinLongJumpPhase.fbx"), use_selection=True,
    object_types={'ARMATURE'}, add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
    bake_anim_use_nla_strips=False, bake_anim_force_startend_keying=True, bake_anim_simplify_factor=0.0)
print("fbx written")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "xbot_longjump.blend"), copy=True)
print("saved")
