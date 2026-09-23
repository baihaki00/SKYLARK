from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
tools = client.call_tool("tools/list", {})
for t in tools.get("result", {}).get("tools", []):
    if t.get("name") in ["start_stop_play", "user_keyboard_input"]:
        print(json.dumps(t, indent=2))
client.close()
