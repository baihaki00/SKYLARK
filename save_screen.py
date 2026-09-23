from Tools.Utilities.roblox_client import RobloxStudioClient
import base64
import os

client = RobloxStudioClient()
res = client.call_tool("screen_capture", {"studio_id": client.studio_id, "capture_id": "screen_1"})
for item in res.get("result", {}).get("content", []):
    if item.get("type") == "image":
        img_b64 = item.get("data")
        out_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_live_studio.png"
        with open(out_path, "wb") as f:
            f.write(base64.b64decode(img_b64))
        print("Saved screen capture to:", out_path)
client.close()
