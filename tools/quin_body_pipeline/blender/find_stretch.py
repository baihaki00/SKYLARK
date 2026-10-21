"""Which pieces stretch during the run: max edge-length ratio (posed / rest) per loose part, over
the clip. blender -b --python find_stretch.py -- <rigged.blend> <run.fbx>"""
import bpy, bmesh, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
before = set(sc.objects)
bpy.ops.import_scene.fbx(filepath=a[1])
new = [o for o in sc.objects if o not in before]
act = next(o for o in new if o.type == 'ARMATURE').animation_data.action
for o in new: bpy.data.objects.remove(o, do_unlink=True)
arm.animation_data_create(); arm.animation_data.action = act
if hasattr(arm.animation_data, "action_slot") and act.slots: arm.animation_data.action_slot = act.slots[0]
arm.data.pose_position = 'POSE'
f0, f1 = (int(x) for x in act.frame_range)
for ob in [o for o in sc.objects if o.type == 'MESH' and o.parent is arm]:
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    seen, part_of, parts = set(), {}, []
    for v in bm.verts:
        if v.index in seen: continue
        st=[v]; seen.add(v.index); idx=len(parts); part=[]
        while st:
            c=st.pop(); part.append(c.index); part_of[c.index]=idx
            for e in c.link_edges:
                o=e.other_vert(c)
                if o.index not in seen: seen.add(o.index); st.append(o)
        parts.append(part)
    edges = [(e.verts[0].index, e.verts[1].index) for e in bm.edges]
    bm.free()
    rest = [v.co.copy() for v in me.vertices]
    rest_len = [(rest[i]-rest[j]).length for i,j in edges]
    worst = [1.0]*len(parts); worst_f=[0]*len(parts)
    for f in range(f0, f1+1, 2):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg); m2 = ev.to_mesh()
        pos = [v.co.copy() for v in m2.vertices]
        ev.to_mesh_clear()
        for k,(i,j) in enumerate(edges):
            if rest_len[k] < 1e-5: continue
            r = (pos[i]-pos[j]).length / rest_len[k]
            r = max(r, 1/r) if r > 0 else 99
            p = part_of[i]
            if r > worst[p]: worst[p]=r; worst_f[p]=f
    ranked = sorted(range(len(parts)), key=lambda p: -worst[p])
    for p in ranked[:8]:
        totals={}
        for i in parts[p]:
            for g in me.vertices[i].groups:
                totals[g.group]=totals.get(g.group,0)+g.weight
        whole=sum(totals.values()) or 1
        top=sorted(totals.items(), key=lambda kv:-kv[1])[:4]
        c = sum((rest[i] for i in parts[p]), rest[0]*0)/len(parts[p])
        c = ob.matrix_world @ c
        print("STRETCH %s part%d n%d x%.2f @f%d centre(%.2f %.2f %.2f) bones %s" % (ob.name, p, len(parts[p]), worst[p], worst_f[p], *c,
              ", ".join("%s %.0f%%" % (ob.vertex_groups[g].name.replace("mixamorig:",""), 100*w/whole) for g,w in top)))
