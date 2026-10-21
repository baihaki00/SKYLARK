"""Export a rigged one-mesh Quin for Roblox: split into zones by material (bronze / wood), the wood
split into body regions so no mesh passes Roblox's 20k triangles (no reduction), rest pose, FBX.
blender -b --python export_quin.py -- <rigged.blend> <out.fbx>"""
import bpy, bmesh, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
V = bpy.context.view_layer
LIMIT = 20000
def activate(ob, *others):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for o in (*others, ob):
        o.hide_set(False); o.select_set(True)
    V.objects.active = ob
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
if arm.animation_data: arm.animation_data.action = None
arm.data.pose_position = 'REST'
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
body = next(o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm)
# zones by material
activate(body); bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='MATERIAL'); bpy.ops.object.mode_set(mode='OBJECT')
zones = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent is arm]
def region(ob, part):
    """the body region a plate belongs to, by the bones that own it"""
    tot = {}
    for i in part:
        for g in ob.data.vertices[i].groups:
            tot[g.group] = tot.get(g.group, 0) + g.weight
    name = ob.vertex_groups[max(tot, key=tot.get)].name.replace("mixamorig:", "")
    if name.startswith("Left") and any(k in name for k in ("Arm", "Hand", "Shoulder")): return "ArmL"
    if name.startswith("Right") and any(k in name for k in ("Arm", "Hand", "Shoulder")): return "ArmR"
    if any(k in name for k in ("UpLeg", "Leg", "Foot", "Toe")): return "Legs"
    return "Torso"
out = []
for z in zones:
    wood = "IVORY" in z.data.materials[0].name.upper() or "LACQUER" in z.data.materials[0].name.upper()
    base = "Quin_Shell" if wood else "Quin_Joints"
    tris = sum(len(p.vertices) - 2 for p in z.data.polygons)
    if tris <= LIMIT:
        z.name = z.data.name = base; out.append(z); continue
    # split by region (plates are separate pieces: each goes whole to one region)
    bm = bmesh.new(); bm.from_mesh(z.data); bm.verts.ensure_lookup_table()
    seen, parts = set(), []
    for v in bm.verts:
        if v.index in seen: continue
        st = [v]; seen.add(v.index); part = []
        while st:
            c = st.pop(); part.append(c.index)
            for e in c.link_edges:
                o = e.other_vert(c)
                if o.index not in seen: seen.add(o.index); st.append(o)
        parts.append(part)
    bm.free()
    labels = {}
    for part in parts:
        r = region(z, part)
        for i in part: labels[i] = r
    # one copy per region, each keeping only its own plates
    for r in sorted(set(labels.values())):
        piece = z.copy(); piece.data = z.data.copy()
        bpy.context.scene.collection.objects.link(piece)
        piece.name = piece.data.name = "%s_%s" % (base, r)
        bm = bmesh.new(); bm.from_mesh(piece.data); bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if labels[v.index] != r], context='VERTS')
        bm.to_mesh(piece.data); bm.free()
        out.append(piece)
    bpy.data.objects.remove(z, do_unlink=True)
for o in out:
    t = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("MESH %-20s tris %6d%s mat %s" % (o.name, t, "  OVER!" if t > LIMIT else "", o.data.materials[0].name))
activate(arm, *out)
bpy.ops.export_scene.fbx(filepath=a[1], use_selection=True, object_types={'ARMATURE', 'MESH'},
    add_leaf_bones=False, bake_anim=False, apply_unit_scale=True, mesh_smooth_type='FACE',
    primary_bone_axis='Y', secondary_bone_axis='X', armature_nodetype='NULL', use_armature_deform_only=False)
print("EXPORTED", a[1])
