--!strict
-- Server-validated action states.
-- Every state here must also be registered server-side via AnimationService.RegisterActionState().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("AnimationAssets"))
local StateNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("StateNames"))

local P = Enum.AnimationPriority

local STATES: { [string]: Types.IStateDefinition } = table.freeze({
	[StateNames.Emote] = {
		animationId = Assets.Emote,
		fadeTime = 0.3,
		looped = false,
		priority = P.Action,
		guard = nil,
		isAction = true,
	},
	[StateNames.Stun] = {
		animationId = Assets.Stun,
		fadeTime = 0.2,
		looped = true,
		priority = P.Action2,
		guard = function(currentState: string?)
			return currentState ~= nil
		end,
		isAction = true,
	},
})

local ActionStates = {}

function ActionStates.init() end

function ActionStates.start()
	local stateMachine = SSA.GetController("StateMachineController") :: Types.IStateMachineController
	stateMachine.RegisterStates(STATES)
end

return ActionStates
