import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
exec(open(a[1]).read())
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
names = [b.name for b in arm.data.bones]
print("SAMPLE", [x for x in names if "Arm" in x or "Index1" in x][:8])
# symmetry check: every .L bone has a .R twin mirrored across X
mw = arm.matrix_world
worst = 0
for b in arm.data.bones:
    if b.name.endswith(".L"):
        t = arm.data.bones.get(b.name[:-2] + ".R")
        h1, h2 = mw @ b.head_local, mw @ t.head_local
        worst = max(worst, abs(h1.x + h2.x) + abs(h1.y - h2.y) + abs(h1.z - h2.z))
print("SYMMETRY worst mismatch (m) %.4f" % worst)
bpy.ops.wm.save_as_mainfile(filepath=a[2])
print("SAVED", a[2])
