local GASPManifest = require(script.Parent.GASPManifest)
local GASPMotionDatabase = {}
GASPMotionDatabase.__index = GASPMotionDatabase

function GASPMotionDatabase.new(manifest)
    local self = setmetatable({
        manifest = manifest,
        records = {},
        byMode = {},
        active = false,
        lastSelection = nil,
    }, GASPMotionDatabase)
    self:rebuild()
    return self
end

function GASPMotionDatabase:rebuild()
    self.records = {}
    self.byMode = {}
    local report = GASPManifest.validate(self.manifest)
    self.active = self.manifest.Enabled == true and report.ok and next(report.clips) ~= nil
    for label, clip in pairs(report.clips) do
        local record = table.clone(clip)
        record.label = label
        -- Inherit rich motion tags from manifest
        local rawClip = self.manifest.Clips and self.manifest.Clips[label]
        if rawClip then
            record.turnAngle = rawClip.turnAngle
            record.turnSide = rawClip.turnSide
            record.foot = rawClip.foot
            record.fromMode = rawClip.fromMode
            record.toMode = rawClip.toMode
        end
        table.insert(self.records, record)
        self.byMode[record.mode] = self.byMode[record.mode] or {}
        table.insert(self.byMode[record.mode], record)
    end
    table.sort(self.records, function(a,b) return a.label < b.label end)
    return report
end

local function score(record, query)
    local s = 0
    if query.mode and record.mode ~= query.mode then s += 100 end
    if query.action and record.action ~= query.action then s += 40 end
    if query.direction and record.direction ~= query.direction then s += 25 end
    if query.turnAngle and record.turnAngle ~= query.turnAngle then s += 20 end
    if query.turnSide and record.turnSide ~= query.turnSide then s += 15 end
    if query.fromMode and record.fromMode ~= query.fromMode then s += 50 end
    if query.toMode and record.toMode ~= query.toMode then s += 50 end
    if query.speed and record.speed then s += math.abs(query.speed - record.speed) * 4 end
    if query.phase and record.phase then
        local delta = math.abs(query.phase - record.phase)
        s += math.min(delta, 1 - delta) * 12
    end
    if query.foot and record.foot and query.foot ~= record.foot then s += 8 end
    return s
end

function GASPMotionDatabase:select(query)
    if not self.active then return nil, "disabled_or_empty" end
    local best, bestScore
    for _, record in ipairs(self.records) do
        local candidateScore = score(record, query or {})
        if not bestScore or candidateScore < bestScore then
            best, bestScore = record, candidateScore
        end
    end
    if best then
        self.lastSelection = { label = best.label, score = bestScore }
    end
    return best, bestScore
end

function GASPMotionDatabase:debug()
    return {
        active = self.active,
        recordCount = #self.records,
        lastSelection = self.lastSelection,
    }
end

return GASPMotionDatabase
