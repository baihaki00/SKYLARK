import bpy, sys
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
for name, frame in (("Quin_Joints", 21), ("Quin_Shell", 21)):
    ob = sc.objects[name]; me = ob.data
    sc.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get(); ev = ob.evaluated_get(dg); m2 = ev.to_mesh()
    pos = [v.co.copy() for v in m2.vertices]; ev.to_mesh_clear()
    bad = {}
    for e in me.edges:
        i, j = e.vertices
        r0 = (me.vertices[i].co - me.vertices[j].co).length
        if r0 < 1e-5: continue
        r = (pos[i] - pos[j]).length / r0
        if r > 2.5 or r < 0.4:
            for k in (i, j): bad[k] = max(bad.get(k, 0), max(r, 1/r))
    print("BAD", name, "verts", len(bad))
    # cluster summary: weights of bad verts
    tally = {}
    for k in bad:
        for g in me.vertices[k].groups:
            if g.weight > 0.05:
                n = ob.vertex_groups[g.group].name.replace("mixamorig:", "")
                tally[n] = tally.get(n, 0) + 1
    print("  bones on bad verts:", sorted(tally.items(), key=lambda kv: -kv[1])[:10])
    worst = sorted(bad, key=lambda k: -bad[k])[:6]
    for k in worst:
        co = ob.matrix_world @ me.vertices[k].co
        ws = ", ".join("%s %.2f" % (ob.vertex_groups[g.group].name.replace("mixamorig:", ""), g.weight) for g in me.vertices[k].groups if g.weight > 0.02)
        print("  v%d x%.1f rest(%.2f %.2f %.2f) %s" % (k, bad[k], *co, ws))
