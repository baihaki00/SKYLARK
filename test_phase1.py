import os
import sys
import time

current_dir = os.path.dirname(os.path.abspath(__file__))
tools_dir = os.path.join(current_dir, "Tools", "Utilities")
if tools_dir not in sys.path:
    sys.path.insert(0, tools_dir)

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

from roblox_client import RobloxStudioClient

def test_phase1():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    code = """
    local CollectionService = game:GetService("CollectionService")
    local quins = CollectionService:GetTagged("Quin")
    
    local stateCounts = {}
    local speedSamples = {}
    local transitionTraces = {}

    for _, q in ipairs(quins) do
        local st = q:GetAttribute("CurrentState") or "None"
        stateCounts[st] = (stateCounts[st] or 0) + 1

        local hum = q:FindFirstChildOfClass("Humanoid")
        if hum and #speedSamples < 12 then
            table.insert(speedSamples, string.format("%s: Spd=%.1f State=%s", q.Name, hum.WalkSpeed, st))
        end

        local tl = q:GetAttribute("TraceLog") or ""
        if string.find(tl, "TargetTransition") or string.find(tl, "Transition:") then
            table.insert(transitionTraces, string.format("[%s]: %s", q.Name, string.gsub(tl, "\\n", " | ")))
        end
    end

    local summaryParts = {}
    for k, v in pairs(stateCounts) do
        table.insert(summaryParts, k .. "=" .. tostring(v))
    end

    return string.format("Total Quins: %d\\nStates: %s\\nSpeed Samples:\\n  %s\\nTransition Traces (%d recorded):\\n  %s",
        #quins,
        table.concat(summaryParts, ", "),
        table.concat(speedSamples, "\\n  "),
        #transitionTraces,
        table.concat(transitionTraces, "\\n  ")
    )
    """

    res = client.execute_luau(code, datamodel_type="Server")
    text = res.get("result", {}).get("content", [{}])[0].get("text", "")
    print("--- LIVE PHASE 1 TELEMETRY ---")
    print(text)
    client.close()

if __name__ == "__main__":
    test_phase1()
