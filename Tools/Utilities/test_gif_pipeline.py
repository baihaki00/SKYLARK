import os
import sys
import time
import base64
import io
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "Tools", "Utilities"))
from roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

client = RobloxStudioClient()

# 1. Query Quins positions
query_code = """
local CollectionService = game:GetService("CollectionService")
local quins = CollectionService:GetTagged("Quin")
if #quins == 0 then return "{}" end

local HttpService = game:GetService("HttpService")
local data = {}
for _, q in ipairs(quins) do
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then
        table.insert(data, {
            name = q.Name,
            state = q:GetAttribute("CurrentState") or "None",
            target = q:GetAttribute("CurrentTarget") or "None",
            pos = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
            vel = hrp.AssemblyLinearVelocity.Magnitude
        })
    end
end
return HttpService:JSONEncode(data)
"""

res = client.execute_luau(query_code, datamodel_type="Server")
import json
txt = res.get("result", {}).get("content", [{}])[0].get("text", "[]")
try:
    quins_data = json.loads(txt)
except Exception:
    quins_data = []

print("Found active quins:", len(quins_data))

# Determine focus point
if len(quins_data) >= 2:
    p1 = quins_data[0]["pos"]
    p2 = quins_data[1]["pos"]
    mid = [(p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, (p1[2] + p2[2]) / 2]
    cam = [mid[0] + 16, mid[1] + 8, mid[2] + 20]
    look = [mid[0], mid[1] + 3, mid[2]]
elif len(quins_data) == 1:
    p1 = quins_data[0]["pos"]
    cam = [p1[0] + 15, p1[1] + 7, p1[2] + 18]
    look = [p1[0], p1[1] + 3, p1[2]]
else:
    cam = [0, 15, -30]
    look = [0, 5, 0]

print("Camera Position:", cam)
print("Look At:", look)

# Capture 4 frames
frames = []
for i in range(4):
    res_cap = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": f"burst_frame_{i}",
        "camera_position": cam,
        "look_at_position": look
    })
    items = res_cap.get("result", {}).get("content", [])
    for item in items:
        if item.get("type") == "image":
            img_bytes = base64.b64decode(item["data"])
            img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
            # Stamp frame index
            draw = ImageDraw.Draw(img)
            draw.rectangle([10, 10, 260, 45], fill=(0, 0, 0, 180))
            draw.text((20, 18), f"Frame {i+1} | T+{i*0.35:.2f}s", fill=(255, 255, 0))
            frames.append(img)
            print(f"Captured frame {i+1} ({img.width}x{img.height})")
            break
    time.sleep(0.1)

if frames:
    # 1. Save animated GIF
    gif_path = os.path.join(ARTIFACT_DIR, "test_action_moment.gif")
    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=350,
        loop=0
    )
    print("Saved animated GIF to:", gif_path, f"({os.path.getsize(gif_path)} bytes)")

    # 2. Save 2x2 or 1x4 Contact Sheet Filmstrip
    w, h = frames[0].size
    scale = 0.5
    thumb_w, thumb_h = int(w * scale), int(h * scale)
    contact_sheet = Image.new("RGB", (thumb_w * 4, thumb_h), (20, 20, 20))
    for idx, f in enumerate(frames):
        thumb = f.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        contact_sheet.paste(thumb, (idx * thumb_w, 0))
    
    strip_path = os.path.join(ARTIFACT_DIR, "test_action_filmstrip.png")
    contact_sheet.save(strip_path)
    print("Saved filmstrip to:", strip_path, f"({os.path.getsize(strip_path)} bytes)")
