--!strict
-- ServerScriptService/Server/Services/PlayerService.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage.Shared.SSA)
local Types = require(ReplicatedStorage.Shared.Types)

-- CRITICAL RULE: Modules must NEVER call SSA.GetService / GetController / GetUtil at the root level of the module 
-- (i.e. outside of a function body). The module's root level executes during Phase 1 before the registry is locked or populated.
-- All SSA getter calls must be deferred to inside `init`, `start`, or other functions.

local PlayerService = {}

-- Because the bootstrapper calls init and start as normal functions, not methods, you must use self-reference via closure (e.g. referencing PlayerService instead of `self`).

function PlayerService.init()
	-- Initialization logic goes here
	-- We fetch TableUtils and cast from unknown -> Types.ITableUtils to regain type safety.
	local TableUtils = SSA.GetUtil("TableUtils") :: Types.ITableUtils
	
	-- Demonstration of using the retrieved utility:
	local keys = TableUtils.Keys({ a = 1, b = 2 })
end

function PlayerService.start()
	-- Startup logic goes here
	-- Demonstration of self-reference via closure:
	-- We call PlayerService.GetPlayer directly rather than using `self`.
	-- This is necessary because the bootstrapper invokes these functions directly.
	local _ = PlayerService.GetPlayer(0)
end

function PlayerService.GetPlayer(userId: number): Player?
	return game:GetService("Players"):GetPlayerByUserId(userId)
end

return PlayerService
