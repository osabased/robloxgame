--!strict
-- ServerScriptService/Server/Services/AnimationService.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RATE_LIMIT_INTERVAL = 0.3 -- minimum seconds between approved action state requests per player

local AnimationService = {}

-- Initialized to empty here; reset inside init() which is the authoritative setup path. Values set here are never read before init() runs.
local _actionStateWhitelist: {[string]: true}
-- Initialized to empty here; reset inside init() which is the authoritative setup path. Values set here are never read before init() runs.
local _playerData: {[Player]: { lastRequestTime: number, conditions: {[string]: boolean} }}

local _reqRemote: RemoteEvent?
local _approvedRemote: RemoteEvent?
local _replicatedRemote: RemoteEvent?

function AnimationService.init()
	local remotes = ReplicatedStorage:FindFirstChild("SSA_Remotes") or Instance.new("Folder")
	if remotes.Parent ~= ReplicatedStorage then
		remotes.Name = "SSA_Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local function getOrCreateRemote(name: string): RemoteEvent
		local event = remotes:FindFirstChild(name)
		if not event or not event:IsA("RemoteEvent") then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = remotes
		end
		return event :: RemoteEvent
	end

	_reqRemote = getOrCreateRemote("SSA_RequestActionState")
	_approvedRemote = getOrCreateRemote("SSA_ActionStateApproved")
	_replicatedRemote = getOrCreateRemote("SSA_ActionStateReplicated")

	_actionStateWhitelist = {}
	_playerData = {}
end

function AnimationService.start()
	if _reqRemote == nil or _approvedRemote == nil or _replicatedRemote == nil then
		warn("AnimationService: start() called before init() completed — RemoteEvents not ready. Aborting.")
		return
	end

	local reqRemote = _reqRemote :: RemoteEvent
	local appRemote = _approvedRemote :: RemoteEvent
	local repRemote = _replicatedRemote :: RemoteEvent

	reqRemote.OnServerEvent:Connect(function(player: Player, stateName: unknown)
		if type(stateName) ~= "string" then
			warn("AnimationService: Non-string state name from player " .. player.Name)
			return
		end
		
		local stateNameStr: string = stateName :: string

		if _actionStateWhitelist[stateNameStr] ~= true then
			-- silent rejection prevents the client from learning which state names are valid.
			return
		end

		if _playerData[player] == nil then
			_playerData[player] = { lastRequestTime = 0, conditions = {} }
		end

		if os.clock() - _playerData[player].lastRequestTime < RATE_LIMIT_INTERVAL then
			return
		end

		for conditionName, isActive in pairs(_playerData[player].conditions) do
			if isActive then
				-- any active disabling condition (e.g. "stunned", "dead") blocks the transition. Conditions are set externally via SetPlayerCondition().
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

		local fireOk, fireErr = pcall(function()
			appRemote:FireClient(player, stateNameStr)
		end)
		if not fireOk then
			warn("AnimationService: FireClient error: " .. tostring(fireErr))
		end

		-- FireAllClientsExcept is not a real Roblox API; the manual loop is the correct approach.
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				local repOk, repErr = pcall(function()
					repRemote:FireClient(otherPlayer, player, stateNameStr)
				end)
				if not repOk then
					warn("AnimationService: FireClient error: " .. tostring(repErr))
				end
			end
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