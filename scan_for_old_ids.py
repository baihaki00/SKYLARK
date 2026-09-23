import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

search_code = """
local old_ids = {
    "100922149573976",
    "114785605157270",
    "85211470256307",
    "77612374182353",
    "77252436211913",
    "133934970513206",
}

local matches = {}

local function check_string(val, path, desc)
    if type(val) == "string" then
        for _, id in ipairs(old_ids) do
            if string.find(val, id) then
                table.insert(matches, {path = path, desc = desc, id = id, val = val})
            end
        end
    end
end

local function scan(root, root_name)
    for _, desc in ipairs(root:GetDescendants()) do
        local p = desc:GetFullName()
        if desc:IsA("StringValue") then
            check_string(desc.Value, p, "StringValue.Value")
        elseif desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
            check_string(desc.Text, p, desc.ClassName .. ".Text")
        elseif desc:IsA("Animation") then
            check_string(desc.AnimationId, p, "Animation.AnimationId")
        elseif desc:IsA("LuaSourceContainer") then
            pcall(function()
                check_string(desc.Source, p, "Script.Source")
            end)
        end
        -- check attributes
        for k, v in pairs(desc:GetAttributes()) do
            if type(v) == "string" then
                check_string(v, p, "Attribute:" .. k)
            end
        end
    end
end

scan(game, "game")
local HttpService = game:GetService("HttpService")
return HttpService:JSONEncode(matches)
"""

print("Scanning Client...")
res_c = client.execute_luau(search_code, datamodel_type="Client")
print("Client Matches:", res_c)

print("Scanning Server...")
res_s = client.execute_luau(search_code, datamodel_type="Server")
print("Server Matches:", res_s)
