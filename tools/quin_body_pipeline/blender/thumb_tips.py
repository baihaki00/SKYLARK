import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm)
G = body.vertex_groups
to_arm = arm.matrix_world.inverted() @ body.matrix_world
res = {}
for side in ("Left", "Right"):
    tip = "mixamorig:%sHandThumb3" % side
    b = arm.data.bones[tip]
    centre = (b.head_local + b.tail_local) / 2
    gt = G.get(tip) or G.new(name=tip)
    if any(x.group == gt.index for v in body.data.vertices for x in v.groups):
        res[tip] = "already weighted"; continue
    near = sorted(body.data.vertices, key=lambda v: ((to_arm @ v.co) - centre).length)[:8]
    for v in near:
        gt.add([v.index], 0.5, 'REPLACE')
    res[tip] = "%d verts, nearest %.2f cm" % (len(near), ((to_arm @ near[0].co) - centre).length)
print("THUMBS", res)
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.wm.save_mainfile()
