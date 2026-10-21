"""Steps 5-7 on a fitted file: Mixamo names back, colour zones, skinning, a check, saved as a new file.
blender -b --python rig_it.py -- <in.blend> <out.blend>"""
import bpy, re, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
V = bpy.context.view_layer

def activate(ob, *others):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for o in (*others, ob):
        o.hide_set(False); o.select_set(True)
    V.objects.active = ob

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
# 1. Mixamo names back (no-op if already done)
activate(arm); bpy.ops.object.mode_set(mode='EDIT')
n = 0
for b in arm.data.edit_bones:
    new = re.sub(r"^mixamorig:(.+)\.L$", r"mixamorig:Left\1", b.name)
    new = re.sub(r"^mixamorig:(.+)\.R$", r"mixamorig:Right\1", new)
    if new != b.name: b.name = new; n += 1
arm.data.use_mirror_x = False
bpy.ops.object.mode_set(mode='OBJECT')
arm.data.pose_position = 'REST'
print("NAMES restored", n)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
# 2. modifiers applied (Object > Convert > Mesh)
for o in meshes:
    if o.modifiers:
        activate(o); bpy.ops.object.convert(target='MESH')
# 3. zones: bronze body = Quin_Joints, every wood piece joined = Quin_Shell
joints = next(o for o in meshes if o.name == "basemesh")
wood = [o for o in meshes if o is not joints]
activate(wood[0], *wood[1:]); bpy.ops.object.join()
shell = V.objects.active
shell.name, shell.data.name = "Quin_Shell", "Quin_Shell"
joints.name, joints.data.name = "Quin_Joints", "Quin_Joints"
for o in (shell, joints):
    activate(o); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# 4. skinning: automatic weights, then max 4 bones per vertex, normalised (Roblox)
for o in (shell, joints):
    activate(arm, o)
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    activate(o)
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    bare = sum(1 for v in o.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("SKIN %s: %d verts, %d tris, %d vertex groups, unweighted verts %d" % (o.name, len(o.data.vertices), tris, len(o.vertex_groups), bare))
arm.data.pose_position = 'POSE'
activate(arm)
bpy.ops.wm.save_as_mainfile(filepath=a[1])
print("SAVED", a[1])
