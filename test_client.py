from Tools.Utilities.roblox_client import RobloxStudioClient
c = RobloxStudioClient()
print("Studio ID:", c.studio_id)
print("Execute:", c.execute_luau('return "STUDIO_ONLINE"', 'Edit'))
c.close()
