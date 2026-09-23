import os
import shutil
import zipfile

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
backup_name = "backup_post_strike1_pre_consolidation_20260923"
backup_dir = os.path.join(scratch_dir, backup_name)
zip_path = os.path.join(scratch_dir, f"{backup_name}.zip")

os.makedirs(backup_dir, exist_ok=True)

lua_files = [f for f in os.listdir(scratch_dir) if f.endswith(".lua")]
copied = 0

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
    for f in sorted(lua_files):
        src = os.path.join(scratch_dir, f)
        dst = os.path.join(backup_dir, f)
        shutil.copy2(src, dst)
        zipf.write(src, arcname=f)
        copied += 1

print(f"Created backup directory: {backup_dir} ({copied} files)")
print(f"Created immutable zip archive: {zip_path} ({os.path.getsize(zip_path)} bytes)")
