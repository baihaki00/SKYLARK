import os
import sys
import base64
import json

sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

client = RobloxStudioClient()
code = """
local qServer = workspace:FindFirstChild("QuinServer")
local quins = qServer and qServer:GetChildren() or {}
local pos = nil
for _, q in ipairs(quins) do
    if q:FindFirstChild("HumanoidRootPart") then
        local p = q.HumanoidRootPart.Position
        pos = {p.X, p.Y, p.Z}
        break
    end
end
return game:GetService("HttpService"):JSONEncode(pos)
"""
res = client.execute_luau(code, datamodel_type="Server")
pos = json.loads(res.get("result", {}).get("content", [{}])[0].get("text", "null"))
print("Target Quin Position:", pos)

if pos:
    cam_pos = [pos[0] - 12, pos[1] + 5, pos[2] - 12]
    look_at = [pos[0], pos[1] + 2.5, pos[2]]

    cap_res = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "ScreenCapture_GhostFixed_CloseUp",
        "camera_position": cam_pos,
        "look_at_position": look_at
    })

    filepath = os.path.join(ARTIFACT_DIR, "screen_capture_ghost_fixed_closeup.png")
    if cap_res and not cap_res.get("isError", False):
        content = cap_res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(filepath, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved close-up screenshot to {filepath} ({len(img_data)} bytes)")
                break

client.close()
