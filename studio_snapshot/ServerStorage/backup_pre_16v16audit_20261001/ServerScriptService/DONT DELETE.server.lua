--WILL USE THIS LATER DONT DELETE

--local Players = game:GetService("Players")

---- Replace this with the actual AnimationId of YBOT_RUNNINGWITHFOOTSTEPs
--local YBOT_RUNNINGWITHFOOTSTEPS_ID = "rbxassetid://108246513830939"

---- Replace this with the asset id of your footstep sound
--local FOOTSTEP_SOUND_ID = "rbxassetid://142665235"

--local function playFootstepSound(character)
--    -- Try to find an existing footstep sound in the character
--    local sound = character:FindFirstChild("FootstepSound")
--    if not sound then
--        sound = Instance.new("Sound")
--        sound.Name = "FootstepSound"
--        sound.SoundId = FOOTSTEP_SOUND_ID
--        sound.Volume = 0.5
--        sound.Parent = character
--    end
--    sound:Play()
--end

--local function onTrackPlayed(track, character)
--    if track.Animation and track.Animation.AnimationId == YBOT_RUNNINGWITHFOOTSTEPS_ID then
--        local markerSignal = track:GetMarkerReachedSignal("Footstep")
--        markerSignal:Connect(function()
--            playFootstepSound(character)
--        end)
--    end
--end

--local function setupCharacter(character)
--    local humanoid = character:FindFirstChildOfClass("Humanoid")
--    if humanoid then
--        local animator = humanoid:FindFirstChildOfClass("Animator")
--        if animator then
--            animator.AnimationPlayed:Connect(function(track)
--                onTrackPlayed(track, character)
--            end)
--            -- Also connect to currently playing tracks (if any)
--            local tracks = animator:GetPlayingAnimationTracks()
--            for i, track in tracks do
--                onTrackPlayed(track, character)
--            end
--        end
--    end
--end

--Players.PlayerAdded:Connect(function(player)
--    player.CharacterAdded:Connect(setupCharacter)
--    if player.Character then
--        setupCharacter(player.Character)
--    end
--end)

--for i, player in Players:GetPlayers() do
--    player.CharacterAdded:Connect(setupCharacter)
--    if player.Character then
--        setupCharacter(player.Character)
--    end
--end

