--// SkylarkWallet.lua
-- Skylark Coin (SC): every player's money, kept on the server only (SKYLARK_ECONOMY_DESIGN.md).
-- SC is earned by playing and never sold for Robux. The client can only ask (spend through the
-- services that sell something); the balance it sees is the player attribute "SC", set here.
--
--   Wallet.balance(player)                 -> number (nil until loaded)
--   Wallet.spend(player, amount, reason)   -> true, newBalance | false, message
--   Wallet.grant(player, amount, reason)   -> newBalance
--
-- Saved in the DataStore "SkylarkWallet_v1" (key "u_<userId>"): loaded on join (a new player starts
-- with START_BALANCE), saved when it changes (at most every SAVE_EVERY seconds), on leaving and on
-- shutdown. If the DataStore can't be reached (Studio without API access) the balance lives in
-- memory for the session and is never saved, so a failed load can't overwrite real money.
-- (A session lock, for one account in two servers at once, comes with the full player save.)

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Wallet = {}

Wallet.START_BALANCE = 2500
local SAVE_EVERY = 30

local store = nil
pcall(function()
    store = DataStoreService:GetDataStore("SkylarkWallet_v1")
end)

local balances = {} -- [userId] = number
local saveable = {} -- [userId] = true when loaded from the store (so saving can't clobber)
local dirty = {} -- [userId] = true: changed since the last save

local function key(player)
    return "u_" .. player.UserId
end

local function publish(player)
    player:SetAttribute("SC", balances[player.UserId])
end

local function load(player)
    local value = nil
    local ok = false
    if store then
        ok = pcall(function()
            value = store:GetAsync(key(player))
        end)
    end
    if not player.Parent then
        return
    end
    if ok then
        saveable[player.UserId] = true
    else
        warn(string.format("[SkylarkWallet] No DataStore for %s: SC this session only, not saved", player.Name))
    end
    balances[player.UserId] = type(value) == "number" and value or Wallet.START_BALANCE
    if ok and type(value) ~= "number" then
        dirty[player.UserId] = true -- (a new player: save the starting balance)
    end
    publish(player)
end

local function save(player)
    local id = player.UserId
    if not (saveable[id] and dirty[id] and store) then
        return
    end
    local amount = balances[id]
    local ok, err = pcall(function()
        store:UpdateAsync("u_" .. id, function()
            return amount
        end)
    end)
    if ok then
        dirty[id] = nil
    else
        warn("[SkylarkWallet] Save failed for " .. player.Name .. ": " .. tostring(err))
    end
end

function Wallet.balance(player)
    return balances[player.UserId]
end

function Wallet.spend(player, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    local current = balances[player.UserId]
    if not current then
        return false, "Your wallet is still loading"
    end
    if amount < 0 then
        return false, "Bad amount"
    end
    if current < amount then
        return false, string.format("Not enough SC (%d needed, you have %d)", amount, current)
    end
    balances[player.UserId] = current - amount
    dirty[player.UserId] = true
    publish(player)
    print(string.format("[SkylarkWallet] %s -%d SC (%s) = %d", player.Name, amount, tostring(reason), balances[player.UserId]))
    return true, balances[player.UserId]
end

function Wallet.grant(player, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if not balances[player.UserId] or amount <= 0 then
        return balances[player.UserId]
    end
    balances[player.UserId] += amount
    dirty[player.UserId] = true
    publish(player)
    print(string.format("[SkylarkWallet] %s +%d SC (%s) = %d", player.Name, amount, tostring(reason), balances[player.UserId]))
    return balances[player.UserId]
end

Players.PlayerAdded:Connect(load)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(load, player)
end

Players.PlayerRemoving:Connect(function(player)
    save(player)
    balances[player.UserId], saveable[player.UserId], dirty[player.UserId] = nil, nil, nil
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        save(player)
    end
end)

task.spawn(function()
    while true do
        task.wait(SAVE_EVERY)
        for _, player in ipairs(Players:GetPlayers()) do
            save(player)
        end
    end
end)

return Wallet
