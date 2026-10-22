"""Compare a rigged file's skeleton with ybot.fbx's (positions, directions) and report the neck/collar weights.
blender -b --python cmp_ybot.py -- <rigged.blend> <ybot.fbx>"""
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=a[1])
y = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
ref = {b.name: (y.matrix_world @ b.head_local, (y.matrix_world @ b.tail_local) - (y.matrix_world @ b.head_local)) for b in y.data.bones}
bpy.ops.wm.open_mainfile(filepath=a[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
rows = []
for b in arm.data.bones:
    if b.name not in ref: continue
    h = arm.matrix_world @ b.head_local
    d = (arm.matrix_world @ b.tail_local) - h
    rh, rd = ref[b.name]
    ang = d.angle(rd) * 57.2958 if d.length > 1e-6 and rd.length > 1e-6 else 0
    rows.append((b.name.replace("mixamorig:", ""), (h - rh).length * 100, ang))
rows.sort(key=lambda r: -(r[1] + r[2]))
print("BONES vs ybot (cm off, deg turned):")
for r in rows[:14]:
    print("  %-18s %5.1f cm  %5.1f deg" % r)
body = next(o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm)
G = body.vertex_groups
neck = arm.matrix_world @ arm.data.bones["mixamorig:Neck"].head_local
tally = {}
n = 0
for v in body.data.vertices:
    p = body.matrix_world @ v.co
    if (p - neck).length < 0.09:
        n += 1
        for g in v.groups:
            if g.weight > 0.02:
                nm = G[g.group].name.replace("mixamorig:", "")
                tally[nm] = tally.get(nm, 0) + g.weight
print("NECK-AREA verts within 9 cm of the neck joint:", n)
for k, w in sorted(tally.items(), key=lambda kv: -kv[1])[:8]:
    print("  %-16s total weight %.1f" % (k, w))
