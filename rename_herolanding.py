import os
import glob

# Rename in NEW ANIMATION and SKYLARKTEST
dirs_to_fix = [r'D:\SKYLARK\NEW ANIMATION', r'D:\SKYLARK\SKYLARKTEST']

renamed_count = 0
for d in dirs_to_fix:
    if not os.path.exists(d): continue
    for root, dirs, files in os.walk(d):
        for f in files:
            if '_HeroLanding_Planted[x0.044].fbx' in f:
                old_path = os.path.join(root, f)
                new_name = f.replace('_HeroLanding_Planted[x0.044].fbx', '_InPlace[x0.044].fbx')
                new_path = os.path.join(root, new_name)
                if os.path.exists(new_path):
                    os.remove(new_path)
                os.rename(old_path, new_path)
                renamed_count += 1
                if renamed_count <= 5:
                    print(f"Renamed: {f} -> {new_name}")

print(f"\nSuccessfully renamed {renamed_count} files from HeroLanding to InPlace!")
