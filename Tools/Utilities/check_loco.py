import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local mod = ReplicatedStorage.QuinCore.Modules.LocomotionModule
local src = mod.Source
local hasDash = src:find("LocomotionModule.dash") ~= nil
local hasSlide = src:find("LocomotionModule.slide") ~= nil

-- In Studio Edit mode, require caches results. Cloning the ModuleScript creates a fresh VM evaluation:
local freshMod = mod:Clone()
local loco = require(freshMod)
local dashFunc = type(loco.dash) == "function"
local slideFunc = type(loco.slide) == "function"

return string.format("Source: hasDash=%s, hasSlide=%s, lines=%d | Fresh require: dash=%s, slide=%s",
    tostring(hasDash), tostring(hasSlide), #src:split("\\n"),
    tostring(dashFunc), tostring(slideFunc))
"""
res = client.execute_luau(code)
print(res)
