--// StudioAutoDebugCombat.server.lua
-- Studio only, for heavy 16v16 testing (owner, 2026-10-27): with the Workspace attribute
-- StudioAutoDebugCombat = true, pressing Play makes the first player Admin and starts the
-- DEBUG COMBAT match at once (the same as the DEBUG COMBAT button: instant 16v16, no clothes,
-- crowd, music, announcer, fireworks or drones). Untick the attribute to play normally.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() or Workspace:GetAttribute("StudioAutoDebugCombat") ~= true then
    return
end

-- (the DEBUG COMBAT button's toggles, ArenaController.client.lua)
local DEBUG_COMBAT_TOGGLES = {
    Announcer = false, ProceduralMusic = false, RandomMusic = false, CrowdFX = false, CrowdAvatars = false,
    Clothes = false, Fireworks = false, Drones = false, TimerPreGame = false,
    Screen = true, ProceduralTerrain = true, InstantMatch = true,
}

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
-- after SkylarkRoles has set everyone joining to Player
task.wait(1)
if player.Parent and player:GetAttribute("SkylarkCanAdmin") == true then
    player:SetAttribute("SkylarkRole", "Admin")
end

local deadline = os.clock() + 30
while not _G.ArenaOrchestrator and os.clock() < deadline do
    task.wait(0.25)
end
if not _G.ArenaOrchestrator then
    warn("[StudioAutoDebugCombat] the orchestrator never came up: no match started")
    return
end
task.wait(2) -- let the arena finish its own start-up
local ok, err = pcall(function()
    _G.ArenaOrchestrator.startMatch({ Mode = "TeamBattle", TeamSize = 16, Toggles = DEBUG_COMBAT_TOGGLES })
end)
print(ok and "[StudioAutoDebugCombat] Admin + DEBUG COMBAT 16v16 started" or ("[StudioAutoDebugCombat] start failed: " .. tostring(err)))
