--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("trove"))
local AnimationNet =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationNet"):WaitForChild("Client"))

-- UX/bandwidth guard only — not a security boundary.
-- Must be strictly less than RATE_LIMIT_INTERVAL in AnimationService.
local MIN_ACTION_COOLDOWN = 0.2

-- Wraps a Blink disconnect function so Trove routes cleanup through :Disconnect()
-- (synchronous, error-surfacing) rather than task.spawn.
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
			StateMachineController.TransitionTo("Jump")
		elseif newState == Enum.HumanoidStateType.Freefall then
			StateMachineController.TransitionTo("Fall")
		elseif newState == Enum.HumanoidStateType.Swimming then
			StateMachineController.TransitionTo("Swim")
		elseif newState == Enum.HumanoidStateType.Climbing then
			StateMachineController.TransitionTo("Climb")
		elseif newState == Enum.HumanoidStateType.Dead then
			-- Nil _humanoid before cleaning the trove so the Heartbeat guard sees nil
			-- immediately and cannot slip through in the same frame.
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
			-- Clear _currentState so the Heartbeat loop can immediately resolve the
			-- correct Idle/Walk/Run on the next frame after landing.
			_currentState = nil
		end
		-- Landed intentionally omitted: Heartbeat resolves ground state within one frame.
	end))

	_characterTrove:Add(RunService.Heartbeat:Connect(function()
		if not _isSetup then
			return
		end
		if not _humanoid or not _humanoid.Parent then
			return
		end
		if _currentState ~= "Idle" and _currentState ~= "Walk" and _currentState ~= "Run" and _currentState ~= nil then
			return
		end

		local rootPart = _humanoid.RootPart
		local magnitude = if rootPart
			then Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
			else 0

		if magnitude < 0.1 then
			StateMachineController.TransitionTo("Idle")
		elseif magnitude < _runThreshold then
			StateMachineController.TransitionTo("Walk")
		else
			StateMachineController.TransitionTo("Run")
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
end

-- Merges states into the registry and sets the run threshold.
-- Repeated calls accumulate states rather than replacing the full set.
function StateMachineController.Setup(states: { [string]: Types.IStateDefinition }, runThreshold: number)
	for k, v in pairs(states) do
		_states[k] = v
	end
	_runThreshold = runThreshold
	_isSetup = true

	if _currentState == nil and _states["Idle"] ~= nil then
		task.spawn(function()
			local ok, err = pcall(function()
				if not _animController then
					warn("StateMachineController: Auto-Idle skipped — AnimationController not available")
					return
				end
				_animController.WaitUntilReady()
				if _currentState == nil then
					StateMachineController.TransitionTo("Idle")
				end
			end)
			if not ok then
				warn("StateMachineController: Auto-Idle transition failed — " .. tostring(err))
			end
		end)
	end
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
		warn("StateMachineController: TransitionTo called before Setup()")
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
		warn("StateMachineController: RequestActionState called before Setup()")
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
	-- Increment token first so any mid-yield CharacterAdded callbacks abort.
	_setupToken += 1
	_destroyed = true
	-- Clean global first so no new character connections can be registered
	-- after we clean _characterTrove.
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
