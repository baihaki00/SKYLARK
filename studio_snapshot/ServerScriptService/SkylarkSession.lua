--// SkylarkSession.lua
-- One server at a time holds a player's save (the session lock). Without it, an account open in
-- two servers (a fast server hop, a second device) could load in one, save in the other and roll
-- back or copy SC and Quins.
--
--   * On join the server claims the lock (DataStore "SkylarkSession_v1", key "u_<userId>":
--     { Job = JobId, T = os.time() }). If another server still holds it (it is saving the
--     player who just left there), this one waits and tries again; a lock not refreshed for
--     STALE seconds (a crashed server) is taken over. Never free in time: the player is asked to
--     rejoin (kicked), so nothing loads.
--   * The services that save something (SkylarkWallet, QuinDataStoreService) load only once the
--     lock is held (Session.waitFor) and hand their save to Session.addSaver; on leaving and on
--     shutdown the savers run first and the lock is let go after them.
--   * Held locks are refreshed every HEARTBEAT seconds.
--   * Without a DataStore (Studio without API access) there is no lock: saves stay in memory.
--     If the lock store errors past WAIT_FOR, the player plays unsaved this session (maySave false).
--
--   Session.waitFor(player) -> true when this server may load and save the player (yields)
--   Session.maySave(player) -> may a save be written now (the lock is held)
--   Session.addSaver(fn)    -- fn(player): save; runs before the lock is let go

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Session = {}

local STALE = 300 -- seconds without a refresh: the server that held it is gone
local HEARTBEAT = 60
local WAIT_FOR = 45 -- seconds to wait for another server to let go
local RETRY = 3

local store = nil
pcall(function()
    store = DataStoreService:GetDataStore("SkylarkSession_v1")
end)

local job = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(math.random(1, 1e9)))
local state = {} -- [userId] = "pending" | "held" | "none" (no DataStore) | "unsaved" (lock store failing) | "denied"
local changed = Instance.new("BindableEvent")
local savers = {}

local function key(userId)
    return "u_" .. userId
end

-- Try once: true (held), false (another server has it), "error" (the store failed), nil (no DataStore)
local function claim(userId)
    if not store then
        return nil
    end
    local got = false
    local ok = pcall(function()
        store:UpdateAsync(key(userId), function(old)
            local now = os.time()
            if type(old) == "table" and old.Job ~= job and now - (old.T or 0) < STALE then
                got = false
                return nil -- (someone else's: leave it)
            end
            got = true
            return { Job = job, T = now }
        end)
    end)
    if not ok then
        return "error"
    end
    return got
end

local function release(userId)
    if not store or state[userId] ~= "held" then
        return
    end
    pcall(function()
        store:UpdateAsync(key(userId), function(old)
            if type(old) == "table" and old.Job == job then
                return { Job = job, T = 0 } -- (free: stale at once)
            end
            return nil
        end)
    end)
end

local function set(userId, value)
    state[userId] = value
    changed:Fire(userId)
end

local function acquire(player)
    local userId = player.UserId
    set(userId, "pending")
    local started = os.clock()
    while player.Parent do
        local got = claim(userId)
        if got == nil then -- (no DataStore here: nothing is saved, so nothing can clash)
            set(userId, "none")
            return
        elseif got == true then
            set(userId, "held")
            return
        end
        if os.clock() - started > WAIT_FOR or (got == "error" and RunService:IsStudio()) then
            if got == "error" then -- (the store keeps failing, or Studio has no API access: play, save nothing)
                set(userId, "unsaved")
                warn(string.format("[SkylarkSession] %s plays unsaved: the save lock can't be reached", player.Name))
                return
            end
            set(userId, "denied")
            warn(string.format("[SkylarkSession] %s's save is still open in another server", player.Name))
            if not RunService:IsStudio() then
                player:Kick("Your Skylark save is still open in another server. Please rejoin in a minute.")
            end
            return
        end
        task.wait(RETRY)
    end
end

function Session.waitFor(player)
    local userId = player.UserId
    while state[userId] == nil or state[userId] == "pending" do
        if not player.Parent then
            return false
        end
        changed.Event:Wait()
    end
    return state[userId] == "held" or state[userId] == "none"
end

function Session.maySave(player)
    return state[player.UserId] == "held"
end

-- Is the player's save safe to write? (held, or no DataStore at all: memory only)
function Session.state(player)
    return state[player.UserId]
end

function Session.addSaver(fn)
    table.insert(savers, fn)
end

local function saveAll(player)
    for _, fn in ipairs(savers) do
        local ok, err = pcall(fn, player)
        if not ok then
            warn("[SkylarkSession] Save failed: " .. tostring(err))
        end
    end
end

Players.PlayerAdded:Connect(acquire)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(acquire, player)
end

Players.PlayerRemoving:Connect(function(player)
    local userId = player.UserId
    if state[userId] == "held" or state[userId] == "none" then
        saveAll(player)
    end
    release(userId)
    state[userId] = nil
    changed:Fire(userId)
end)

game:BindToClose(function()
    local left = 0
    for _, player in ipairs(Players:GetPlayers()) do
        left += 1
        task.spawn(function()
            if state[player.UserId] == "held" or state[player.UserId] == "none" then
                saveAll(player)
            end
            release(player.UserId)
            left -= 1
        end)
    end
    local t = os.clock()
    while left > 0 and os.clock() - t < 25 do
        task.wait(0.2)
    end
end)

task.spawn(function()
    while true do
        task.wait(HEARTBEAT)
        for _, player in ipairs(Players:GetPlayers()) do
            if state[player.UserId] == "held" then
                local got = claim(player.UserId)
                if got == false then -- (taken over while we thought it ours: stop saving)
                    warn("[SkylarkSession] Lost the lock for " .. player.Name)
                    set(player.UserId, "denied")
                end
            end
        end
    end
end)

return Session
