--// ScoutView.lua
-- Scouting, read on the player's machine (SKYLARK_ECONOMY_DESIGN.md step 4D): the round's Quins
-- per team (Workspace ScoutRoster, published by ArenaPrepRoom while the rooms are open: bands
-- only, the same as the ArenaBoards; never an opponent's plan or exact numbers) and the arena's
-- facts (Workspace ArenaScout, ArenaGenerator). The glass (MatchResultsClient) and the prep
-- terminal (PrepRoomClient) draw it.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local ScoutView = {}

local function decode(name)
    local raw = Workspace:GetAttribute(name)
    local ok, value = pcall(function()
        return raw and HttpService:JSONDecode(raw)
    end)
    return ok and type(value) == "table" and value or nil
end

local function mix(counts)
    local list = {}
    for name, n in pairs(counts) do
        table.insert(list, { name, n })
    end
    table.sort(list, function(a, b)
        return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1])
    end)
    local out = {}
    for _, e in ipairs(list) do
        table.insert(out, e[2] .. " " .. e[1])
    end
    return table.concat(out, ", ")
end

-- The other side, as seen from `player`. nil when the player has no Quin in the round.
-- { side, count, owners, us, them (strength sums), players = { { name, strength, quins } },
--   npc = { count, temperaments }, temperaments, fresh, worn, battered, bonded, best = quin }
function ScoutView.opponents(player)
    player = player or Players.LocalPlayer
    local roster = decode("ScoutRoster")
    if not roster then
        return nil
    end
    local mine = nil
    for team, list in pairs(roster) do
        for _, q in ipairs(list) do
            if q.UserId == player.UserId then
                mine = team
            end
        end
    end
    if not mine then
        return nil
    end
    local theirs = mine == "TeamAlpha" and "TeamBeta" or "TeamAlpha"
    local view = { side = theirs == "TeamAlpha" and "ALPHA" or "BETA", count = 0, us = 0, them = 0,
        players = {}, npc = { count = 0 }, fresh = 0, worn = 0, battered = 0, bonded = 0 }
    for _, q in ipairs(roster[mine] or {}) do
        view.us += q.S or 0
    end
    local byOwner, temps, npcTemps = {}, {}, {}
    for _, q in ipairs(roster[theirs] or {}) do
        view.them += q.S or 0
        view.count += 1
        view[string.lower(q.Cond or "Fresh")] = (view[string.lower(q.Cond or "Fresh")] or 0) + 1
        if q.Bond == "Bonded" then
            view.bonded += 1
        end
        temps[q.Temperament] = (temps[q.Temperament] or 0) + 1
        if not view.best or (q.Wins or 0) > (view.best.Wins or 0) then
            view.best = q
        end
        if q.Npc then
            view.npc.count += 1
            npcTemps[q.Temperament] = (npcTemps[q.Temperament] or 0) + 1
        else
            local owner = byOwner[q.Owner]
            if not owner then
                owner = { name = q.Owner, strength = 0, quins = {} }
                byOwner[q.Owner] = owner
                table.insert(view.players, owner)
            end
            owner.strength += q.S or 0
            table.insert(owner.quins, q)
        end
    end
    view.owners = #view.players + (view.npc.count > 0 and 1 or 0)
    table.sort(view.players, function(a, b)
        return a.strength > b.strength
    end)
    view.temperaments = mix(temps)
    view.npc.temperaments = mix(npcTemps)
    return view
end

-- One opponent Quin as a line: "Quin #8769  Hothead  •  W14 L3  •  Fresh  •  Bonded"
function ScoutView.quinLine(q)
    return string.format("Quin #%s  %s  •  W%d L%d  •  %s  •  %s", q.Tag or "????", q.Temperament or "?", q.Wins or 0, q.Losses or 0, q.Cond or "?", q.Bond or "?")
end

-- The arena's facts (nil before a generated arena): the table, and two lines of text
function ScoutView.arena()
    local facts = decode("ArenaScout")
    if not facts then
        return nil
    end
    local line1 = string.format("%s  •  %d pieces  •  %d trees  •  %s COVER", facts.Layout or "?", facts.Pieces or 0, facts.Trees or 0, facts.Cover or "?")
    local line2 = string.format("High ground: %d platforms  •  Open lanes: %d", facts.High or 0, facts.Lanes or 0)
    return facts, line1, line2
end

return ScoutView
