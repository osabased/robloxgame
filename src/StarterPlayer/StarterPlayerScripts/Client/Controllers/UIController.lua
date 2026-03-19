--!strict
-- StarterPlayerScripts/Client/Controllers/UIController.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- CRITICAL RULE: Modules must NEVER call SSA.GetService / GetController / GetUtil at the root level of the module
-- (i.e. outside of a function body). The module's root level executes during Phase 1 before the registry is locked or populated.
-- All SSA getter calls must be deferred to inside `init`, `start`, or other functions.

local UIController = {}
local TableUtils: Types.ITableUtils?

-- Because the bootstrapper calls init and start as normal functions, not methods, you must use self-reference via closure (e.g. referencing UIController instead of `self`).

function UIController.init()
	TableUtils = SSA.GetUtil("TableUtils") :: Types.ITableUtils?
	assert(TableUtils, "TableUtils must be initialized")
	local keys = TableUtils.Keys({ a = 1, b = 2 })
end

function UIController.start() end

function UIController.ShowHUD() end

return UIController
