"""1. Collarbones (LeftShoulder/RightShoulder) back to the ybot's rest orientation: same direction,
   length and roll as in ybot.fbx, ending at the fitted arm joint (only their start moves).
2. Thumb3/Pinky3 (which held no weight, so Roblox dropped them) take over the tip part of the
   finger from Thumb2/Pinky2.
blender -b --python fix_shoulders_fingers.py -- <rigged.blend> <ybot.fbx> <out.blend>"""
import bpy, sys
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
# the ybot's collarbones, in armature space
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=a[1])
yarm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bpy.context.view_layer.objects.active = yarm; bpy.ops.object.mode_set(mode='EDIT')
ref = {}
for side in ("Left", "Right"):
    eb = yarm.data.edit_bones["mixamorig:%sShoulder" % side]
    ref[side] = (eb.tail - eb.head, eb.roll)
bpy.ops.object.mode_set(mode='OBJECT')

bpy.ops.wm.open_mainfile(filepath=a[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm)
if arm.animation_data: arm.animation_data.action = None
bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for side, (vec, roll) in ref.items():
    eb = arm.data.edit_bones["mixamorig:%sShoulder" % side]
    before = (eb.tail - eb.head).normalized()
    eb.use_connect = False
    eb.head = eb.tail - vec
    eb.roll = roll
    print("SHOULDER %s turned back %.1f deg, start moved %.2f cm" % (side, before.angle((eb.tail - eb.head).normalized()) * 57.3, 0))
heads = {}
for n in ("LeftHandThumb3", "LeftHandPinky3", "RightHandThumb3", "RightHandPinky3", "LeftHandThumb2", "LeftHandPinky2", "RightHandThumb2", "RightHandPinky2"):
    eb = arm.data.edit_bones["mixamorig:" + n]
    heads[n] = (eb.head.copy(), (eb.tail - eb.head).normalized())
bpy.ops.object.mode_set(mode='OBJECT')
# fingertips: vertices of the finger past the tip bone's start go to the tip bone
G = body.vertex_groups
mw_inv = arm.matrix_world.inverted() @ body.matrix_world
moved = {}
for side in ("Left", "Right"):
    for f in ("Thumb", "Pinky"):
        tip, mid = "mixamorig:%sHand%s3" % (side, f), "mixamorig:%sHand%s2" % (side, f)
        gt = G.get(tip) or G.new(name=tip)
        gm = G.get(mid)
        if not gm: continue
        h, d = heads["%sHand%s3" % (side, f)]
        n = 0
        for v in body.data.vertices:
            w = next((x.weight for x in v.groups if x.group == gm.index), 0)
            if w <= 0: continue
            p = mw_inv @ v.co
            if (p - h).dot(d) > 0:  # past the tip joint, along the finger
                gt.add([v.index], w, 'ADD'); gm.add([v.index], 0, 'REPLACE'); gm.remove([v.index]); n += 1
        moved[tip.replace("mixamorig:", "")] = n
print("FINGERTIPS", moved)
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.wm.save_as_mainfile(filepath=a[2])
print("SAVED", a[2])
