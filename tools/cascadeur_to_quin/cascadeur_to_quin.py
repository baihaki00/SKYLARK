"""
Cascadeur FBX -> Quin (Roblox) one-clicker
==========================================
For every Cascadeur FBX in the folder above this one, it writes `<Name>_Quin[x0.044].fbx`
beside it: the clip on the Quin's skeleton (Mixamo bone names, the Quin's rest pose), sized
for Roblox. The motion is kept as authored (no in-placing). Import that file into Roblox.

Bones are not just renamed: the two skeletons point their bones different ways and rest in
different poses (A vs T), so a renamed clip would twist every limb. The clip is retargeted
headless in Blender (cascadeur_to_quin_blender.py) onto quin_rig_template.fbx (a Mixamo
download of the Quin's rig), then fbx_resize.py shrinks it x0.044 for Roblox.
"""
import os
import glob
import shutil
import argparse
import subprocess

import fbx_resize

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
    out = os.path.join(os.path.dirname(src), "%s_Quin[x%s].fbx" % (name, scale))
    if not force and os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(src):
        print("  [SKIPPED] %s -> already up-to-date" % name)
        return False
    print("  Converting %s ..." % os.path.basename(src))
    result = subprocess.run(
        [blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "cascadeur_to_quin_blender.py"),
         "--", src, os.path.join(HERE, "quin_rig_template.fbx"), out],
        capture_output=True, text=True)
    log = result.stdout + result.stderr
    for line in log.splitlines():
        if line.startswith("  (skipped"):
            print("  " + line.strip())
    if "RETARGET_OK" not in log or not os.path.exists(out):
        logfile = os.path.join(os.path.dirname(src), name + "_Quin_error.txt")
        with open(logfile, "w", encoding="utf-8") as f:
            f.write(log)
        raise RuntimeError("retarget failed (see %s)" % os.path.basename(logfile))
    fbx_resize.resize(out, scale)  # every bone's position, rest and animated, x scale
    print("  [OK] " + os.path.basename(out))
    return True


def main():
    parser = argparse.ArgumentParser(description="Cascadeur FBX -> Quin (Roblox) converter")
    parser.add_argument("inputs", nargs="*", help="specific FBX files (default: every FBX in the folder)")
    parser.add_argument("--scale", type=float, default=0.044)
    parser.add_argument("--force", action="store_true", help="redo files that are already up-to-date")
    args = parser.parse_args()

    folder = os.path.dirname(HERE)
    files = args.inputs or [f for f in sorted(glob.glob(os.path.join(folder, "*.fbx")))
                            if "_Quin[" not in os.path.basename(f)]
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
