--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local RUN_THRESHOLD = 17

local STATES: { [string]: Types.IStateDefinition } = {
	Idle = {
		animationId = "rbxassetid://86677748592544",
		fadeTime = 0.2,
		looped = true,
		priority = Enum.AnimationPriority.Idle,
		guard = nil,
		isAction = false,
	},
	Walk = {
		animationId = "rbxassetid://96929137427604",
		fadeTime = 0.15,
		looped = true,
		priority = Enum.AnimationPriority.Movement,
		guard = nil,
		isAction = false,
	},
	Run = {
		animationId = "rbxassetid://126575723824558",
		fadeTime = 0.1,
		looped = true,
		priority = Enum.AnimationPriority.Movement,
		guard = nil,
		isAction = false,
	},
	Jump = {
		animationId = "rbxassetid://125750702",
		fadeTime = 0.1,
		looped = false,
		priority = Enum.AnimationPriority.Movement,
		guard = function(currentState: string?)
			return currentState ~= "Swim"
		end,
		isAction = false,
	},
	Fall = {
		animationId = "rbxassetid://180436148",
		fadeTime = 0.1,
		looped = false,
		priority = Enum.AnimationPriority.Movement,
		guard = nil,
		isAction = false,
	},
	Swim = {
		animationId = "rbxassetid://180436334",
		fadeTime = 0.2,
		looped = true,
		priority = Enum.AnimationPriority.Movement,
		guard = nil,
		isAction = false,
	},
	Climb = {
		animationId = "rbxassetid://180436334",
		fadeTime = 0.15,
		looped = true,
		priority = Enum.AnimationPriority.Movement,
		guard = nil,
		isAction = false,
	},
	-- Issue 4 note: replace "rbxassetid://0" with a real asset ID before shipping.
	Emote = {
		animationId = "rbxassetid://0",
		fadeTime = 0.3,
		looped = false,
		priority = Enum.AnimationPriority.Action,
		guard = nil,
		isAction = true,
	},
	Stun = {
		animationId = "rbxassetid://0",
		fadeTime = 0.2,
		looped = true,
		priority = Enum.AnimationPriority.Action2,
		guard = function(currentState: string?)
			return currentState ~= nil
		end,
		isAction = true,
	},
}

local AnimationSetupController = {}

local _stateMachine: Types.IStateMachineController

function AnimationSetupController.init()
	_stateMachine = SSA.GetController("StateMachineController") :: Types.IStateMachineController
end

function AnimationSetupController.start()
	if not _stateMachine then
		warn("AnimationSetupController: StateMachineController unavailable — skipping setup")
		return
	end

	for stateName, definition in pairs(STATES) do
		if definition.animationId == "rbxassetid://0" or definition.animationId == "" then
			warn(
				"AnimationSetupController: placeholder animationId for state '"
					.. stateName
					.. "' — replace before shipping"
			)
		end
	end

	_stateMachine.Setup(STATES, RUN_THRESHOLD)
end

return AnimationSetupController
