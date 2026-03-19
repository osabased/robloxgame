--!strict
-- StarterPlayerScripts/Client/Controllers/StateMachineController.luau
--
-- Two-phase lifecycle:
--   1. init()  — resolves collaborators from SSA; called once at framework startup.
--   2. start() — wires RemoteEvents and begins character tracking; called after init().
--   Setup()    — registers states and run threshold; must be called after start().
--
-- Action states (isAction = true) are routed through a server request rather than
-- applied locally, because they require server-side validation (e.g. attack cooldowns,
-- anti-exploit checks) before the animation is authorised and broadcast to other clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- UX / bandwidth guard only. Must be strictly less than AnimationService.RATE_LIMIT_INTERVAL
-- (currently 0.3 s). This is NOT a security boundary — the server's RATE_LIMIT_INTERVAL is
-- the authoritative gate. An exploiter can bypass this client-side check entirely.
local MIN_ACTION_COOLDOWN = 0.2 -- seconds; prevents server remote queue from being flooded

local StateMachineController = {}

local _states: { [string]: Types.IStateDefinition } = {}
local _currentState: string?
local _animController: Types.IAnimationController?
local _humanoid: Humanoid?
local _runThreshold: number = 0
local _isSetup: boolean = false
local _destroyed: boolean = false
local _remotePlayerStates: { [Player]: string } = {}
local _reqRemote: RemoteEvent?
local _approvedRemote: RemoteEvent?
local _replicatedRemote: RemoteEvent?
local _hybridConnections: { RBXScriptConnection } = {}
-- Stores os.clock() timestamps. UX/bandwidth guard only — not a security boundary.
local _lastRequestTime: { [string]: number } = {}
local _setupToken: number = 0

-- Shared transition path: runs the guard, computes outgoing fade time, plays the
-- animation, and updates _currentState. Returns true if the transition was applied.
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
		warn("StateMachineController: _transitionApproved called before Setup() — ignoring")
		return
	end
	local definition = _states[stateName]
	if not definition then
		warn("StateMachineController: Approved state '" .. stateName .. "' not found in local registry")
		return
	end
	_applyTransition(stateName, definition)
end

local function _disconnectHybridConnections()
	for _, conn in ipairs(_hybridConnections) do
		conn:Disconnect()
	end
	table.clear(_hybridConnections)
end

-- Wires Heartbeat and HumanoidStateType listeners for the given character.
-- Must only be called after old connections have been cleared via _disconnectHybridConnections.
local function _setupHybridDetection(character: Model)
	_humanoid = character:WaitForChild("Humanoid") :: Humanoid

	table.insert(
		_hybridConnections,
		_humanoid.StateChanged:Connect(function(_, newState)
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
				-- Immediately sever all listeners so the settling ragdoll cannot fire
				-- further transitions (e.g. Landed) against a nil _currentState.
				_disconnectHybridConnections()
				_humanoid = nil
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
				-- HumanoidStateType.Running fires for all ground locomotion regardless of speed.
				-- The Heartbeat loop handles the Idle/Walk/Run distinction instead.
			end
			-- Landed is intentionally omitted: the Heartbeat loop resolves the correct
			-- ground state within one frame, preventing a spurious Idle flash on landing
			-- while the character is already moving.
		end)
	)

	table.insert(
		_hybridConnections,
		RunService.Heartbeat:Connect(function()
			if not _isSetup then
				return
			end

			-- A destroyed Instance is not nil in Luau; guard the Parent to detect removal.
			if not _humanoid or not _humanoid.Parent then
				return
			end
			if
				_currentState ~= "Idle"
				and _currentState ~= "Walk"
				and _currentState ~= "Run"
				and _currentState ~= nil
			then
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
		end)
	)
end

function StateMachineController.init()
	_animController = SSA.GetController("AnimationController") :: Types.IAnimationController
	_isSetup = false
	_destroyed = false
	_states = {}
	_remotePlayerStates = {}
	table.clear(_lastRequestTime)
end

function StateMachineController.start()
	local ssaRemotes = ReplicatedStorage:WaitForChild("SSA_Remotes")
	_reqRemote = ssaRemotes:WaitForChild("SSA_RequestActionState") :: RemoteEvent
	_approvedRemote = ssaRemotes:WaitForChild("SSA_ActionStateApproved") :: RemoteEvent
	_replicatedRemote = ssaRemotes:WaitForChild("SSA_ActionStateReplicated") :: RemoteEvent

	_approvedRemote.OnClientEvent:Connect(function(stateName: string)
		if type(stateName) ~= "string" or not _states[stateName] then
			warn("StateMachineController: Received invalid or unknown approved state: " .. tostring(stateName))
			return
		end
		_transitionApproved(stateName)
	end)

	_replicatedRemote.OnClientEvent:Connect(function(player: Player, stateName: string)
		_remotePlayerStates[player] = stateName
	end)

	-- Remove stale entries when players leave to prevent unbounded memory growth
	-- proportional to player churn over a session's lifetime.
	Players.PlayerRemoving:Connect(function(player: Player)
		_remotePlayerStates[player] = nil
	end)

	if not _animController then
		warn("StateMachineController: AnimationController is unavailable")
		return
	end

	_animController.WaitUntilReady()

	local localPlayer = Players.LocalPlayer

	if localPlayer.Character then
		_setupHybridDetection(localPlayer.Character)
	end

	localPlayer.CharacterAdded:Connect(function(newCharacter: Model)
		-- Sever old listeners immediately, before yielding, so events from the
		-- previous character cannot fire during the WaitUntilReady window, and
		-- so a rapid second CharacterAdded cannot register connections twice.
		_disconnectHybridConnections()
		_setupToken += 1
		local token = _setupToken
		_animController.WaitUntilReady()
		if token ~= _setupToken then
			return
		end -- superseded by a newer CharacterAdded
		_setupHybridDetection(newCharacter)
	end)
end

function StateMachineController.Setup(states: { [string]: Types.IStateDefinition }, runThreshold: number)
	for k, v in pairs(states) do
		_states[k] = v
	end
	_runThreshold = runThreshold
	_isSetup = true

	if _currentState == nil and _states["Idle"] ~= nil then
		task.spawn(function()
			local ok, err = pcall(function()
				-- Guard against Setup() being called before start() completes,
				-- which would leave _animController nil and cause a nil-index error.
				if not _animController then
					warn("StateMachineController: Auto-Idle skipped — AnimationController not yet available")
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
	-- Unconditional early-return when the state is unknown or is not an action state.
	-- This is a defence-in-depth measure: the server must independently validate, but
	-- this prevents arbitrary strings from reaching FireServer entirely on the client.
	if not definition then
		warn("StateMachineController: Unknown state '" .. stateName .. "'")
		return
	end
	if definition.isAction ~= true then
		warn("StateMachineController: '" .. stateName .. "' is not an action state. Use TransitionTo() instead.")
		return
	end
	if not _reqRemote then
		warn("StateMachineController: RequestActionState called before RemoteEvents were ready")
		return
	end

	local now = os.clock()
	if (now - (_lastRequestTime[stateName] or 0)) < MIN_ACTION_COOLDOWN then
		return
	end
	_lastRequestTime[stateName] = now

	local ok, err = pcall(function()
		_reqRemote:FireServer(stateName)
	end)
	if not ok then
		warn("StateMachineController: FireServer failed — " .. tostring(err))
	end
end

function StateMachineController.GetCurrentState(): string?
	return _currentState
end

function StateMachineController.GetRemotePlayerState(player: Player): string?
	return _remotePlayerStates[player]
end

-- Tears down all connections and resets all module state. Safe to call from
-- character cleanup paths or test harnesses without requiring a full place reload.
function StateMachineController.Destroy()
	_disconnectHybridConnections()
	_animController = nil
	_humanoid = nil
	_reqRemote = nil
	_approvedRemote = nil
	_replicatedRemote = nil
	table.clear(_states)
	table.clear(_remotePlayerStates)
	table.clear(_lastRequestTime)
	_currentState = nil
	_isSetup = false
	_destroyed = true
end

return StateMachineController
