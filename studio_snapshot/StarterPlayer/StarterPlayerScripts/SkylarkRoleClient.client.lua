--// SkylarkRoleClient.client.lua
-- The player's side of the two roles (SkylarkRoles): as a Player, every admin screen is off (the
-- Quin menu, the Spectator HUD, drones, the animation lab, debug and tuning panels). The
-- Spectator HUD comes back only at a preparation room terminal (shared.SpectateFilter is set
-- while one is in use), with the player's own Quins. As Admin, the screens are as they were.
-- The key handlers in those scripts check the role too (keys fire even with a screen off).
-- shared.IsAdmin() is the one check every script can use.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The debug buttons (Play As Admin / Play As Roblox Player / Spectator HUD) stay hidden; F8 shows
-- or hides them. Their keys (P, H) work either way. Read through shared.DebugButtons().
shared.DebugButtons = function()
    return player:GetAttribute("ShowDebugButtons") == true
end
game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.F8 then
        player:SetAttribute("ShowDebugButtons", not shared.DebugButtons() or nil)
    end
end)

local ADMIN_SCREENS = {
    QuinMenuUI = true, AnimationLabUI = true, ArenaOrchestratorUI = true, JumpDebugUI = true,
    ArenaDroneUI = true, MasterDebugUI = true, TuningPanel = true,
}
local TERMINAL_SCREENS = { QuinDebugGui = true } -- (also at a preparation room terminal)
local VIP_SCREENS = { ArenaDroneUI = true } -- (also inside a VIP box after using its terminal: SkylarkSpectate)

shared.IsAdmin = function()
    return player:GetAttribute("SkylarkRole") == "Admin"
end

local hidden = {} -- [ScreenGui] = was enabled before the Player role hid it

local function reconcile()
    local admin = shared.IsAdmin()
    local atTerminal = shared.SpectateFilter ~= nil
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and (ADMIN_SCREENS[gui.Name] or TERMINAL_SCREENS[gui.Name]) then
            local allowed = admin or (TERMINAL_SCREENS[gui.Name] and atTerminal) or (VIP_SCREENS[gui.Name] and shared.VipAccess == true)
            if not allowed then
                if hidden[gui] == nil then
                    hidden[gui] = gui.Enabled
                end
                gui.Enabled = false
            elseif hidden[gui] ~= nil then
                gui.Enabled = hidden[gui] or TERMINAL_SCREENS[gui.Name] ~= nil or VIP_SCREENS[gui.Name] ~= nil
                hidden[gui] = nil
            end
        end
    end
    -- (no spectating someone else's Quin outside a terminal)
    if not admin and not atTerminal then
        local spec = shared.SpectatedQuin or _G.SpectatedQuin
        if spec or (Workspace:GetAttribute("SpectatedQuin") or "") ~= "" then
            shared.SpectatedQuin, _G.SpectatedQuin = nil, nil
            Workspace:SetAttribute("SpectatedQuin", "")
        end
    end
end

player:GetAttributeChangedSignal("SkylarkRole"):Connect(reconcile)
task.spawn(function()
    while true do
        reconcile()
        task.wait(0.25)
    end
end)
