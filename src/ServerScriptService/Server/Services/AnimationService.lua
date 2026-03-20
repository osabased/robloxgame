--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationNet =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationNet"):WaitForChild("Server"))

-- Must be strictly greater than MIN_ACTION_COOLDOWN in StateMachineController.
local RATE_LIMIT_INTERVAL = 0.3

local AnimationService = {}

local _actionStateWhitelist: { [string]: true }
local _playerData: { [Player]: { lastRequestTime: number, conditions: { [string]: boolean } } }
local _requestListenerDisconnect: (() -> ())?
local _playerRemovingConn: RBXScriptConnection?

function AnimationService.init()
	_actionStateWhitelist = {}
	_playerData = {}
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
	if _requestListenerDisconnect then
		warn("AnimationService: start() called more than once — ignoring")
		return
	end

	_requestListenerDisconnect = AnimationNet.RequestActionState.On(function(player: Player, stateName: string)
		if _actionStateWhitelist[stateName] ~= true then
			return
		end

		if _playerData[player] == nil then
			_playerData[player] = { lastRequestTime = 0, conditions = {} }
		end

		local now = os.clock()
		if now - _playerData[player].lastRequestTime < RATE_LIMIT_INTERVAL then
			return
		end

		for _, isActive in pairs(_playerData[player].conditions) do
			if isActive then
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

		AnimationNet.ActionStateApproved.Fire(player, stateName)
		AnimationNet.ActionStateReplicated.FireExcept(player, {
			Player = player,
			StateName = stateName,
		})
	end)

	_playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
		_playerData[player] = nil
	end)
end

function AnimationService.RegisterActionState(name: string)
	_actionStateWhitelist[name] = true
end

-- Any condition with value = true silently rejects incoming action state requests.
function AnimationService.SetPlayerCondition(player: Player, condition: string, value: boolean)
	-- player.Parent is nil once the Player has been removed; re-creating _playerData
	-- here would leak since PlayerRemoving already fired and cleared it.
	if player.Parent == nil then
		return
	end
	if _playerData[player] == nil then
		_playerData[player] = { lastRequestTime = 0, conditions = {} }
	end
	_playerData[player].conditions[condition] = value
end

return AnimationService
