--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SSA        = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local StateNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("StateNames"))
local Trove      = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("trove"))
local AnimationNet =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationNet"):WaitForChild("Client"))

-- UX/bandwidth guard only — not a security boundary.
-- Must be strictly less than RATE_LIMIT_INTERVAL in AnimationService.
local MIN_ACTION_COOLDOWN = 0.2

local function wrapDisconnect(fn: () -> ()): { Disconnect: () -> () }
	return { Disconnect = fn }
end

local StateMachineController = {}

local _states: { [string]: Types.IStateDefinition } = {}
local _currentState: string?
local _animController: Types.IAnimationController?
local _humanoid: Humanoid?
local _runThreshold: number = 0
local _isSetup: boolean = false
local _destroyed: boolean = false
local _remotePlayerStates: { [Player]: string } = {}
local _characterTrove: typeof(Trove.new())
local _globalTrove: typeof(Trove.new())
local _lastRequestTime: { [string]: number } = {}
local _setupToken: number = 0

local function _applyTransition(stateName: string, definition: Types.IStateDefinition): boolean
	if not _animController then
		warn("StateMachineController: AnimationController is unavailable")
		return false
	end
	if definition.guard and not definition.guard(_currentState) then
		return false
	end
	local outgoingFadeTime = if _currentState and _states[_currentState] then _states[_currentState].fadeTime else nil
	local success = _animController.Play(stateName, definition, outgoingFadeTime)
	if not success then
		return false
	end
	_currentState = stateName
	return true
end

local function _transitionApproved(stateName: string)
	if not _isSetup then
		return
	end
	local definition = _states[stateName]
	if not definition then
		warn("StateMachineController: Approved state '" .. stateName .. "' not found in local registry")
		return
	end
	_applyTransition(stateName, definition)
end

local function _setupHybridDetection(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if not character.Parent or _destroyed then
		return
	end
	_humanoid = humanoid

	_characterTrove:Add(_humanoid.StateChanged:Connect(function(_, newState)
		if not _isSetup then
			return
		end

		if newState == Enum.HumanoidStateType.Jumping then
			StateMachineController.TransitionTo(StateNames.Jump)
		elseif newState == Enum.HumanoidStateType.Freefall then
			StateMachineController.TransitionTo(StateNames.Fall)
		elseif newState == Enum.HumanoidStateType.Swimming then
			StateMachineController.TransitionTo(StateNames.Swim)
		elseif newState == Enum.HumanoidStateType.Climbing then
			StateMachineController.TransitionTo(StateNames.Climb)
		elseif newState == Enum.HumanoidStateType.Dead then
			_humanoid = nil
			_characterTrove:Clean()
			if not _animController then
				warn("StateMachineController: AnimationController is unavailable")
				return
			end
			local outgoingFadeTime = if _currentState and _states[_currentState]
				then _states[_currentState].fadeTime
				else nil
			_animController.Stop(outgoingFadeTime)
			_currentState = nil
		elseif newState == Enum.HumanoidStateType.Running then
			_currentState = nil
		end
	end))

	_characterTrove:Add(RunService.Heartbeat:Connect(function()
		if not _isSetup then
			return
		end
		if not _humanoid or not _humanoid.Parent then
			return
		end

		local groundState = _currentState == StateNames.Idle
			or _currentState == StateNames.Walk
			or _currentState == StateNames.Run
			or _currentState == nil
		if not groundState then
			return
		end

		local rootPart = _humanoid.RootPart
		local magnitude = if rootPart
			then Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
			else 0

		if magnitude < 0.1 then
			StateMachineController.TransitionTo(StateNames.Idle)
		elseif magnitude < _runThreshold then
			StateMachineController.TransitionTo(StateNames.Walk)
		else
			StateMachineController.TransitionTo(StateNames.Run)
		end
	end))
end

function StateMachineController.init()
	_animController = SSA.GetController("AnimationController") :: Types.IAnimationController
	_isSetup = false
	_destroyed = false
	_currentState = nil
	_humanoid = nil
	_runThreshold = 0
	_setupToken = 0
	_states = {}
	_remotePlayerStates = {}
	table.clear(_lastRequestTime)
	if _characterTrove then
		_characterTrove:Destroy()
	end
	if _globalTrove then
		_globalTrove:Destroy()
	end
	_characterTrove = Trove.new()
	_globalTrove = Trove.new()
end

function StateMachineController.start()
	_globalTrove:Add(wrapDisconnect(AnimationNet.ActionStateApproved.On(function(stateName: string)
		_transitionApproved(stateName)
	end)))

	_globalTrove:Add(wrapDisconnect(AnimationNet.ActionStateReplicated.On(function(data)
		_remotePlayerStates[data.Player] = data.StateName
	end)))

	_globalTrove:Add(Players.PlayerRemoving:Connect(function(player: Player)
		_remotePlayerStates[player] = nil
	end))

	if not _animController then
		warn("StateMachineController: AnimationController is unavailable")
		return
	end

	_animController.WaitUntilReady()

	-- All RegisterStates() calls from state module inits have completed by this point.
	-- It is now safe to open transitions.
	_isSetup = true

	local localPlayer = Players.LocalPlayer

	if localPlayer.Character then
		if _destroyed then
			return
		end
		_setupHybridDetection(localPlayer.Character)
	end

	_globalTrove:Add(localPlayer.CharacterAdded:Connect(function(newCharacter: Model)
		_characterTrove:Clean()
		_setupToken += 1
		local token = _setupToken

		if not _animController then
			warn("StateMachineController: AnimationController is unavailable")
			return
		end

		_animController.WaitUntilReady()

		if _destroyed or token ~= _setupToken then
			return
		end

		_setupHybridDetection(newCharacter)
	end))

	-- Auto-Idle: resolve initial ground state once the animator is ready.
	if _states[StateNames.Idle] ~= nil and _currentState == nil then
		task.spawn(function()
			local ok, err = pcall(function()
				if not _animController then
					warn("StateMachineController: Auto-Idle skipped — AnimationController not available")
					return
				end
				_animController.WaitUntilReady()
				if _currentState == nil then
					StateMachineController.TransitionTo(StateNames.Idle)
				end
			end)
			if not ok then
				warn("StateMachineController: Auto-Idle transition failed — " .. tostring(err))
			end
		end)
	end
end

-- Merges a batch of states into the registry. Safe to call from multiple module inits.
-- Validates the incoming batch immediately; warns on duplicates.
function StateMachineController.RegisterStates(states: { [string]: Types.IStateDefinition })
	local StateValidator = SSA.GetUtil("StateValidator") :: any
	if StateValidator then
		local result = StateValidator.Validate(states)
		for _, warning in ipairs(result.warnings) do
			warn("StateMachineController.RegisterStates: " .. warning)
		end
		if not StateValidator.IsValid(result) then
			for _, err in ipairs(result.errors) do
				warn("StateMachineController.RegisterStates: ERROR — " .. err)
			end
			warn("StateMachineController.RegisterStates: batch rejected — fix errors above")
			return
		end
	end

	for name, def in pairs(states) do
		if _states[name] ~= nil then
			warn(`StateMachineController.RegisterStates: duplicate state "{name}" — overwriting previous definition`)
		end
		_states[name] = def
	end
end

-- Called once by whichever module owns locomotion (LocomotionStates).
function StateMachineController.SetRunThreshold(threshold: number)
	_runThreshold = threshold
end

function StateMachineController.RegisterState(name: string, definition: Types.IStateDefinition)
	_states[name] = definition
end

function StateMachineController.TransitionTo(stateName: string): boolean
	if _destroyed then
		warn("StateMachineController: TransitionTo called after Destroy()")
		return false
	end
	if not _isSetup then
		warn("StateMachineController: TransitionTo called before setup is complete")
		return false
	end

	local definition = _states[stateName]
	if not definition then
		warn("StateMachineController: Unknown state '" .. stateName .. "'")
		return false
	end
	if stateName == _currentState then
		return true
	end
	if definition.isAction == true then
		return false
	end

	return _applyTransition(stateName, definition)
end

function StateMachineController.RequestActionState(stateName: string)
	if _destroyed then
		warn("StateMachineController: RequestActionState called after Destroy()")
		return
	end
	if not _isSetup then
		warn("StateMachineController: RequestActionState called before setup is complete")
		return
	end

	local definition = _states[stateName]
	if not definition then
		warn("StateMachineController: Unknown state '" .. stateName .. "'")
		return
	end
	if definition.isAction ~= true then
		warn("StateMachineController: '" .. stateName .. "' is not an action state. Use TransitionTo() instead.")
		return
	end

	local now = os.clock()
	if (now - (_lastRequestTime[stateName] or 0)) < MIN_ACTION_COOLDOWN then
		return
	end
	_lastRequestTime[stateName] = now

	local ok, err = pcall(function()
		AnimationNet.RequestActionState.Fire(stateName)
	end)
	if not ok then
		warn("StateMachineController: Fire failed — " .. tostring(err))
	end
end

function StateMachineController.GetCurrentState(): string?
	return _currentState
end

function StateMachineController.GetRemotePlayerState(player: Player): string?
	return _remotePlayerStates[player]
end

function StateMachineController.Destroy()
	_setupToken += 1
	_destroyed = true
	_globalTrove:Clean()
	_characterTrove:Clean()
	_animController = nil
	_humanoid = nil
	table.clear(_states)
	table.clear(_remotePlayerStates)
	table.clear(_lastRequestTime)
	_currentState = nil
	_isSetup = false
end

return StateMachineController
