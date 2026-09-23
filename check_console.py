from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
res = client.call_tool("get_console_output", {"studio_id": client.studio_id})
print("Console output:")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
client.close()
