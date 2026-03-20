--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local AnimationSetupService = {}

local _animationService: Types.IAnimationService

function AnimationSetupService.init()
	_animationService = SSA.GetService("AnimationService") :: Types.IAnimationService
end

function AnimationSetupService.start()
	-- Must be called before clients can have requests approved.
	_animationService.RegisterActionState("Emote")
end

return AnimationSetupService
