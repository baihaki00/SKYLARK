"""
Cascadeur FBX -> Quin (Roblox) one-clicker
==========================================
For every Cascadeur FBX in the folder above this one, it makes `<Name>_Quin/` with:
  1. `<Name>_Mixamo.fbx`               the clip retargeted onto the Quin's Mixamo skeleton
                                        (Mixamo bone names, the Quin's own rest pose)
  2. `<Name>_InPlace[x0.044].fbx`       autofixer: no horizontal travel, height kept, scaled
  3. `<Name>_NoHipsLocation[x0.044].fbx` autofixer: hips pinned, rotation only, scaled
Import 2 or 3 into Roblox as usual.

The Quin skeleton comes from quin_rig_template.fbx (a Mixamo download of the Quin's rig);
the retarget runs headless in Blender (cascadeur_to_quin_blender.py).
"""
import os
import sys
import glob
import shutil
import argparse
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import autofixer  # noqa: E402

BLENDER_CANDIDATES = [
    r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.4\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
]


def find_blender():
    for p in BLENDER_CANDIDATES:
        if os.path.exists(p):
            return p
    found = shutil.which("blender")
    if found:
        return found
    base = r"C:\Program Files\Blender Foundation"
    if os.path.isdir(base):
        for d in sorted(os.listdir(base), reverse=True):
            p = os.path.join(base, d, "blender.exe")
            if os.path.exists(p):
                return p
    raise RuntimeError("Blender not found (install it, or add its path to BLENDER_CANDIDATES)")


def convert(blender, src, scale, force):
    name = os.path.splitext(os.path.basename(src))[0]
    out_dir = os.path.join(os.path.dirname(src), name + "_Quin")
    mixamo = os.path.join(out_dir, name + "_Mixamo.fbx")
    inplace = os.path.join(out_dir, "%s_InPlace[x%s].fbx" % (name, scale))
    noloc = os.path.join(out_dir, "%s_NoHipsLocation[x%s].fbx" % (name, scale))
    if not force and all(os.path.exists(p) and os.path.getmtime(p) >= os.path.getmtime(src)
                         for p in (mixamo, inplace, noloc)):
        print("  [SKIPPED] %s -> already up-to-date in %s/" % (name, os.path.basename(out_dir)))
        return False

    os.makedirs(out_dir, exist_ok=True)
    print("\n=======================================================")
    print("Processing: " + os.path.basename(src))
    print("=======================================================")

    result = subprocess.run(
        [blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "cascadeur_to_quin_blender.py"),
         "--", src, os.path.join(HERE, "quin_rig_template.fbx"), mixamo],
        capture_output=True, text=True)
    log = result.stdout + result.stderr
    for line in log.splitlines():
        if line.startswith("  (skipped") or "Error" in line or "RETARGET_OK" in line:
            print("  " + line.strip())
    if "RETARGET_OK" not in log or not os.path.exists(mixamo):
        with open(os.path.join(out_dir, "blender_log.txt"), "w", encoding="utf-8") as f:
            f.write(log)
        raise RuntimeError("retarget failed (see %s/blender_log.txt)" % os.path.basename(out_dir))
    print("  [1/3] Retargeted onto the Quin rig: " + os.path.basename(mixamo))

    # autofixer writes into <Name>_Mixamo_Fixed/; move its two files up beside the retarget
    autofixer.process_fbx_file(mixamo, scale=scale, force=True)
    fixed_dir = os.path.join(out_dir, name + "_Mixamo_Fixed")
    for made, final in (("%s_Mixamo_InPlace[x%s].fbx" % (name, scale), inplace),
                        ("%s_Mixamo_NoHipsLocation[x%s].fbx" % (name, scale), noloc)):
        shutil.move(os.path.join(fixed_dir, made), final)
    shutil.rmtree(fixed_dir, ignore_errors=True)
    print("  [2/3] " + os.path.basename(inplace))
    print("  [3/3] " + os.path.basename(noloc))
    return True


def main():
    parser = argparse.ArgumentParser(description="Cascadeur FBX -> Quin (Roblox) converter")
    parser.add_argument("inputs", nargs="*", help="specific FBX files (default: every FBX in the folder)")
    parser.add_argument("--scale", type=float, default=0.044)
    parser.add_argument("--force", action="store_true", help="redo files that are already up-to-date")
    args = parser.parse_args()

    folder = os.path.dirname(HERE)
    files = args.inputs or sorted(glob.glob(os.path.join(folder, "*.fbx")))
    if not files:
        print("No Cascadeur FBX files found in " + folder)
        return
    blender = find_blender()
    print("Found %d FBX file(s). Blender: %s" % (len(files), blender))
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
    print("\n=======================================================")
    print("Converted: %d   Up-to-date: %d   Failed: %d" % (done, skipped, failed))
    print("=======================================================")


if __name__ == "__main__":
    main()
