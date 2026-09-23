from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local rs = game:GetService("ReplicatedStorage")
local cmd = rs:WaitForChild("GameCommand", 5)
if cmd then
    cmd:FireServer("team", 16)
    return "Fired GameCommand team 16 from Client!"
else
    return "GameCommand not found in ReplicatedStorage"
end
"""
res = c.execute_luau(code, "Client")
print("Client command result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
