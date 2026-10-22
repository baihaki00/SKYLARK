"""Versioned Quin body export: a rigged .blend -> QUIN_DESIGN\export\<Gender>\Quin<Gender>_v<N>.fbx,
N one past the highest existing version. The gender is "Female" when the .blend's name contains
"female" (any case), otherwise "Male". Runs Blender with export_quin.py.
  python export_versioned.py <rigged.blend> [Male|Female]"""
import os, re, sys, glob, shutil, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_ROOT = r"D:\SKYLARK\QUIN_DESIGN\export"
blend = os.path.abspath(sys.argv[1])
gender = sys.argv[2] if len(sys.argv) > 2 else ("Female" if "female" in os.path.basename(blend).lower() else "Male")
folder = os.path.join(EXPORT_ROOT, gender)
os.makedirs(folder, exist_ok=True)
versions = [int(m.group(1)) for f in glob.glob(os.path.join(folder, "Quin%s_v*.fbx" % gender))
            for m in [re.search(r"_v(\d+)\.fbx$", f)] if m]
n = max(versions, default=0) + 1
out = os.path.join(folder, "Quin%s_v%d.fbx" % (gender, n))
blender = shutil.which("blender") or r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
r = subprocess.run([blender, "-b", "--python", os.path.join(HERE, "export_quin.py"), "--", blend, out],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")
for line in ((r.stdout or "") + (r.stderr or "")).splitlines():
    if line.startswith(("MESH", "EXPORTED")) or "Error" in line:
        print(line)
if not os.path.exists(out):
    sys.exit("export failed")
# a note of where each version came from
with open(os.path.join(folder, "versions.txt"), "a", encoding="utf-8") as f:
    f.write("Quin%s_v%d  <-  %s\n" % (gender, n, blend))
print("\nVERSION Quin%s_v%d" % (gender, n))
print("Studio: 3D Importer -> %s (Rig Type Custom, Rest Pose Imported Rig), then ask Claude to make it the Quin%s template." % (out, gender))
