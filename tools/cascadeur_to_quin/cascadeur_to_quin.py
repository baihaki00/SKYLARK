"""
Cascadeur FBX -> Quin (Roblox) one-clicker
==========================================
For every Cascadeur FBX in the folder above this one, it writes two files into
`<Name>_CascadeurQuin/` beside it, the clip
on the Quin's skeleton (Mixamo bone names, the Quin's rest pose), sized for Roblox:
  <Name>_Quin[x0.044].fbx          the motion as authored (travel included)
  <Name>_Quin_InPlace[x0.044].fbx  the hips stay on their spot (height and rotations kept)

Bones are not just renamed: the two skeletons point their bones different ways and rest in
different poses (A vs T), so a renamed clip would twist every limb. The clip is retargeted
headless in Blender (cascadeur_to_quin_blender.py) onto quin_rig_template.fbx (a Mixamo
download of the Quin's rig); quin_fbx.py writes it into that template file itself (the exact
Mixamo layout), scaled x0.044. Import with Rest Pose Source "Imported Rig".
"""
import os
import glob
import shutil
import argparse
import tempfile
import subprocess

import quin_fbx

HERE = os.path.dirname(os.path.abspath(__file__))


def find_blender():
    found = shutil.which("blender")
    if found:
        return found
    base = r"C:\Program Files\Blender Foundation"
    if os.path.isdir(base):
        for d in sorted(os.listdir(base), reverse=True):  # newest first
            p = os.path.join(base, d, "blender.exe")
            if os.path.exists(p):
                return p
    raise RuntimeError("Blender not found (install it, or put blender.exe on the PATH)")


def convert(blender, src, scale, force):
    name = os.path.splitext(os.path.basename(src))[0]
    out_dir = os.path.join(os.path.dirname(src), name + "_CascadeurQuin")
    out = os.path.join(out_dir, "%s_Quin[x%s].fbx" % (name, scale))
    out_in_place = os.path.join(out_dir, "%s_Quin_InPlace[x%s].fbx" % (name, scale))
    if not force and all(os.path.exists(p) and os.path.getmtime(p) >= os.path.getmtime(src)
                         for p in (out, out_in_place)):
        print("  [SKIPPED] %s -> already up-to-date" % name)
        return False
    print("  Converting %s ..." % os.path.basename(src))
    os.makedirs(out_dir, exist_ok=True)
    template = os.path.join(HERE, "quin_rig_template.fbx")
    clip_json = os.path.join(tempfile.gettempdir(), "cascadeur_to_quin_%s.json" % name)
    result = subprocess.run(
        [blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "cascadeur_to_quin_blender.py"),
         "--", src, template, clip_json],
        capture_output=True, text=True)
    log = result.stdout + result.stderr
    for line in log.splitlines():
        if line.startswith("  (skipped"):
            print("  " + line.strip())
    if "RETARGET_OK" not in log or not os.path.exists(clip_json):
        logfile = os.path.join(os.path.dirname(src), name + "_Quin_error.txt")
        with open(logfile, "w", encoding="utf-8") as f:
            f.write(log)
        raise RuntimeError("retarget failed (see %s)" % os.path.basename(logfile))
    quin_fbx.build(template, clip_json, out, scale)  # into the template's own Mixamo layout, x scale
    quin_fbx.build(template, clip_json, out_in_place, scale, in_place=True)
    os.remove(clip_json)
    print("  [OK] " + os.path.basename(out))
    print("  [OK] " + os.path.basename(out_in_place))
    return True


def main():
    parser = argparse.ArgumentParser(description="Cascadeur FBX -> Quin (Roblox) converter")
    parser.add_argument("inputs", nargs="*", help="specific FBX files (default: every FBX in the folder)")
    parser.add_argument("--scale", type=float, default=0.044)
    parser.add_argument("--force", action="store_true", help="redo files that are already up-to-date")
    args = parser.parse_args()

    folder = os.path.dirname(HERE)
    files = args.inputs or [f for f in sorted(glob.glob(os.path.join(folder, "*.fbx")))
                            if "_Quin[" not in os.path.basename(f) and "_Quin_InPlace[" not in os.path.basename(f)]
    if not files:
        print("No Cascadeur FBX files found in " + folder)
        return
    blender = find_blender()
    print("Found %d FBX file(s). Blender: %s\n" % (len(files), blender))
    done = skipped = failed = 0
    for path in files:
        try:
            if convert(blender, os.path.abspath(path), args.scale, args.force):
                done += 1
            else:
                skipped += 1
        except Exception as e:  # keep going with the rest
            failed += 1
            print("  ERROR %s: %s" % (os.path.basename(path), e))
    print("\nConverted: %d   Up-to-date: %d   Failed: %d" % (done, skipped, failed))


if __name__ == "__main__":
    main()
