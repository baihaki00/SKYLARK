import os
import sys
import base64

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

client = RobloxStudioClient()
cap_res = client.call_tool("screen_capture", {
    "studio_id": client.studio_id,
    "capture_id": "screen_capture_survival_decision_verified",
    "camera_position": {"x": 20, "y": 18, "z": -25},
    "look_at_position": {"x": 0, "y": 2, "z": 0}
})
print("Cap res keys:", cap_res.keys())
content = cap_res.get("result", {}).get("content", [])
print("Content len:", len(content))
for item in content:
    print("Item type:", item.get("type"))
    if item.get("type") == "image":
        img_data = item.get("data", "")
        fpath = os.path.join(ARTIFACT_DIR, "screen_capture_survival_decision_verified.png")
        with open(fpath, "wb") as f:
            f.write(base64.b64decode(img_data))
        print("Saved to", fpath, "bytes:", len(img_data))
