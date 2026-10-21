"""Clean a rigged Quin's weights: tip bones (*_End, finger 4s) emptied, weights smoothed, normalised,
max 4 per vertex. blender -b --python fix_weights.py -- <in.blend> <out.blend>"""
import bpy, re, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
V = bpy.context.view_layer
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
TIP = re.compile(r"(_End$|Thumb4$|Index4$|Middle4$|Ring4$|Pinky4$)")
for ob in [o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm]:
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); V.objects.active = ob
    emptied = 0
    allv = range(len(ob.data.vertices))
    for g in ob.vertex_groups:
        if TIP.search(g.name):
            n = sum(1 for v in ob.data.vertices for x in v.groups if x.group == g.index and x.weight > 0)
            emptied += n
            g.remove(list(allv))
    # verts left with no weight take their nearest neighbour's later via smoothing; normalise first
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    bpy.ops.object.mode_set(mode='WEIGHT_PAINT')  # (the smooth tool runs only here)
    ob.data.use_paint_mask = False; ob.data.use_paint_mask_vertex = False
    bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=4, expand=0.0)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    # the head plate moves only with the Head bone (it took up to 60% Neck: it stretched at the top)
    hg = ob.vertex_groups.get("mixamorig:Head")
    if hg and ob.name == "Quin_Shell":
        import bmesh
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
        seen = set(); made = 0
        for v0 in bm.verts:
            if v0.index in seen: continue
            st = [v0]; seen.add(v0.index); part = []
            while st:
                c = st.pop(); part.append(c.index)
                for e in c.link_edges:
                    o = e.other_vert(c)
                    if o.index not in seen: seen.add(o.index); st.append(o)
            tot = {}
            for i in part:
                for x in ob.data.vertices[i].groups: tot[x.group] = tot.get(x.group, 0) + x.weight
            whole = sum(tot.values()) or 1
            if tot.get(hg.index, 0) / whole > 0.3:
                for g in ob.vertex_groups: g.remove(part)
                hg.add(part, 1.0, 'REPLACE'); made += len(part)
        bm.free()
        print("HEAD plate rigid on Head: %d verts" % made)
    bare = sum(1 for v in ob.data.vertices if sum(x.weight for x in v.groups) < 1e-4)
    print("FIX %s: tip-bone weights removed %d, unweighted now %d" % (ob.name, emptied, bare))
bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); V.objects.active = arm
bpy.ops.wm.save_as_mainfile(filepath=a[1])
print("SAVED", a[1])
