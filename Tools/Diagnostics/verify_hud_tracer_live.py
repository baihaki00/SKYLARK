import os
import sys
import json
import time

sys.stdout.reconfigure(encoding='utf-8')

util_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities"))
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

def verify_live_hud_tracer():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Launch 1v1 match via Client RemoteEvent
    launch_code = """
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
    local Events = QuinCore:WaitForChild("Events")
    local labEvent = Events:WaitForChild("AnimationLabEvent")
    labEvent:FireServer("SetGameMode", { mode = "1v1" })
    return "1v1 Match Launched"
    """
    res_launch = client.execute_luau(launch_code, "Client")
    print("Launch status:", res_launch.get("result", {}).get("content", [{}])[0].get("text", ""))

    print("Waiting 4.5s for countdown (3.. 2.. 1.. FIGHT!)...")
    time.sleep(4.5)

    # 2. Select first active arena Quin as spectated to test expanded card rendering
    select_code = """
    local Workspace = game:GetService("Workspace")
    local qServer = Workspace:FindFirstChild("QuinServer")
    if qServer then
        local children = qServer:GetChildren()
        if #children > 0 then
            local targetName = children[1].Name
            Workspace:SetAttribute("SpectatedQuin", targetName)
            shared.SpectatedQuin = children[1]
            return "Spectating: " .. targetName
        end
    end
    return "No Quins found in QuinServer"
    """
    res_select = client.execute_luau(select_code, "Client")
    print("Spectator selection:", res_select.get("result", {}).get("content", [{}])[0].get("text", ""))

    # 3. Sample live combat telemetry on the client: check HUD card label and model attributes
    sample_code = """
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local player = Players.LocalPlayer
    local pGui = player:FindFirstChild("PlayerGui")
    local debugGui = pGui and pGui:FindFirstChild("QuinDebugGui")
    local scrollFrame = debugGui and debugGui:FindFirstChild("Frame") and debugGui.Frame:FindFirstChild("ScrollingFrame")

    local report = {
        cards = {},
        models = {}
    }

    if scrollFrame then
        for _, child in ipairs(scrollFrame:GetChildren()) do
            if child:IsA("TextButton") then
                local label = child:FindFirstChildOfClass("TextLabel")
                table.insert(report.cards, {
                    name = child.Name,
                    size = string.format("%dx%d", child.AbsoluteSize.X, child.AbsoluteSize.Y),
                    text = label and label.Text or "N/A"
                })
            end
        end
    end

    local qServer = Workspace:FindFirstChild("QuinServer")
    if qServer then
        for _, m in ipairs(qServer:GetChildren()) do
            if m:IsA("Model") then
                table.insert(report.models, {
                    name = m.Name,
                    state = m:GetAttribute("CurrentState"),
                    breadcrumb = m:GetAttribute("TraceBreadcrumb"),
                    traceLog = m:GetAttribute("TraceLog"),
                    lastTraceTime = m:GetAttribute("LastTraceTime")
                })
            end
        end
    end

    return report
    """

    print("Sampling live HUD card presentation over 6 iterations (3.6 seconds)...")
    for i in range(6):
        time.sleep(0.6)
        res = client.execute_luau(sample_code, "Client")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"\n--- SAMPLE {i+1} ---")
        try:
            data = json.loads(txt)
            raw_models = data.get("models", [])
            models = list(raw_models.values()) if isinstance(raw_models, dict) else raw_models
            raw_cards = data.get("cards", [])
            cards = list(raw_cards.values()) if isinstance(raw_cards, dict) else raw_cards

            print(f"Active Models in QuinServer: {len(models)}")
            for m in models:
                if isinstance(m, dict):
                    print(f"  Model [{m.get('name')}]: State={m.get('state')} | LastTime={m.get('lastTraceTime')}")
                    print(f"    Breadcrumb: {m.get('breadcrumb')}")
                    print(f"    TraceLog:\n{m.get('traceLog')}")

            print(f"Active HUD Cards Rendered: {len(cards)}")
            for c in cards:
                if isinstance(c, dict):
                    print(f"  Card [{c.get('name')}] Size: {c.get('size')}")
                    print(f"    Text:\n{c.get('text')}\n")
        except Exception as e:
            print("Parse Error:", e)
            print("Raw text:", txt)

    # 4. Clean arena
    clear_code = """
    local SSS = game:GetService("ServerScriptService")
    local Spawner = require(SSS:WaitForChild("QuinSpawner"))
    Spawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)
    workspace:SetAttribute("CurrentMode", "None")
    workspace:SetAttribute("SpectatedQuin", "")
    return "Arena Cleaned"
    """
    client.execute_luau(clear_code, "Server")
    print("Arena cleaned.")
    client.close()

if __name__ == "__main__":
    verify_live_hud_tracer()
