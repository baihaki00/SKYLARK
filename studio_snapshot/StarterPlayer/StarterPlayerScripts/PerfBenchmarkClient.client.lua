--// PerfBenchmarkClient.client.lua
-- This machine's half of the performance benchmark (ServerScriptService.PerfBenchmark; Quin
-- Manager > TEST MODES > Performance Benchmark; SKYLARK_PERFORMANCE_PLAN.md step A).
-- While Workspace.BenchRunning is set:
--   - the camera is held on one fixed wide view of the arena (the same every run);
--   - the frames are measured over the same two windows as the server: START (0-12 s: spawn,
--     dressing, countdown) and STEADY (12-32 s: the fight);
--   - in the STEADY window the server's scripts are profiled (ScriptProfilerService) where this
--     machine may (plugins only today; otherwise F9 > Script Profiler shows the same);
--   - variant "noclothes" / "bare": every clothing wrap is switched off for the run (and back on
--     after).
-- Then a panel shows this run beside the earlier ones, with buttons to run each variant again.
-- Also printed to Output ("[Benchmark] ...") and kept in player attribute BenchResult (JSON).
-- Read the numbers knowing:
--   - in Studio Play the server runs on this PC too, so the fps here include its cost (Team Test
--     gives a real player's numbers);
--   - Studio slows itself down when it is not the focused window: a run that lost focus is
--     marked UNRELIABLE.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local START_WINDOW = 12
local STEADY_WINDOW = 20
local CAMERA_EYE = Vector3.new(0, 140, -178) -- (over the stands, looking at the arena centre)
local CAMERA_AT = Vector3.new(0, 0, -438)
local TOP_SCRIPTS = 8
local VARIANTS = {
    { key = "full", label = "Full" },
    { key = "nocrowd", label = "No crowd" },
    { key = "noclothes", label = "No clothes" },
    { key = "bare", label = "Bare" },
}

local history = {} -- earlier runs this session, newest last
local running = false
local holdOff = false -- (clothes held off for a "noclothes" / "bare" run)
local focused = true
UserInputService.WindowFocused:Connect(function()
    focused = true
end)
UserInputService.WindowFocusReleased:Connect(function()
    focused = false
end)

local function allowed()
    return player:GetAttribute("SkylarkCanAdmin") == true or RunService:IsStudio()
end

-- ===================== the panel =====================

local gui = Instance.new("ScreenGui")
gui.Name = "PerfBenchmarkUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 90
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(470, 520)
panel.Position = UDim2.new(1, -490, 0, 80)
panel.BackgroundColor3 = Color3.fromRGB(14, 18, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(255, 120, 60)
stroke.Transparency = 0.3

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 0, 30)
title.Position = UDim2.fromOffset(14, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 170, 110)
title.Text = "PERFORMANCE BENCHMARK"
title.Parent = panel

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(30, 26)
close.Position = UDim2.new(1, -40, 0, 10)
close.BackgroundColor3 = Color3.fromRGB(40, 46, 60)
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 13
close.Text = "X"
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)
close.MouseButton1Click:Connect(function()
    gui.Enabled = false
end)

local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -28, 1, -100)
body.Position = UDim2.fromOffset(14, 42)
body.BackgroundTransparency = 1
body.Font = Enum.Font.Code
body.TextSize = 13
body.RichText = true
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextColor3 = Color3.fromRGB(225, 232, 245)
body.Text = ""
body.Parent = panel

local labEvent = nil
local function runVariant(key)
    labEvent = labEvent or ReplicatedStorage:FindFirstChild("AnimationLabEvent", true)
    if labEvent then
        labEvent:FireServer("SetTestMode", { mode = "Benchmark", variant = key })
    end
end
for i, v in ipairs(VARIANTS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.25, -8, 0, 34)
    b.Position = UDim2.new((i - 1) * 0.25, 4 + (i == 1 and 6 or 0), 1, -46)
    b.BackgroundColor3 = i == 1 and Color3.fromRGB(255, 120, 60) or Color3.fromRGB(44, 52, 70)
    b.TextColor3 = i == 1 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = "Run: " .. v.label
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        if not running then
            runVariant(v.key)
        end
    end)
end
shared.RunPerfBenchmark = runVariant

-- ===================== measuring =====================

local function window(seconds, label)
    local dts, cpu, gpu = {}, 0, 0
    local t0 = os.clock()
    local lostFocus = not focused
    while os.clock() - t0 < seconds and Workspace:GetAttribute("BenchRunning") do
        local dt = RunService.RenderStepped:Wait()
        table.insert(dts, dt)
        cpu += Stats.RenderCPUFrameTime
        gpu += Stats.RenderGPUFrameTime
        lostFocus = lostFocus or not focused
        body.Text = ("Running <b>%s</b>: %s window %d / %d s\n\nKeep Studio focused, don't touch the camera."):format(
            tostring(Workspace:GetAttribute("BenchVariant")), label, math.floor(os.clock() - t0), seconds)
    end
    local n = math.max(1, #dts)
    local total = 0
    for _, dt in ipairs(dts) do
        total += dt
    end
    table.sort(dts, function(a, b)
        return a > b
    end)
    local worstShare = math.max(1, math.floor(n * 0.01))
    local worstSum = 0
    for i = 1, worstShare do
        worstSum += dts[i] or 0
    end
    return {
        fps = math.floor(n / math.max(0.001, total) + 0.5),
        low1 = math.floor(worstShare / math.max(0.001, worstSum) + 0.5),
        p95 = math.floor((dts[math.max(1, math.floor(n * 0.05))] or 0) * 1000 + 0.5),
        worst = math.floor((dts[1] or 0) * 1000 + 0.5),
        cpu = math.floor(cpu / n * 10000 + 0.5) / 10,
        gpu = math.floor(gpu / n * 10000 + 0.5) / 10,
        lostFocus = lostFocus,
    }
end

-- the server's heaviest script functions over the STEADY window (ms of server time per second)
local profiler = nil
local function startProfile()
    local ok, sps = pcall(function()
        return game:GetService("ScriptProfilerService")
    end)
    if not ok or not sps then
        return nil
    end
    local state = { sps = sps }
    -- (game scripts may not use the profiler: "lacking capability Plugin". Then there is no list;
    -- the same data is in the Developer Console, F9 > Script Profiler, or from the Studio MCP.)
    if not pcall(function()
        state.con = sps.OnNewData:Connect(function(_, json)
            state.json = json
        end)
    end) then
        return nil
    end
    if not pcall(function()
        sps:ServerStart(1000)
    end) then
        state.con:Disconnect()
        return nil
    end
    return state
end

local function stopProfile(state)
    if not state then
        return nil
    end
    pcall(function()
        state.sps:ServerStop()
        state.sps:ServerRequestData()
    end)
    local t0 = os.clock()
    while not state.json and os.clock() - t0 < 4 do
        task.wait(0.1)
    end
    state.con:Disconnect()
    if not state.json then
        return nil
    end
    local ok, data = pcall(function()
        return state.sps:DeserializeJSON(state.json)
    end)
    if not ok or type(data) ~= "table" or not data.Functions then
        return nil
    end
    local span = math.max(1, (data.SessionEndTime or 1) - (data.SessionStartTime or 0)) / 1000 -- (s)
    local list = {}
    for _, f in ipairs(data.Functions) do
        local name = tostring(f.Name or "?")
        local source = tostring(f.Source or ""):gsub("^.*%.", "")
        -- (skip the wrappers every script runs inside: they would top the list and say nothing)
        local wrapper = name == "Main" or name == "pcall" or source == "[C]" and name:find("^pcall")
        if not wrapper and f.TotalDuration then
            table.insert(list, {
                label = (name == "nil" and "(anon)" or name) .. "  " .. source .. ":" .. tostring(f.Line or 0),
                msPerSec = f.TotalDuration * 1000 / span,
            })
        end
    end
    table.sort(list, function(a, b)
        return a.msPerSec > b.msPerSec
    end)
    local top = {}
    for i = 1, math.min(TOP_SCRIPTS, #list) do
        top[i] = list[i]
    end
    return top
end

local function wraps(on)
    local folder = Workspace:FindFirstChild("QuinServer")
    for _, d in ipairs(folder and folder:GetDescendants() or {}) do
        if d:IsA("WrapLayer") and d.Enabled ~= on then
            d.Enabled = on
        end
    end
end

-- ===================== the report =====================

local function fmtWindow(w)
    return ("%3d fps  1%%low %3d  p95 %3d ms  worst %3d ms\n       render CPU %4.1f ms  GPU %4.1f ms"):format(
        w.fps, w.low1, w.p95, w.worst, w.cpu, w.gpu)
end

local function render(result)
    local lines = {}
    local function add(s)
        table.insert(lines, s)
    end
    local ok = result.steady.fps >= 60
    add(("<b>%s</b>   run %d   %s"):format(result.variant, result.run,
        ok and '<font color="#7CFF9A">STEADY 60+</font>' or '<font color="#FF8A7A">STEADY UNDER 60</font>'))
    if result.unreliable then
        add('<font color="#FFC857">UNRELIABLE: Studio lost focus during the run</font>')
    end
    add("")
    add("<b>THIS MACHINE</b>")
    add("START  " .. fmtWindow(result.start))
    add("STEADY " .. fmtWindow(result.steady))
    local s = result.server
    if s then
        add("")
        add("<b>SERVER</b>  (60 Hz is full speed)")
        add(("START  %2d Hz  p95 %d ms\nSTEADY %2d Hz  p95 %d ms  Lua %.1f ms  physics %.1f ms  (%d alive)"):format(
            s.start.hz, s.start.p95, s.steady.hz, s.steady.p95, s.steady.heartbeatMs, s.steady.physicsMs, s.alive or 0))
    else
        add("")
        add("SERVER: no numbers (the run was cut short?)")
    end
    if not (result.top and #result.top > 0) then
        add("")
        add('<font color="#9AA7BD">Heaviest server scripts: F9 > Script Profiler (Server) during a run.</font>')
    end
    if result.top and #result.top > 0 then
        add("")
        add("<b>HEAVIEST SERVER SCRIPTS</b> (ms per second)")
        for _, f in ipairs(result.top) do
            add(("%6.1f  %s"):format(f.msPerSec, f.label:sub(1, 44)))
        end
    end
    if #history > 1 then
        add("")
        add("<b>EARLIER RUNS</b> (steady fps / server Hz)")
        for i = math.max(1, #history - 4), #history - 1 do
            local h = history[i]
            add(("run %d  %-9s %3d fps  %s Hz"):format(h.run, h.variant, h.steady.fps,
                h.server and tostring(h.server.steady.hz) or "?"))
        end
    end
    if RunService:IsStudio() then
        add("")
        add('<font color="#9AA7BD">Studio Play: the server runs on this PC, in step with these frames, so its Hz just follows the fps here and the fps include its cost. Read the server by its Lua ms; Team Test gives a real player\'s fps.</font>')
    end
    body.Text = table.concat(lines, "\n")
end

local function runInner()
    if running or not allowed() then
        return
    end
    running = true
    gui.Enabled = true
    local variant = Workspace:GetAttribute("BenchVariant") or "full"
    local noClothes = variant == "noclothes" or variant == "bare"
    local camera = Workspace.CurrentCamera
    local prevType = camera.CameraType
    RunService:BindToRenderStep("PerfBenchmarkCamera", Enum.RenderPriority.Last.Value + 60, function()
        local cam = Workspace.CurrentCamera
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(CAMERA_EYE, CAMERA_AT)
    end)
    holdOff = noClothes
    if noClothes then
        task.spawn(function()
            while holdOff do
                wraps(false) -- (Quins dressed after the start are caught too; not every frame: the scan costs)
                task.wait(0.5)
            end
        end)
    end

    local startW = window(START_WINDOW, "START")
    profiler = startProfile()
    local steadyW = window(STEADY_WINDOW, "STEADY")
    local top = stopProfile(profiler)
    profiler = nil

    RunService:UnbindFromRenderStep("PerfBenchmarkCamera")
    camera.CameraType = prevType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or prevType
    holdOff = false
    if noClothes then
        wraps(true)
    end

    -- the server's numbers arrive when its STEADY window closes
    local t0 = os.clock()
    while not Workspace:GetAttribute("BenchServer") and os.clock() - t0 < 6 do
        task.wait(0.2)
    end
    local server = nil
    pcall(function()
        server = HttpService:JSONDecode(Workspace:GetAttribute("BenchServer"))
    end)

    local result = {
        run = Workspace:GetAttribute("BenchRun") or 0,
        variant = variant,
        start = startW,
        steady = steadyW,
        server = server,
        top = top,
        unreliable = startW.lostFocus or steadyW.lostFocus,
    }
    table.insert(history, result)
    render(result)
    player:SetAttribute("BenchResult", HttpService:JSONEncode(result))
    print(("[Benchmark] client %s: start %d fps (1%% low %d), steady %d fps (1%% low %d, p95 %d ms, render CPU %.1f ms, GPU %.1f ms)%s"):format(
        variant, startW.fps, startW.low1, steadyW.fps, steadyW.low1, steadyW.p95, steadyW.cpu, steadyW.gpu,
        result.unreliable and " UNRELIABLE (focus lost)" or ""))
    running = false
end

-- (an error mid-run must not leave the camera held or the buttons locked)
local function run()
    local ok, err = pcall(runInner)
    if not ok then
        warn("[Benchmark] client run failed: " .. tostring(err))
        RunService:UnbindFromRenderStep("PerfBenchmarkCamera")
        Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        holdOff = false
        wraps(true)
        body.Text = "Run failed: " .. tostring(err)
        running = false
    end
end

Workspace:GetAttributeChangedSignal("BenchRunning"):Connect(function()
    if Workspace:GetAttribute("BenchRunning") then
        task.spawn(run)
    end
end)
