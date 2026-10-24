--// SkylarkPayouts.lua
-- What a round costs an owner and what it pays back (SKYLARK_ECONOMY_DESIGN.md, step 2):
--   * Entry: ENTRY_FEE per Quin, taken when the Quin is seated for a round (ArenaRegistration):
--     you pay only for rounds your Quins actually fight. A round stopped before the winner is
--     decided gives it back (refund).
--   * Performance score, 0..1000 per Quin, from what it did (ArenaSystemOrchestrator counts it
--     while the match runs, and shows it live as the Quin's MatchScore attribute):
--       Damage      350  damage dealt; twice the match's average or more scores it all
--       KOs         200  knockouts, 3 or more scores it all
--       Survival    200  how much of the match it was still standing
--       Efficiency  150  dealt / (dealt + taken)
--       Result      100  its side won
--   * Payout per Quin: PARTICIPATION + score x PER_POINT, + WIN_BONUS on the winning side,
--     + SURVIVOR_BONUS if still standing at the end. A quick double loss costs about 100 of the
--     200 entry; an average loss gives a little back; a win pays well. Money drains elsewhere
--     too (repairs, training: step 3).
-- No Robux anywhere: SC comes only from playing (no pay to win).

local ServerScriptService = game:GetService("ServerScriptService")

local Wallet = require(ServerScriptService:WaitForChild("SkylarkWallet"))

local Payouts = {}

Payouts.ENTRY_FEE = 100
Payouts.PARTICIPATION = 30
Payouts.PER_POINT = 0.2
Payouts.WIN_BONUS = 150
Payouts.SURVIVOR_BONUS = 50

Payouts.PARTS = {
    { key = "Damage", max = 350 },
    { key = "KOs", max = 200 },
    { key = "Survival", max = 200 },
    { key = "Efficiency", max = 150 },
    { key = "Result", max = 100 },
}

-- c: { dmg, taken, kills, lifetime } for one Quin; match: { avgDmg, length }; won: its side won.
-- Returns total, { [part] = points }
function Payouts.score(c, match, won)
    local parts = {}
    local avg = math.max(1, match.avgDmg or 1)
    parts.Damage = 350 * math.clamp((c.dmg or 0) / (2 * avg), 0, 1)
    parts.KOs = 200 * math.clamp((c.kills or 0) / 3, 0, 1)
    parts.Survival = 200 * math.clamp((c.lifetime or 0) / math.max(1, match.length or 1), 0, 1)
    local dealt, taken = c.dmg or 0, c.taken or 0
    parts.Efficiency = 150 * ((dealt + taken) > 0 and dealt / (dealt + taken) or 0)
    parts.Result = won and 100 or 0
    local total = 0
    for key, v in pairs(parts) do
        parts[key] = math.floor(v + 0.5)
        total += parts[key]
    end
    return total, parts
end

function Payouts.payout(score, won, survived)
    local performance = math.floor(score * Payouts.PER_POINT)
    local pay = Payouts.PARTICIPATION + performance
    local lines = { { "Took part", Payouts.PARTICIPATION }, { "Performance", performance } }
    if won then
        pay += Payouts.WIN_BONUS
        table.insert(lines, { "Win bonus", Payouts.WIN_BONUS })
    end
    if survived then
        pay += Payouts.SURVIVOR_BONUS
        table.insert(lines, { "Still standing", Payouts.SURVIVOR_BONUS })
    end
    return pay, lines
end

-- The entry fee for one seated Quin. Returns true, or false + message when the owner can't pay.
function Payouts.chargeEntry(player, quinTag)
    local ok, result = Wallet.spend(player, Payouts.ENTRY_FEE, "Entry Quin #" .. tostring(quinTag))
    if not ok then
        return false, result
    end
    return true
end

function Payouts.refund(player, amount, reason)
    if player and player.Parent and amount > 0 then
        Wallet.grant(player, amount, reason or "Refund")
    end
end

function Payouts.grant(player, amount, reason)
    if player and player.Parent and amount > 0 then
        return Wallet.grant(player, amount, reason)
    end
    return Wallet.balance(player)
end

function Payouts.balance(player)
    return Wallet.balance(player)
end

return Payouts
