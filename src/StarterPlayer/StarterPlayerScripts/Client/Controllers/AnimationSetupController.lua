--!strict
-- StarterPlayerScripts/Client/Controllers/AnimationSetupController.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local RUN_THRESHOLD = 17 -- studs/sec. Tune using the [StateMachine] print output.

local IAnimationSetupController = {}

local _stateMachine: Types.IStateMachineController

function IAnimationSetupController.init()
	_stateMachine = SSA.GetController("StateMachineController") :: Types.IStateMachineController
end

function IAnimationSetupController.start()
	local states: {[string]: Types.IStateDefinition} = {
		Idle = {
			animationId = "rbxassetid://86677748592544",
			fadeTime    = 0.2,
			looped      = true,
			priority    = Enum.AnimationPriority.Idle,
			guard       = nil,
			isAction    = false,
		},
		Walk = {
			animationId = "rbxassetid://96929137427604",
			fadeTime    = 0.15,
			looped      = true,
			priority    = Enum.AnimationPriority.Movement,
			guard       = nil,
			isAction    = false,
		},
		Run = {
			animationId = "rbxassetid://126575723824558",
			fadeTime    = 0.1,
			looped      = true,
			priority    = Enum.AnimationPriority.Movement,
			guard       = nil,
			isAction    = false,
		},
		Jump = {
			animationId = "rbxassetid://125750702",
			fadeTime    = 0.1,
			looped      = false,
			priority    = Enum.AnimationPriority.Movement,
			guard       = function(currentState: string?) return currentState ~= "Swim" end,
			isAction    = false,
		},
		Fall = {
			animationId = "rbxassetid://180436148",
			fadeTime    = 0.1,
			looped      = false,
			priority    = Enum.AnimationPriority.Movement,
			guard       = nil,
			isAction    = false,
		},
		Swim = {
			animationId = "rbxassetid://180436148",
			fadeTime    = 0.2,
			looped      = true,
			priority    = Enum.AnimationPriority.Movement,
			guard       = nil,
			isAction    = false,
		},
		Climb = {
			animationId = "rbxassetid://180436334",
			fadeTime    = 0.15,
			looped      = true,
			priority    = Enum.AnimationPriority.Movement,
			guard       = nil,
			isAction    = false,
		},
		Emote = {
			animationId = "rbxassetid://0",
			fadeTime    = 0.3,
			looped      = false,
			priority    = Enum.AnimationPriority.Action,
			guard       = nil,
			isAction    = true,
		},
		Stun = {
			animationId = "rbxassetid://0",
			fadeTime    = 0.2,
			looped      = true,
			priority    = Enum.AnimationPriority.Action2,
			guard       = function(currentState: string?) return currentState ~= "Dead" end,
			isAction    = false,
		},
	}

	_stateMachine.Setup(states, RUN_THRESHOLD)
end

return IAnimationSetupController