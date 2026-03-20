--!strict
-- StarterPlayerScripts/Client/Controllers/StateMachineController.luau
--
-- Two-phase lifecycle:
--   1. init()  — resolves collaborators from SSA; resets all module state.
--   2. start() — wires Blink listeners and begins character tracking.
--   Setup()    — registers states and run threshold; must be called after start().
--
-- Action states (isAction = true) are routed through RequestActionState(), which fires
-- a Blink remote to the server for validation before the animation is authorised and
-- broadcast to all other clients.
--
-- Networking: all three animation remotes are multiplexed over Blink's shared reliable
-- channel. See src/ReplicatedStorage/Shared/animations.blink for the schema and compile
-- instructions. The generated AnimationNet/Client module must exist at
-- ReplicatedStorage.Shared.AnimationNet.Client.
--
-- Connection lifetime:
--   _characterTrove — per-character connections (StateChanged, Heartbeat).
--                     Cleaned on each CharacterAdded and on Destroy().
--   _globalTrove    — session-lifetime connections (Blink listeners, PlayerRemoving,
--                     CharacterAdded). Cleaned only on Destroy().
--
-- Blink disconnect handles: Blink's .On() returns a plain function. To ensure Trove
-- calls it synchronously and with visible errors (rather than spawning it), we wrap
-- each disconnect in a ConnectionLike table so Trove takes the :Disconnect() path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- Trove is available at Packages/trove.lua. Adjust the require path to match your
-- Rojo project mapping if Packages is not at ReplicatedStorage.Packages.
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("trove"))

-- Blink-generated client module. Compile animations.blink to regenerate.
local AnimationNet =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationNet"):WaitForChild("Client"))

-- UX / bandwidth guard only. NOT a security boundary — the server's RATE_LIMIT_INTERVAL
-- (currently 0.3 s in AnimationService) is the authoritative gate. This value MUST be
-- strictly less than RATE_LIMIT_INTERVAL to avoid pointless server-side rejections.
local MIN_ACTION_COOLDOWN = 0.2 -- seconds

-- Wraps a Blink disconnect function in a ConnectionLike table so Trove routes cleanup
-- through :Disconnect() (direct call, not task.spawn). This makes teardown synchronous
-- and surfaces any errors thrown by the disconnect rather than swallowing them.
local function wrapDisconnect(fn: () -> ()): { Disconnect: () -> () }
	return { Disconnect = fn }
end

local StateMachineController = {}

-- All module-level variables are explicitly reset in init() so that re-init (e.g. in
-- test harnesses) starts from a clean slate without any state leaking from a prior lifecycle.
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
-- Stores os.clock() timestamps. UX/bandwidth guard only — not a security boundary.
local _lastRequestTime: { [string]: number } = {}
-- Monotonically increasing token used to discard CharacterAdded callbacks that were
-- queued before a superseding CharacterAdded or a Destroy() call.
local _setupToken: number = 0

-- Shared transition path: runs the guard, computes the outgoing fade time, plays the
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

-- Called by the Blink ActionStateApproved listener.
-- Silently drops approvals that arrive before Setup() completes — this is normal during
-- the startup window and is not logged as a warning.
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

-- Wires per-character Heartbeat and StateChanged connections into _characterTrove.
-- Must only be called after _characterTrove:Clean() has been called to clear the prior
-- character's connections.
local function _setupHybridDetection(character: Model)
	-- WaitForChild yields; guard against the character being destroyed during the wait
	-- (e.g. rapid server-side respawn or a test teardown).
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Re-check both character validity and module liveness after the yield.
	-- Without the _destroyed check, a Destroy() call during the WaitForChild yield would
	-- cause connections to be added to an already-cleaned _characterTrove, leaking them.
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
			-- Nil _humanoid BEFORE cleaning the trove so the Heartbeat guard (`if not
			-- _humanoid`) sees nil immediately. Without this ordering, a Heartbeat
			-- callback dispatched in the same frame but not yet resumed could slip past
			-- the guard while _humanoid is still non-nil.
			_humanoid = nil
			-- Sever all per-character listeners so the settling ragdoll cannot fire
			-- further transitions (e.g. Landed) against a nil _currentState.
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
			-- HumanoidStateType.Running fires whenever the player returns to ground
			-- (including after Jump/Fall/Swim/Climb). Clear _currentState so the
			-- Heartbeat guard (`_currentState ~= nil`) is satisfied and the loop can
			-- immediately resolve the correct Idle/Walk/Run state on the next frame.
			--
			-- ROOT-CAUSE FIX: Without this, _currentState stays "Jump"/"Fall"/etc.
			-- after landing. The Heartbeat guard bails out early for any state that
			-- isn't Idle/Walk/Run/nil, so locomotion animations never resume and the
			-- player slides around with no animation.
			_currentState = nil
		end
		-- Landed is intentionally omitted: the Heartbeat loop resolves the correct ground
		-- state within one frame, preventing a spurious Idle flash on landing while moving.
	end))

	_characterTrove:Add(RunService.Heartbeat:Connect(function()
		if not _isSetup then
			return
		end
		-- A destroyed Instance is not nil in Luau; guard the Parent to detect removal.
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
	-- Guard against re-init without a preceding Destroy(): clean the existing Troves
	-- before creating new ones so their connections are not abandoned and leaked.
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
	-- Wire Blink listeners. wrapDisconnect() converts the plain function returned by
	-- .On() into a ConnectionLike so Trove calls :Disconnect() directly (synchronous,
	-- error-surfacing) rather than routing through task.spawn.
	_globalTrove:Add(wrapDisconnect(AnimationNet.ActionStateApproved.On(function(stateName: string)
		_transitionApproved(stateName)
	end)))

	-- Player field is Instance(Player) (non-optional per schema) — no nil check required.
	_globalTrove:Add(wrapDisconnect(AnimationNet.ActionStateReplicated.On(function(data)
		_remotePlayerStates[data.Player] = data.StateName
	end)))

	-- Remove stale entries when players leave to prevent unbounded memory growth
	-- proportional to player churn over a session's lifetime.
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
		-- Guard against Destroy() called during the WaitUntilReady yield above.
		-- _setupHybridDetection also re-checks _destroyed after its internal WaitForChild
		-- yield, but this outer guard avoids the call entirely when already destroyed.
		if _destroyed then
			return
		end
		_setupHybridDetection(localPlayer.Character)
	end

	_globalTrove:Add(localPlayer.CharacterAdded:Connect(function(newCharacter: Model)
		-- Sever old character connections immediately, before yielding, so events from
		-- the prior character cannot fire during the WaitUntilReady window.
		_characterTrove:Clean()
		_setupToken += 1
		local token = _setupToken

		if not _animController then
			warn("StateMachineController: AnimationController is unavailable")
			return
		end

		_animController.WaitUntilReady()

		-- Guard against Destroy() or a newer CharacterAdded superseding this token
		-- during the WaitUntilReady yield window.
		if _destroyed or token ~= _setupToken then
			return
		end

		_setupHybridDetection(newCharacter)
	end))
end

-- Registers a batch of state definitions and sets the run speed threshold.
-- States are merged into the existing table; repeated calls accumulate states rather
-- than replacing the full set. Call after start() but before player input is live.
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

-- Registers a single state definition. For runtime additions after startup (e.g. DLC
-- states loaded on demand). Prefer Setup() for batch registration at startup.
function StateMachineController.RegisterState(name: string, definition: Types.IStateDefinition)
	_states[name] = definition
end

-- Attempts a client-authoritative transition to the named state.
-- Returns false without warning if stateName == _currentState (no-op).
-- Returns false without warning if the state has isAction = true (use RequestActionState).
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

-- Fires a server validation request for an action state.
-- The transition is only applied locally after the server responds via ActionStateApproved.
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
	-- Defence-in-depth: prevents arbitrary strings from reaching FireServer.
	-- The server independently validates against its whitelist regardless.
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

-- Tears down all connections and resets all module state. Safe to call from character
-- cleanup paths or test harnesses without requiring a full place reload.
function StateMachineController.Destroy()
	-- Increment token first so any CharacterAdded callback mid-yield at WaitUntilReady
	-- will see _destroyed = true or a token mismatch and return without registering
	-- new connections.
	_setupToken += 1
	_destroyed = true
	-- Clean global first: removes Blink listeners and CharacterAdded so no new character
	-- connections can be registered after we clean _characterTrove.
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
