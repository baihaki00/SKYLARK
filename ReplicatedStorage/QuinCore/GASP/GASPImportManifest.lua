local GASPManifest = require(script.Parent:WaitForChild("GASPManifest"))

local M = {}

local function normalizeId(value)
    if type(value) == "number" then
        return "rbxassetid://" .. tostring(math.floor(value))
    end
    if type(value) ~= "string" then
        return nil
    end
    local digits = string.match(value, "%d+")
    if not digits then
        return nil
    end
    return "rbxassetid://" .. digits
end

function M.build(assetMap, metadata)
    assetMap = assetMap or {}
    metadata = metadata or {}
    local clips = {}
    for label, rawId in pairs(assetMap) do
        clips[tostring(label)] = {
            id = normalizeId(rawId),
        }
    end
    local manifest = {
        Version = 1,
        Enabled = metadata.Enabled == true,
        SourceProject = metadata.SourceProject or "GameAnimationSample2",
        SourceEngine = metadata.SourceEngine or "Unreal Engine 5.8",
        RetargetSkeleton = metadata.RetargetSkeleton or "Quin",
        Clips = clips,
    }
    local report = GASPManifest.validate(manifest)
    return manifest, report.errors, report.warnings
end

function M.report(assetMap, metadata)
    local _, errors, warnings = M.build(assetMap, metadata)
    return {
        errors = errors or {},
        warnings = warnings or {},
        valid = #(errors or {}) == 0,
    }
end

return M
