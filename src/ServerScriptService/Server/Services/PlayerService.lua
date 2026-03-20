--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage.Shared.SSA)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerService = {}

function PlayerService.init()
	local TableUtils = SSA.GetUtil("TableUtils") :: Types.ITableUtils
end

function PlayerService.start() end

function PlayerService.GetPlayer(userId: number): Player?
	return game:GetService("Players"):GetPlayerByUserId(userId)
end

return PlayerService
