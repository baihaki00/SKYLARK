import bpy, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=sys.argv[-1])
for o in bpy.data.objects:
    if o.type == 'MESH':
        pts = [o.matrix_world @ v.co for v in o.data.vertices]
        print("FBX MESH %-18s tris %d groups %d height %.3f..%.3f" % (o.name, sum(len(p.vertices)-2 for p in o.data.polygons), len(o.vertex_groups), min(p.z for p in pts), max(p.z for p in pts)))
    if o.type == 'ARMATURE':
        names = sorted(b.name for b in o.data.bones)
        bad = [n for n in names if not n.startswith("mixamorig:") or n.endswith((".L", ".R"))]
        hips = o.matrix_world @ o.data.bones["mixamorig:Hips"].head_local
        print("FBX ARMATURE bones %d hips z %.3f odd names %s" % (len(names), hips.z, bad or "none"))
