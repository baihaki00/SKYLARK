local GASPManifest = {}

local function normalizeId(id)
    if typeof(id) ~= "string" then
        return nil
    end
    local digits = string.match(id, "%d+")
    if not digits then
        return nil
    end
    return "rbxassetid://" .. digits
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

function GASPManifest.validate(manifest)
    local errors, warnings, normalized = {}, {}, {}
    if typeof(manifest) ~= "table" then
        return { ok = false, errors = {"manifest must be a table"}, warnings = {}, clips = {} }
    end
    if manifest.Version ~= 1 then
        table.insert(warnings, "unexpected manifest version: "..tostring(manifest.Version))
    end
    local seenIds = {}
    for _, label in ipairs(sortedKeys(manifest.Clips)) do
        local clip = manifest.Clips[label]
        if typeof(clip) ~= "table" then
            table.insert(errors, label.." must be a clip table")
            continue
        end
        local id = normalizeId(clip.id)
        if not id then
            table.insert(errors, label.." has no valid Roblox animation id")
            continue
        end
        if seenIds[id] then
            table.insert(warnings, "duplicate asset id "..id.." used by "..seenIds[id].." and "..label)
        else
            seenIds[id] = label
        end
        normalized[label] = {
            id = id,
            mode = clip.mode or "Unknown",
            action = clip.action or "Loop",
            direction = clip.direction or "Neutral",
            speed = tonumber(clip.speed) or 1,
            phase = tonumber(clip.phase) or 0,
            contact = clip.contact or "Unknown",
            duration = tonumber(clip.duration),
            rootMotion = clip.rootMotion == true,
        }
    end
    if next(normalized) == nil then
        table.insert(warnings, "no uploaded clips are present")
    end
    return { ok = #errors == 0, errors = errors, warnings = warnings, clips = normalized }
end

function GASPManifest.resolve(label, manifest)
    local report = GASPManifest.validate(manifest)
    return report.clips[label], report
end

function GASPManifest.labels(manifest)
    local report = GASPManifest.validate(manifest)
    local labels = {}
    for label in pairs(report.clips) do table.insert(labels, label) end
    table.sort(labels)
    return labels, report
end

return GASPManifest
