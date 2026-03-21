--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SSA        = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Assets     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("AnimationAssets"))
local StateNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("StateNames"))

local RUN_THRESHOLD = 17
local P = Enum.AnimationPriority

local STATES: { [string]: Types.IStateDefinition } = table.freeze({
	[StateNames.Idle] = {
		animationId = Assets.Idle,
		fadeTime    = 0.2,
		looped      = true,
		priority    = P.Idle,
		guard       = nil,
		isAction    = false,
	},
	[StateNames.Walk] = {
		animationId = Assets.Walk,
		fadeTime    = 0.15,
		looped      = true,
		priority    = P.Movement,
		guard       = nil,
		isAction    = false,
	},
	[StateNames.Run] = {
		animationId = Assets.Run,
		fadeTime    = 0.1,
		looped      = true,
		priority    = P.Movement,
		guard       = nil,
		isAction    = false,
	},
	[StateNames.Jump] = {
		animationId = Assets.Jump,
		fadeTime    = 0.1,
		looped      = false,
		priority    = P.Movement,
		guard       = function(currentState: string?)
			return currentState ~= StateNames.Swim
		end,
		isAction    = false,
	},
	[StateNames.Fall] = {
		animationId = Assets.Fall,
		fadeTime    = 0.1,
		looped      = false,
		priority    = P.Movement,
		guard       = nil,
		isAction    = false,
	},
	[StateNames.Swim] = {
		animationId = Assets.Swim,
		fadeTime    = 0.2,
		looped      = true,
		priority    = P.Movement,
		guard       = nil,
		isAction    = false,
	},
	[StateNames.Climb] = {
		animationId = Assets.Climb,
		fadeTime    = 0.15,
		looped      = true,
		priority    = P.Movement,
		guard       = nil,
		isAction    = false,
	},
})

local LocomotionStates = {}

function LocomotionStates.init()
	local stateMachine = SSA.GetController("StateMachineController") :: Types.IStateMachineController
	stateMachine.RegisterStates(STATES)
	stateMachine.SetRunThreshold(RUN_THRESHOLD)
end

function LocomotionStates.start() end

return LocomotionStates
