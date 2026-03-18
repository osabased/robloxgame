--!strict
-- ServerScriptService/Server/Services/AnimationSetupService.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- NEVER call SSA getters at root level.
local IAnimationSetupService = {}

local _animationService: Types.IAnimationService

function IAnimationSetupService.init()
	_animationService = SSA.GetService("AnimationService") :: Types.IAnimationService
end

function IAnimationSetupService.start()
	-- RegisterActionState() must be called before clients can have their requests approved. The whitelist on the server is the single source of truth for which action states are valid.
	_animationService.RegisterActionState("Emote")

	-- Example: dummyBindable.Event:Connect(function(player: Player, isStunned: boolean)
	-- 	_animationService.SetPlayerCondition(player, "stunned", isStunned)
	-- end)
end

return IAnimationSetupService
