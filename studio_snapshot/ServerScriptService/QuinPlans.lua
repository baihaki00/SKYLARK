--// QuinPlans.lua
-- The owner's plan for a Quin's round, set at the preparation room terminal while the room is open
-- (PREPARATION_ROOM; locked when the Quins deploy). SKYLARK_ECONOMY_DESIGN.md step 4:
--   * Stance (Aggressive / Balanced / Defensive), Target (Own pick / Weakest / Strongest / Defend)
--     and Role (Free / Striker / Guard / Hunter).
--   * A plan never makes a Quin stronger: it leans the Quin's own habits (the live Pers_ values)
--     for the round, and adds a target preference (TargetingModule reads PlanTarget / PlanRole /
--     PlanFollow).
--   * How much it follows: 0.4 + 0.6 x Bond/100. Each part that goes against its nature (a timid
--     Quin told to be Aggressive, a loner told to Guard...) follows 30% less and makes it hesitate
--     a moment before it fights (PlanHesitation seconds: the orchestrator holds it inert that long).
--   * The last plan per Quin is remembered for the session and put back on its next round.
--   * NPC owners plan too (npcPick: from the Quin's own habits), so a plan is no edge players alone have.
-- Model attributes: PlanStance, PlanTarget, PlanRole, PlanFollow (0..1), PlanClash (text),
-- PlanHesitation (s).

local Workspace = game:GetService("Workspace")

local Plans = {}

Plans.STANCES = { "Aggressive", "Balanced", "Defensive" }
Plans.TARGETS = { "Own pick", "Weakest", "Strongest", "Defend" }
Plans.ROLES = { "Free", "Striker", "Guard", "Hunter" }

local CLASH_KEEP = 0.7 -- follow kept per part against its nature
local CLASH_HESITATION = 0.8 -- seconds per part against its nature
local MAX_HESITATION = 2

-- habit leans at full follow
local LEANS = {
    Aggressive = { Aggression = 0.25, RiskTolerance = 0.2, RetreatTendency = -0.2, TargetPersistence = 0.15, DashPreference = 0.1 },
    Defensive = { Aggression = -0.25, RiskTolerance = -0.2, RetreatTendency = 0.25, MobilityPreference = 0.1, Awareness = 0.1 },
    Striker = { Aggression = 0.1, DashPreference = 0.15, Protectiveness = -0.15 },
    Guard = { Protectiveness = 0.35, TargetPersistence = -0.1, MobilityPreference = -0.1 },
    Hunter = { MobilityPreference = 0.15, TargetPersistence = 0.2, Protectiveness = -0.2, Awareness = 0.1 },
}

-- what goes against a Quin's nature (its saved habits)
local function clashes(habits, plan)
    local list = {}
    local aggression = habits.Aggression or 0.6
    local protect = habits.Protectiveness or 0.5
    if plan.Stance == "Aggressive" and aggression < 0.45 then
        table.insert(list, "too timid to go all in")
    elseif plan.Stance == "Defensive" and aggression > 0.8 then
        table.insert(list, "hates holding back")
    end
    if plan.Role == "Striker" and aggression < 0.45 then
        table.insert(list, "not a front-liner")
    elseif plan.Role == "Guard" and protect < 0.3 then
        table.insert(list, "a loner, not a guard")
    elseif plan.Role == "Hunter" and protect > 0.75 then
        table.insert(list, "won't leave its team")
    end
    if plan.Target == "Defend" and protect < 0.25 then
        table.insert(list, "doesn't care to defend")
    end
    return list
end

local function valid(list, v)
    return table.find(list, v) ~= nil
end

local last = {} -- [QuinId] = plan

function Plans.lastFor(quin)
    return quin and last[quin.QuinId]
end

-- How much this Quin follows its owner at all
function Plans.follow(quin)
    return 0.4 + 0.6 * math.clamp((quin.Bond or 0) / 100, 0, 1)
end

-- Put `plan` on `model` (the Quin's saved instance `quin`): returns ok, message
function Plans.apply(model, quin, plan)
    plan = type(plan) == "table" and plan or {}
    local stance = valid(Plans.STANCES, plan.Stance) and plan.Stance or "Balanced"
    local target = valid(Plans.TARGETS, plan.Target) and plan.Target or "Own pick"
    local role = valid(Plans.ROLES, plan.Role) and plan.Role or "Free"
    plan = { Stance = stance, Target = target, Role = role }

    local habits = quin.Personality or {}
    local against = clashes(habits, plan)
    local follow = Plans.follow(quin) * CLASH_KEEP ^ #against

    -- the live habits: the saved ones, leaned
    local sum = {}
    for _, key in ipairs({ stance, role }) do
        for dim, d in pairs(LEANS[key] or {}) do
            sum[dim] = (sum[dim] or 0) + d
        end
    end
    for dim, base in pairs(habits) do
        if dim ~= "Confidence" and type(base) == "number" then
            model:SetAttribute("Pers_" .. dim, math.clamp(base + (sum[dim] or 0) * follow, 0, 1))
        end
    end

    local neutral = stance == "Balanced" and target == "Own pick" and role == "Free"
    model:SetAttribute("PlanStance", stance)
    model:SetAttribute("PlanTarget", target)
    model:SetAttribute("PlanRole", role)
    model:SetAttribute("PlanFollow", (not neutral) and (math.floor(follow * 100 + 0.5) / 100) or nil)
    model:SetAttribute("PlanClash", #against > 0 and table.concat(against, ", ") or nil)
    model:SetAttribute("PlanHesitation", #against > 0 and math.min(MAX_HESITATION, CLASH_HESITATION * #against) or nil)
    last[quin.QuinId] = plan

    local pct = math.floor(follow * 100 + 0.5)
    if neutral then
        return true, "No plan: it fights its own way."
    elseif #against > 0 then
        return true, string.format("Plan set, against its nature (%s): follows about %d%% and hesitates first.", table.concat(against, ", "), pct)
    end
    return true, string.format("Plan set. It follows about %d%%.", pct)
end

-- An NPC owner's plan for its Quin: read from the Quin's own habits (so it rarely goes against its
-- nature), with a little chance so two alike Quins don't always get the same plan.
function Plans.npcPick(quin, rng)
    rng = rng or Random.new()
    local h = quin.Personality or {}
    local aggression, protect = h.Aggression or 0.6, h.Protectiveness or 0.5
    local mobility = h.MobilityPreference or 0.5
    local stance = "Balanced"
    if aggression > 0.7 and rng:NextNumber() < 0.7 then
        stance = "Aggressive"
    elseif aggression < 0.5 and rng:NextNumber() < 0.7 then
        stance = "Defensive"
    end
    local role = "Free"
    if protect > 0.65 then
        role = "Guard"
    elseif mobility > 0.75 and protect < 0.45 then
        role = "Hunter"
    elseif aggression > 0.75 then
        role = "Striker"
    end
    local target = "Own pick"
    local roll = rng:NextNumber()
    if roll < 0.2 then
        target = "Weakest"
    elseif roll < 0.3 and protect >= 0.4 then
        target = "Defend"
    end
    return { Stance = stance, Target = target, Role = role }
end

-- May plans change now?
function Plans.open()
    return Workspace:GetAttribute("ArenaPhase") == "PREPARATION_ROOM"
end

return Plans
