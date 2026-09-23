import sys
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r'C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities')
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected Studio ID:", client.studio_id)

dump_dir = r"C:\Users\User\.gemini\antigravity\scratch\studio_pull_20260922"
os.makedirs(dump_dir, exist_ok=True)

# First get list of all scripts with their FullName and ClassName
list_script = """
local HttpService = game:GetService("HttpService")
local list = {}
local function scan(container)
    if not container then return end
    for _, child in ipairs(container:GetDescendants()) do
        if child:IsA("LuaSourceContainer") then
            table.insert(list, {
                FullName = child:GetFullName(),
                ClassName = child.ClassName,
                Name = child.Name
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

return HttpService:JSONEncode(list)
"""

res = client.execute_luau(list_script)
raw = res.get("result", {}).get("content", [{}])[0].get("text", "")
scripts = json.loads(raw)
print(f"Total scripts to pull from Studio: {len(scripts)}")

pulled = 0
for i, s in enumerate(scripts):
    fullname = s["FullName"]
    # Fetch source individually using Luau
    fetch_lua = f"""
    local obj = game
    for part in string.gmatch("{fullname}", "[^.]+") do
        if part ~= "game" then
            obj = obj:FindFirstChild(part)
            if not obj then return nil end
        end
    end
    return obj and obj.Source or ""
    """
    res_src = client.execute_luau(fetch_lua)
    src = res_src.get("result", {}).get("content", [{}])[0].get("text", "")
    
    # Clean up StudioMCP prefix if any
    clean_path = fullname.replace(".", "/")
    target_file = os.path.join(dump_dir, clean_path + (".server.lua" if s["ClassName"] == "Script" else (".client.lua" if s["ClassName"] == "LocalScript" else ".lua")))
    os.makedirs(os.path.dirname(target_file), exist_ok=True)
    with open(target_file, "w", encoding="utf-8") as f:
        f.write(src)
    pulled += 1
    if (i + 1) % 10 == 0 or (i + 1) == len(scripts):
        print(f"Pulled {pulled}/{len(scripts)}: {fullname}")

print("\nSuccessfully pulled all Studio scripts to:", dump_dir)
