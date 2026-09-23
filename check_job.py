from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
res = client.call_tool("wait_job_finished", {"studio_id": client.studio_id})
print("wait_job_finished:", res)
client.close()
