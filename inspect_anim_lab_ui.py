import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local pg = lp:FindFirstChild("PlayerGui")
local anim_ui = pg:FindFirstChild("AnimationLabUI")
if not anim_ui then return "No AnimationLabUI" end

local text_elements = {}
for _, desc in ipairs(anim_ui:GetDescendants()) do
    if desc:IsA("TextBox") or desc:IsA("TextLabel") or desc:IsA("TextButton") then
        table.insert(text_elements, {
            class = desc.ClassName,
            name = desc.Name,
            parent = desc.Parent and desc.Parent.Name,
            text = desc.Text,
            visible = (desc:IsA("GuiObject") and desc.Visible)
        })
    end
end

local HttpService = game:GetService("HttpService")
return HttpService:JSONEncode(text_elements)
"""

res = client.execute_luau(code, datamodel_type="Client")
text_content = res.get("result", {}).get("content", [{}])[0].get("text", "")

with open(r"C:\Users\User\.gemini\antigravity\scratch\anim_lab_ui_elements.json", "w", encoding="utf-8") as f:
    f.write(text_content)

print("Saved elements, total length:", len(text_content))
data = json.loads(text_content)
for el in data:
    if "100922149573976" in el["text"] or "77612374182353" in el["text"] or "107962284182266" in el["text"] or "Strafe" in el["text"] or "ID" in el["text"]:
        print(el)
