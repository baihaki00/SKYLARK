--// NpcChatBubbles.client.lua
-- What the NPC owners and their friends say (ArenaNpcOwners -> ReplicatedStorage.NpcSay), shown
-- the same way as the stands' chatter (ArenaCrowdClient): a chat bubble over the head, only when
-- the camera is within BUBBLE_RANGE studs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local BUBBLE_RANGE = 90 -- (as the stands)

local remote = ReplicatedStorage:WaitForChild("NpcSay")
remote.OnClientEvent:Connect(function(head, text)
    local camera = Workspace.CurrentCamera
    if typeof(head) ~= "Instance" or not head:IsA("BasePart") or not head.Parent or not camera then
        return
    end
    if (head.Position - camera.CFrame.Position).Magnitude < BUBBLE_RANGE then
        pcall(function()
            TextChatService:DisplayBubble(head, text)
        end)
    end
end)
