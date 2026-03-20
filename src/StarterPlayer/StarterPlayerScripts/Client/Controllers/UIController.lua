--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local UIController = {}
local TableUtils: Types.ITableUtils?

function UIController.init()
	TableUtils = SSA.GetUtil("TableUtils") :: Types.ITableUtils?
	assert(TableUtils, "TableUtils must be initialized")
end

function UIController.start() end

function UIController.ShowHUD() end

return UIController
