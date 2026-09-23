local QuinCore = game:GetService("ReplicatedStorage"):FindFirstChild("QuinCore")
local infractions = {}

local function scan(inst)
    if inst:IsA("LuaSourceContainer") then
        local src = inst.Source
        local lines = src:split("\n")
        for lineNum, line in ipairs(lines) do
            local trimmed = line:match("^%s*(.-)%s*$")
            if not trimmed:sub(1, 2) == "--" then
                local codeOnly = line:gsub("%-%-.*$", "")
                if codeOnly:find("Instance.new%([\"']BodyVelocity[\"']%)") then
                    table.insert(infractions, string.format("%s:%d has Instance.new('BodyVelocity')", inst:GetFullName(), lineNum))
                end
                if codeOnly:find("Instance.new%([\"']BodyGyro[\"']%)") then
                    table.insert(infractions, string.format("%s:%d has Instance.new('BodyGyro')", inst:GetFullName(), lineNum))
                end
                if codeOnly:find("Instance.new%([\"']BodyPosition[\"']%)") then
                    table.insert(infractions, string.format("%s:%d has Instance.new('BodyPosition')", inst:GetFullName(), lineNum))
                end
            end
        end
    end
    for _, ch in ipairs(inst:GetChildren()) do
        scan(ch)
    end
end

scan(QuinCore)

if #infractions == 0 then
    return "PASS: 0 deprecated BodyMovers instantiated in QuinCore!"
else
    return "FAIL: Found " .. #infractions .. " infractions:\n" .. table.concat(infractions, "\n")
end
