--!strict
-- ServerScriptService/Server/Services/AnimationService.luau

local Players = game:GetService("Players")

-- Net is the Blink-generated server module. It is required at the root level
-- because it has no SSA dependencies — it is a static generated module.
-- Blink creates and owns BLINK_RELIABLE_REMOTE; AnimationService no longer
-- manages any RemoteEvent instances.
local Net = require(script.Parent.Parent.Net)

local RATE_LIMIT_INTERVAL = 0.3 -- minimum seconds between approved action state requests per player

local AnimationService = {}

-- Initialized to empty here; reset inside init() which is the authoritative setup path.
local _actionStateWhitelist: { [string]: true }
-- Initialized to empty here; reset inside init() which is the authoritative setup path.
local _playerData: { [Player]: { lastRequestTime: number, conditions: { [string]: boolean } } }

function AnimationService.init()
	-- No remote setup needed — Blink owns the RemoteEvent infrastructure.
	_actionStateWhitelist = {}
	_playerData = {}
end

function AnimationService.start()
	-- Blink has already validated that `stateName` is a non-empty string ≤ 64 chars
	-- before this listener fires, so no manual type check is needed here.
	Net.RequestActionState.On(function(player: Player, stateName: string)
		if _actionStateWhitelist[stateName] ~= true then
			-- Silent rejection: the client must not learn which names are valid.
			return
		end

		if _playerData[player] == nil then
			_playerData[player] = { lastRequestTime = 0, conditions = {} }
		end

		if os.clock() - _playerData[player].lastRequestTime < RATE_LIMIT_INTERVAL then
			return
		end

		for _, isActive in pairs(_playerData[player].conditions) do
			if isActive then
				-- Any active disabling condition (e.g. "stunned", "dead") blocks the transition.
				-- Conditions are set externally via SetPlayerCondition().
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

		_playerData[player].lastRequestTime = os.clock()

		-- Confirm approval to the originating client.
		local approveOk, approveErr = pcall(function()
			Net.ActionStateApproved.Fire(player, stateName)
		end)
		if not approveOk then
			warn("AnimationService: ActionStateApproved.Fire error: " .. tostring(approveErr))
		end

		-- Broadcast to all other clients.
		-- FireExcept is a first-class Blink API; no manual loop needed.
		local replicateOk, replicateErr = pcall(function()
			Net.ActionStateReplicated.FireExcept(player, { Player = player, StateName = stateName })
		end)
		if not replicateOk then
			warn("AnimationService: ActionStateReplicated.FireExcept error: " .. tostring(replicateErr))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		_playerData[player] = nil
	end)
end

function AnimationService.RegisterActionState(name: string)
	_actionStateWhitelist[name] = true
end

function AnimationService.SetPlayerCondition(player: Player, condition: string, value: boolean)
	if _playerData[player] == nil then
		_playerData[player] = { lastRequestTime = 0, conditions = {} }
	end
	_playerData[player].conditions[condition] = value
end

return AnimationService
