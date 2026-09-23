import sys
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected to studio:", client.studio_id)

for dm in ["Edit", "Server", "Client"]:
    try:
        res = client.execute_luau('return game:GetService("RunService"):IsRunning()', datamodel_type=dm)
        print(f"[{dm}] IsRunning: {res}")
    except Exception as e:
        print(f"[{dm}] Error: {e}")
