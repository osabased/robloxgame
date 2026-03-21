--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SSA   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
-- StateNames auto-discovered as a Util; retrieved here to avoid magic strings server-side too.
local StateNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("StateNames"))

local AnimationSetupService = {}

local _animationService: Types.IAnimationService

function AnimationSetupService.init()
	_animationService = SSA.GetService("AnimationService") :: Types.IAnimationService
end

function AnimationSetupService.start()
	-- Register every action state that clients are permitted to request.
	-- This list must stay in sync with the action states defined in ActionStates.lua.
	_animationService.RegisterActionState(StateNames.Emote)
	_animationService.RegisterActionState(StateNames.Stun)
end

return AnimationSetupService
