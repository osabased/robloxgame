--!strict
-- ServerScriptService/Server/Services/AnimationService.luau
--
-- Networking is handled by the Blink-generated AnimationNet module.
-- See src/ReplicatedStorage/Shared/animations.blink for the schema.
-- If AnimationNet is missing, run: blink src/ReplicatedStorage/Shared/animations.blink

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Blink-generated server module. Compile animations.blink to regenerate.
local AnimationNet =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationNet"):WaitForChild("Server"))

-- Authoritative minimum interval between approved action requests per player.
-- MIN_ACTION_COOLDOWN in StateMachineController MUST be set strictly lower than this.
local RATE_LIMIT_INTERVAL = 0.3

local AnimationService = {}

local _actionStateWhitelist: { [string]: true }
local _playerData: { [Player]: { lastRequestTime: number, conditions: { [string]: boolean } } }
-- Disconnect handle for the RequestActionState listener registered in start().
-- Guards against double-start() leaking the first listener.
-- If a Destroy() path is added to this service, call this to clean up the listener.
local _requestListenerDisconnect: (() -> ())?
-- Stored so double-start() can be detected. Also allows future Destroy() implementation.
local _playerRemovingConn: RBXScriptConnection?

function AnimationService.init()
	_actionStateWhitelist = {}
	_playerData = {}
	-- Disconnect any prior listeners from a previous lifecycle (e.g. test harness re-init).
	if _requestListenerDisconnect then
		_requestListenerDisconnect()
		_requestListenerDisconnect = nil
	end
	if _playerRemovingConn then
		_playerRemovingConn:Disconnect()
		_playerRemovingConn = nil
	end
end

function AnimationService.start()
	-- Guard against double-start(): SingleAsync silently drops the second listener,
	-- but without this guard the first listener's disconnect handle would be overwritten
	-- and leaked. init() clears the handle, so this guard only triggers on a true
	-- double-start() within the same lifecycle.
	if _requestListenerDisconnect then
		warn("AnimationService: start() called more than once — ignoring")
		return
	end

	-- Blink validates that stateName is a non-empty string(1..32) before this handler
	-- fires, so no manual type guard is required here.
	_requestListenerDisconnect = AnimationNet.RequestActionState.On(function(player: Player, stateName: string)
		if _actionStateWhitelist[stateName] ~= true then
			-- Silent rejection: prevents the client from learning which state names are valid.
			return
		end

		if _playerData[player] == nil then
			_playerData[player] = { lastRequestTime = 0, conditions = {} }
		end

		-- Capture once and reuse for both the rate-limit check and the timestamp update.
		local now = os.clock()
		if now - _playerData[player].lastRequestTime < RATE_LIMIT_INTERVAL then
			return
		end

		for _, isActive in pairs(_playerData[player].conditions) do
			if isActive then
				-- Any active disabling condition (e.g. "stunned", "dead") blocks the transition.
				-- Conditions are registered externally via SetPlayerCondition().
				return
			end
		end

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and (humanoid :: Humanoid).Health <= 0 then
				return
			end
		end

		_playerData[player].lastRequestTime = now

		-- Approve to the requesting client.
		AnimationNet.ActionStateApproved.Fire(player, stateName)

		-- Replicate to all other clients via Blink's built-in FireExcept.
		AnimationNet.ActionStateReplicated.FireExcept(player, {
			Player = player,
			StateName = stateName,
		})
	end)

	_playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
		_playerData[player] = nil
	end)
end

-- Adds a state name to the server whitelist. Must be called before clients can have
-- requests for that state approved. The whitelist is the single source of truth.
function AnimationService.RegisterActionState(name: string)
	_actionStateWhitelist[name] = true
end

-- Sets or clears a blocking condition for a player (e.g. "stunned", "dead").
-- Any condition with value = true will silently reject incoming action state requests.
-- Guards against re-creating a _playerData entry for a player who has already departed
-- (their PlayerRemoving event cleared the entry and set parent to nil).
function AnimationService.SetPlayerCondition(player: Player, condition: string, value: boolean)
	-- player.Parent is nil once the Player instance has been removed from Players.
	-- Proceeding after departure would re-create a _playerData entry that will never
	-- be cleaned up by PlayerRemoving (which already fired).
	if player.Parent == nil then
		return
	end
	if _playerData[player] == nil then
		_playerData[player] = { lastRequestTime = 0, conditions = {} }
	end
	_playerData[player].conditions[condition] = value
end

return AnimationService
