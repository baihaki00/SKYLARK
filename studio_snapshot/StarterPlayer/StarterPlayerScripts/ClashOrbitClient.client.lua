--// ClashOrbitClient.client.lua
-- Draws every mid-air clash orbit on this screen from its own run of the shared path
-- (Modules/ClashOrbit), so the fast curving flight is smooth instead of arriving in the
-- server's uneven replication steps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClashOrbit = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ClashOrbit"))
ClashOrbit.startClient()
