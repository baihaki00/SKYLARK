"""Neck only: the collarbones (and arms) let go of the neck area, so it follows Neck/Spine2/Head
alone (the collarbones lift in most clips and dragged the neck's base up: a constant shrug).
blender -b --python fix_neck.py -- <in.blend> <out.blend>"""
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm)
G = body.vertex_groups
neck = arm.matrix_world @ arm.data.bones["mixamorig:Neck"].head_local
DROP = [g.index for g in G if any(k in g.name for k in ("Shoulder", "Arm", "Hand"))]
area, cleared = 0, 0
for v in body.data.vertices:
    p = body.matrix_world @ v.co
    if abs(p.x - neck.x) < 0.07 and abs(p.z - neck.z) < 0.08 and abs(p.y - neck.y) < 0.09:
        area += 1
        had = [g for g in v.groups if g.group in DROP and g.weight > 0]
        for g in had:
            G[g.group].remove([v.index]); cleared += 1
        if sum(g.weight for g in v.groups) < 1e-4:  # nothing left: the neck takes it
            G["mixamorig:Neck"].add([v.index], 1.0, 'REPLACE')
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
left = sum(g.weight for v in body.data.vertices for g in v.groups if G[g.group].name.endswith("LeftShoulder") and abs((body.matrix_world @ v.co).x - neck.x) < 0.07 and abs((body.matrix_world @ v.co).z - neck.z) < 0.08)
print("NECK area verts %d, collarbone/arm weights removed %d, shoulder weight left in area %.2f" % (area, cleared, left))
bpy.ops.wm.save_as_mainfile(filepath=a[1])
print("SAVED", a[1])
