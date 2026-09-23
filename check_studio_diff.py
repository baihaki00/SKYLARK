import sys
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r'C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities')
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected Studio ID:", client.studio_id)

place_info = client.execute_luau("return tostring(game.PlaceId) .. ' | ' .. tostring(game.Name)")
print("Place:", place_info)

check_script = """
local HttpService = game:GetService("HttpService")
local items = {}
local function scan(container)
    if not container then return end
    for _, child in ipairs(container:GetDescendants()) do
        if child:IsA("LuaSourceContainer") then
            table.insert(items, {
                Name = child.Name,
                FullName = child:GetFullName(),
                ClassName = child.ClassName,
                Length = #child.Source
            })
        end
    end
end

if game.ReplicatedStorage:FindFirstChild("QuinCore") then
    scan(game.ReplicatedStorage.QuinCore)
end
scan(game.ServerScriptService)
if game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts") then
    scan(game.StarterPlayer.StarterPlayerScripts)
end

return HttpService:JSONEncode(items)
"""

res = client.execute_luau(check_script)
raw_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
try:
    items = json.loads(raw_text)
except Exception as e:
    print(f"Failed to parse JSON: {e}")
    sys.exit(1)

print(f"Total scripts found in Studio: {len(items)}")

# Map of sync files
from sync_and_restart import sync_map

studio_by_fullname = {it["FullName"]: it for it in items}

print("\n--- COMPARING SCRIPT SIZES: STUDIO VS LOCAL SCRATCH ---")
differences = []
same_count = 0

for name, target_path, filename, class_name in sync_map:
    local_path = os.path.join(r'C:\Users\User\.gemini\antigravity\scratch', filename)
    if not os.path.exists(local_path):
        print(f"[MISSING LOCAL] {filename}")
        continue
    with open(local_path, "r", encoding="utf-8", errors="replace") as f:
        local_src = f.read()

    studio_item = studio_by_fullname.get(target_path)
    if not studio_item:
        print(f"[NOT IN STUDIO] {target_path}")
        continue

    local_len = len(local_src)
    studio_len = studio_item["Length"]
    if local_len != studio_len:
        differences.append({
            "name": name,
            "target": target_path,
            "file": filename,
            "local_len": local_len,
            "studio_len": studio_len,
            "diff_len": studio_len - local_len
        })
    else:
        same_count += 1

sync_targets = set(t[1] for t in sync_map)
new_in_studio = [it for it in items if it["FullName"] not in sync_targets]

print(f"\n{same_count} scripts have identical byte counts.")
print(f"{len(differences)} scripts have DIFFERENT byte counts in Studio:")
for d in sorted(differences, key=lambda x: abs(x["diff_len"]), reverse=True):
    print(f"  * {d['name']:<25} ({d['file']:<28}): Local={d['local_len']:>6} B, Studio={d['studio_len']:>6} B (Diff: {d['diff_len']:+6d} B)")

if new_in_studio:
    print(f"\n{len(new_in_studio)} scripts in Studio NOT in sync_map:")
    for n in new_in_studio:
        print(f"  + {n['FullName']:<50} ({n['ClassName']}, {n['Length']} bytes)")


# Map of sync files
from sync_and_restart import sync_map

studio_by_fullname = {it["FullName"]: it for it in items}

print("\n--- COMPARING STUDIO SOURCE VS LOCAL SCRATCH SOURCE ---")
differences = []
new_in_studio = []

for name, target_path, filename, class_name in sync_map:
    local_path = os.path.join(r'C:\Users\User\.gemini\antigravity\scratch', filename)
    if not os.path.exists(local_path):
        print(f"[MISSING LOCAL] {filename} does not exist locally!")
        continue
    with open(local_path, "r", encoding="utf-8", errors="replace") as f:
        local_src = f.read()

    studio_item = studio_by_fullname.get(target_path)
    if not studio_item:
        print(f"[MISSING IN STUDIO] {target_path}")
        continue

    studio_src = studio_item["Source"]
    if local_src != studio_src:
        diff_len = len(studio_src) - len(local_src)
        differences.append({
            "name": name,
            "target": target_path,
            "file": filename,
            "local_len": len(local_src),
            "studio_len": len(studio_src),
            "diff_len": diff_len
        })

sync_targets = set(t[1] for t in sync_map)
for it in items:
    if it["FullName"] not in sync_targets:
        new_in_studio.append(it)

print(f"\nFound {len(differences)} modified scripts in Studio compared to local scratch:")
for d in differences:
    print(f"  * {d['name']} ({d['file']}): Local={d['local_len']} bytes, Studio={d['studio_len']} bytes (Diff: {d['diff_len']:+d})")

print(f"\nFound {len(new_in_studio)} scripts in Studio not in sync_map:")
for n in new_in_studio:
    print(f"  + {n['FullName']} ({n['ClassName']}, {n['Length']} bytes)")
