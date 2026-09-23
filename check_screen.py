from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
res = client.call_tool("screen_capture", {"studio_id": client.studio_id, "capture_id": "screen_1"})
print("Screen capture keys:", res.keys())
if "result" in res:
    for item in res["result"].get("content", []):
        if item.get("type") == "image":
            print("Received image data!")
        else:
            print("Item:", item)
client.close()
