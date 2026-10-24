--// QuinCare.lua
-- Looking after a Quin between fights (SKYLARK_ECONOMY_DESIGN.md, step 3). Everything here is on
-- the server and runs on Skylark time (SkylarkTime.now; a Skylark hour is 20 real minutes):
--   * Condition 0..100, saved on the Quin. A match takes it down by the damage taken (a full
--     beating -25, knocked out -15 more). A worn Quin fights worn: its max health and its energy
--     are capped at 75% + 25% x condition (applyToModel).
--   * Rest (free): +REST_PER_HOUR a Skylark hour while it is not busy, also while its owner is
--     offline (worked out from ConditionAt when it is next looked at).
--   * Workshop repair (SC): REPAIR_PER_POINT a point, back to 100 after REPAIR_HOURS.
--   * Quin Trainer: a session on one habit, up or down (Temperament.applyMatch with the owner's
--     TrainingFocus, so the 1:3 protects it from fights), Short / Normal / Long; it wears the Quin
--     (TRAIN_WEAR) and grows Bond. Bond makes training count for more.
--   * Quin Specialist: appraisal, each habit as Low / Mid / High at that moment (goes stale as the
--     habits drift). Fights reveal the habits a Quin shows most for free, from REVEAL_FIGHTS on.
--   * A busy Quin (repair, training) can't be seated for a round (ArenaRegistration).
-- Remote: ArenaNetwork.QuinCare (RemoteFunction) "list" | "repair", slot | "train", slot, habit,
-- dir, session | "appraise", slot. Each action needs its station close by (STATION_RANGE).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local PersonalitySystem = require(QuinCore.Modules:WaitForChild("PersonalitySystem"))
local Temperament = require(QuinCore.Modules:WaitForChild("Temperament"))
local QuinDataStoreService = require(QuinCore.Modules:WaitForChild("QuinDataStoreService"))
local Wallet = require(ServerScriptService:WaitForChild("SkylarkWallet"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))

local Care = {}

Care.REST_PER_HOUR = 5
Care.REPAIR_PER_POINT = 2
Care.REPAIR_HOURS = 0.5
Care.TRAIN_WEAR = 5
Care.APPRAISE_COST = 150
Care.REVEAL_FIGHTS = 10
Care.STATION_RANGE = 14
Care.SESSIONS = {
    Short = { hours = 1, cost = 100, step = 0.01 },
    Normal = { hours = 2, cost = 180, step = 0.02 },
    Long = { hours = 4, cost = 320, step = 0.04 },
}
Care.HABIT_NAMES = {
    Aggression = "Aggression", RiskTolerance = "Risk", DashPreference = "Dash", RetreatTendency = "Retreat",
    TargetPersistence = "Focus", Protectiveness = "Protect", MobilityPreference = "Mobility",
    SpecialPreference = "Special", Confidence = "Confidence", Awareness = "Awareness",
}

local HOUR = SkylarkTime.HOUR

-- ============================================================================
-- CONDITION, BUSY, BOND
-- ============================================================================

local function now()
    return SkylarkTime.now()
end

local function band(v)
    return v < 0.4 and "Low" or (v > 0.65 and "High" or "Mid")
end

local function markDirty(quin)
    local _, userId = QuinDataStoreService.findQuinById(quin.QuinId)
    if userId and QuinDataStoreService.markDirty then
        QuinDataStoreService.markDirty(userId)
    end
end

-- Finish a repair or a training session whose time is up. Returns a line for the owner, or nil.
local function finishBusy(quin)
    local busy = quin.Busy
    if not busy or now() < busy.Until then
        return nil
    end
    quin.Busy = nil
    quin.ConditionAt = busy.Until -- (rest starts from when the work ended)
    local tag = quin.QuinId:sub(3, 6)
    if busy.Kind == "Repair" then
        quin.Condition = 100
        return string.format("Quin #%s is repaired: condition 100%%.", tag)
    elseif busy.Kind == "Training" then
        local session = Care.SESSIONS[busy.Session] or Care.SESSIONS.Short
        local bondFactor = 0.6 + 0.4 * math.clamp((quin.Bond or 0) / 100, 0, 1)
        local before = quin.Personality[busy.Habit] or 0.5
        quin.TrainingFocus = quin.TrainingFocus or {}
        quin.TrainingFocus[busy.Habit] = busy.Dir
        local step = session.step * bondFactor * busy.Dir
        Temperament.applyMatch(quin, { [busy.Habit] = step }, PersonalitySystem.typeBounds(quin.Type), math.abs(step))
        quin.Bond = math.min(100, (quin.Bond or 0) + 3)
        local after = quin.Personality[busy.Habit] or before
        return string.format("Quin #%s finished training: %s %d -> %d.", tag, Care.HABIT_NAMES[busy.Habit] or busy.Habit,
            math.floor(before * 100 + 0.5), math.floor(after * 100 + 0.5))
    end
    return nil
end

-- Bring a Quin up to date (finished work, rest since last time). Returns a finished-work line or nil.
function Care.settle(quin)
    if not quin then
        return nil
    end
    local line = finishBusy(quin)
    local t = now()
    if quin.Condition == nil then
        quin.Condition, quin.ConditionAt = 100, t
    end
    if not quin.Busy then
        local at = quin.ConditionAt or t
        if t > at and quin.Condition < 100 then
            quin.Condition = math.min(100, quin.Condition + Care.REST_PER_HOUR * (t - at) / HOUR)
        end
        quin.ConditionAt = t
    end
    if line then
        markDirty(quin)
    end
    return line
end

function Care.condition(quin)
    Care.settle(quin)
    return quin.Condition or 100
end

function Care.isBusy(quin)
    Care.settle(quin)
    return quin.Busy ~= nil
end

function Care.factor(conditionValue)
    return 0.75 + 0.25 * math.clamp((conditionValue or 100) / 100, 0, 1)
end

-- A worn Quin fights worn: max health now, energy capped by the loop below
function Care.applyToModel(quin, model)
    if not (quin and model) or quin.Condition == nil then
        return
    end
    local c = Care.condition(quin)
    local f = Care.factor(c)
    model:SetAttribute("Condition", math.floor(c + 0.5))
    model:SetAttribute("ConditionFactor", f)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and f < 1 then
        hum.MaxHealth = math.floor(hum.MaxHealth * f)
        hum.Health = hum.MaxHealth
    end
    -- (energy is read from CombatConfig.MaxEnergy all over the combat code: a worn Quin's cap is held here)
    if f < 1 then
        local cap = 100 * f
        local function hold()
            local e = model:GetAttribute("Energy")
            if e and e > cap then
                model:SetAttribute("Energy", cap)
            end
        end
        model:GetAttributeChangedSignal("Energy"):Connect(hold)
        hold()
    end
end

-- After a match: the damage it took comes off its condition; a fight together grows Bond a little.
-- Returns condition before, after.
function Care.afterMatch(quin, taken, maxHealth, knockedOut)
    local before = Care.condition(quin)
    local loss = 25 * math.clamp((taken or 0) / math.max(1, maxHealth or 1000), 0, 1) + (knockedOut and 15 or 0)
    quin.Condition = math.max(0, before - loss)
    quin.ConditionAt = now()
    quin.Bond = math.min(100, (quin.Bond or 0) + 1)
    markDirty(quin)
    return before, quin.Condition
end

-- ============================================================================
-- WHAT THE OWNER KNOWS ABOUT ITS HABITS
-- ============================================================================

local function revealedByFights(quin)
    local battles = quin.BattleRecord and quin.BattleRecord.Battles or 0
    if battles < Care.REVEAL_FIGHTS then
        return {}
    end
    local count = math.min(#PersonalitySystem.DIMENSIONS, 3 + math.floor((battles - Care.REVEAL_FIGHTS) / 5))
    local list = {}
    for _, habit in ipairs(PersonalitySystem.DIMENSIONS) do
        table.insert(list, { habit = habit, edge = math.abs((quin.Personality[habit] or 0.5) - 0.5) })
    end
    table.sort(list, function(a, b)
        return a.edge > b.edge
    end)
    local shown = {}
    for i = 1, count do
        shown[list[i].habit] = true
    end
    return shown
end

-- The habits anyone can see (fights reveal them; an appraisal stays its owner's): { Name, Band }
function Care.knownHabits(quin)
    local list = {}
    for _, habit in ipairs(PersonalitySystem.DIMENSIONS) do
        if revealedByFights(quin)[habit] then
            table.insert(list, { Habit = habit, Name = Care.HABIT_NAMES[habit] or habit, Band = band(quin.Personality[habit] or 0.5) })
        end
    end
    return list
end

local function habitView(quin)
    local fromFights = revealedByFights(quin)
    local appraisal = quin.Appraisal
    local view = {}
    for _, habit in ipairs(PersonalitySystem.DIMENSIONS) do
        local entry = { Habit = habit, Name = Care.HABIT_NAMES[habit] or habit }
        if fromFights[habit] then
            entry.Band, entry.Source = band(quin.Personality[habit] or 0.5), "fights"
        elseif appraisal and appraisal.Bands and appraisal.Bands[habit] then
            entry.Band, entry.Source = appraisal.Bands[habit], "appraisal"
        end
        local trend = quin.HabitTrend and quin.HabitTrend[habit] or 0
        if entry.Band and math.abs(trend) >= 0.002 then
            entry.Trend = trend > 0 and 1 or -1
        end
        local focus = quin.TrainingFocus and quin.TrainingFocus[habit]
        if focus and focus ~= 0 then
            entry.Training = focus
        end
        table.insert(view, entry)
    end
    return view
end

-- ============================================================================
-- STATIONS AND REQUESTS
-- ============================================================================

local function stationPart(name)
    for _, d in ipairs(Workspace:GetDescendants()) do -- (a part of that name first: the Workshop folder shares it)
        if d.Name == name and d:IsA("BasePart") then
            return d
        end
    end
    local inst = Workspace:FindFirstChild(name, true)
    if not inst then
        return nil
    end
    if inst:IsA("BasePart") then
        return inst
    end
    return inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChild("UpperTorso") or inst:FindFirstChild("Torso")
        or inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

local STATIONS = {
    Workshop = { part = stationPart("QuinWorkshop"), action = "Repair", object = "Quin Workshop" },
    Trainer = { part = stationPart("Quin Trainer"), action = "Talk", object = "Quin Trainer" },
    Specialist = { part = stationPart("QuinSpecialist"), action = "Talk", object = "Quin Specialist" },
}
-- (the Workshop is a whole floor: its prompt sits over the operating tables, and anywhere on the floor counts as near)
do
    local floor = STATIONS.Workshop.part
    if floor and floor.Size.X > 20 then
        STATIONS.Workshop.zone = floor
        local tables = floor.Parent and floor.Parent:FindFirstChild("OperatingTableCopiesCopies")
        local spot = floor:FindFirstChild("QuinCareSpot") or Instance.new("Attachment")
        spot.Name = "QuinCareSpot"
        local at = tables and tables:IsA("Model") and tables:GetPivot().Position or floor.Position
        spot.WorldPosition = Vector3.new(at.X, floor.Position.Y + floor.Size.Y / 2 + 4, at.Z)
        spot.Parent = floor
        STATIONS.Workshop.promptParent = spot
    end
end
for kind, s in pairs(STATIONS) do
    local host = s.promptParent or s.part
    if host and not host:FindFirstChild("QuinCarePrompt") then
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = "QuinCarePrompt"
        prompt.ActionText = s.action
        prompt.ObjectText = s.object
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 10
        prompt.RequiresLineOfSight = false
        prompt:SetAttribute("Station", kind)
        prompt.Parent = host
    elseif not s.part then
        warn("[QuinCare] No station found for " .. kind)
    end
end

local function near(player, kind)
    local s = STATIONS[kind]
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if s and s.zone and root then
        local rel = s.zone.CFrame:PointToObjectSpace(root.Position)
        return math.abs(rel.X) <= s.zone.Size.X / 2 + 6 and math.abs(rel.Z) <= s.zone.Size.Z / 2 + 6 and math.abs(rel.Y) < 25
    end
    return s and s.part and root and (s.part.Position - root.Position).Magnitude <= Care.STATION_RANGE
end

local function quinInSlot(player, slot)
    local quin = QuinRosterService.getQuinInSlot(player, tonumber(slot) or 0)
    if quin then
        Care.settle(quin)
    end
    return quin
end

local function list(player)
    local roster = QuinRosterService.getRoster(player)
    local out = {}
    for slot = 1, roster.UnlockedSlots do
        local q = roster.Slots[slot]
        if q then
            Care.settle(q)
            local c = q.Condition or 100
            local busy = nil
            if q.Busy then
                busy = { Kind = q.Busy.Kind, Left = math.max(0, SkylarkTime.realSecondsUntil(q.Busy.Until) or 0),
                    Habit = q.Busy.Habit and Care.HABIT_NAMES[q.Busy.Habit], Dir = q.Busy.Dir, Session = q.Busy.Session }
            end
            table.insert(out, {
                Slot = slot,
                Tag = q.QuinId:sub(3, 6),
                Temperament = Temperament.displayName(q.Temperament or ""),
                Condition = math.floor(c + 0.5),
                RepairCost = math.ceil((100 - c) * Care.REPAIR_PER_POINT),
                RestFullIn = c < 100 and math.ceil((100 - c) / Care.REST_PER_HOUR * HOUR) or 0, -- real seconds
                Busy = busy,
                Bond = math.floor(q.Bond or 0),
                Battles = q.BattleRecord and q.BattleRecord.Battles or 0,
                Wins = q.BattleRecord and q.BattleRecord.Wins or 0,
                Losses = q.BattleRecord and q.BattleRecord.Losses or 0,
                Streak = q.BattleRecord and q.BattleRecord.CurrentStreak or 0,
                Gender = q.Gender,
                Title = q.Titles and q.Titles.Current or nil,
                Habits = habitView(q),
                AppraisedAt = q.Appraisal and q.Appraisal.At or nil,
            })
        end
    end
    return {
        Quins = out,
        Unlocked = roster.UnlockedSlots,
        MaxSlots = QuinRosterService.MAX_SLOTS,
        Balance = Wallet.balance(player),
        Sessions = Care.SESSIONS,
        AppraiseCost = Care.APPRAISE_COST,
        Now = now(),
    }
end

local function repair(player, slot)
    if not near(player, "Workshop") then
        return false, "Repairs are done at the Quin Workshop."
    end
    local quin = quinInSlot(player, slot)
    if not quin then
        return false, "No Quin in that slot."
    end
    if quin.Busy then
        return false, "That Quin is busy (" .. quin.Busy.Kind .. ")."
    end
    local c = quin.Condition or 100
    if c >= 99.5 then
        return false, "Already in full condition."
    end
    local cost = math.ceil((100 - c) * Care.REPAIR_PER_POINT)
    local ok, msg = Wallet.spend(player, cost, "Repair Quin #" .. quin.QuinId:sub(3, 6))
    if not ok then
        return false, msg
    end
    quin.Busy = { Kind = "Repair", Until = now() + Care.REPAIR_HOURS * HOUR }
    markDirty(quin)
    return true, string.format("Repairing Quin #%s for %d SC: back to 100%% in %d real minutes.", quin.QuinId:sub(3, 6), cost,
        math.ceil(Care.REPAIR_HOURS * HOUR / 60))
end

local function train(player, slot, habit, dir, sessionName)
    if not near(player, "Trainer") then
        return false, "Training is booked with the Quin Trainer."
    end
    local quin = quinInSlot(player, slot)
    local session = Care.SESSIONS[sessionName]
    if not quin then
        return false, "No Quin in that slot."
    end
    if not (Care.HABIT_NAMES[habit] and session and (dir == 1 or dir == -1)) then
        return false, "Pick a habit, up or down, and a session."
    end
    if quin.Busy then
        return false, "That Quin is busy (" .. quin.Busy.Kind .. ")."
    end
    local ok, msg = Wallet.spend(player, session.cost, string.format("Training Quin #%s %s", quin.QuinId:sub(3, 6), habit))
    if not ok then
        return false, msg
    end
    quin.Condition = math.max(0, (quin.Condition or 100) - Care.TRAIN_WEAR) -- (training wears it)
    quin.Busy = { Kind = "Training", Until = now() + session.hours * HOUR, Habit = habit, Dir = dir, Session = sessionName }
    markDirty(quin)
    return true, string.format("Quin #%s is training %s %s for %d real minutes (%d SC).", quin.QuinId:sub(3, 6),
        Care.HABIT_NAMES[habit], dir > 0 and "up" or "down", math.ceil(session.hours * HOUR / 60), session.cost)
end

local function appraise(player, slot)
    if not near(player, "Specialist") then
        return false, "Appraisals are done by the Quin Specialist."
    end
    local quin = quinInSlot(player, slot)
    if not quin then
        return false, "No Quin in that slot."
    end
    local ok, msg = Wallet.spend(player, Care.APPRAISE_COST, "Appraisal Quin #" .. quin.QuinId:sub(3, 6))
    if not ok then
        return false, msg
    end
    local bands = {}
    for _, habit in ipairs(PersonalitySystem.DIMENSIONS) do
        bands[habit] = band(quin.Personality[habit] or 0.5)
    end
    quin.Appraisal = { At = now(), Bands = bands }
    markDirty(quin)
    return true, string.format("Quin #%s appraised. This reading is true today; habits drift.", quin.QuinId:sub(3, 6))
end

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = ArenaNetwork:FindFirstChild("QuinCare")
if not remote then
    remote = Instance.new("RemoteFunction")
    remote.Name = "QuinCare"
    remote.Parent = ArenaNetwork
end
local busyRequest = {}
remote.OnServerInvoke = function(player, action, a, b, c, d)
    if busyRequest[player] then
        return false, "One moment..."
    end
    busyRequest[player] = true
    local ok, r1, r2 = pcall(function()
        if action == "list" then
            return list(player)
        elseif action == "repair" then
            return repair(player, a)
        elseif action == "train" then
            return train(player, a, b, tonumber(c), d)
        elseif action == "appraise" then
            return appraise(player, a)
        end
        return false, "Unknown request"
    end)
    busyRequest[player] = nil
    if not ok then
        warn("[QuinCare] " .. tostring(r1))
        return false, "Something went wrong"
    end
    return r1, r2
end

-- Studio tests (MCP runs code in its own VM, so tests drive this copy through an attribute):
-- workspace QuinCareDev = "cond <slot> <0..100>" | "finish <slot>" | "dump", on the first player.
-- The reply is workspace QuinCareDevResult.
if game:GetService("RunService"):IsStudio() then
    Workspace:GetAttributeChangedSignal("QuinCareDev"):Connect(function()
        local cmd = Workspace:GetAttribute("QuinCareDev")
        local player = Players:GetPlayers()[1]
        if not (cmd and player) then
            return
        end
        Workspace:SetAttribute("QuinCareDev", nil)
        local word, a, b = cmd:match("^(%S+)%s*(%S*)%s*(%S*)")
        local reply = "?"
        if word == "cond" or word == "finish" then
            local q = quinInSlot(player, a)
            if q and word == "cond" then
                q.Condition, q.ConditionAt = math.clamp(tonumber(b) or 100, 0, 100), now()
                reply = "ok"
            elseif q and q.Busy then
                q.Busy.Until = now() - 1
                reply = tostring(Care.settle(q))
            end
        elseif word == "dump" then
            local lines = {}
            local roster = QuinRosterService.getRoster(player)
            for slot = 1, roster.UnlockedSlots do
                local q = roster.Slots[slot]
                if q then
                    Care.settle(q)
                    table.insert(lines, string.format("%d %s cond %.1f bond %d busy %s aggr %.3f", slot, q.QuinId, q.Condition or 100,
                        q.Bond or 0, q.Busy and q.Busy.Kind or "-", q.Personality.Aggression or 0))
                end
            end
            reply = table.concat(lines, " | ")
        end
        Workspace:SetAttribute("QuinCareDevResult", reply)
    end)
end

-- ============================================================================
-- LOOP: finished work
-- ============================================================================

local function notice(player, text)
    local r = ArenaNetwork:FindFirstChild("PrepRoom")
    if r then
        r:FireClient(player, "notice", text)
    end
end

task.spawn(function()
    while true do
        task.wait(5)
        for _, player in ipairs(Players:GetPlayers()) do
            local ok, roster = pcall(QuinRosterService.getRoster, player)
            if ok and roster then
                for slot = 1, roster.UnlockedSlots do
                    local q = roster.Slots[slot]
                    local line = q and q.Busy and Care.settle(q)
                    if line then
                        notice(player, line)
                    end
                end
            end
        end
    end
end)

return Care
