--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

export type ValidationResult = {
	errors:   { string },
	warnings: { string },
}

local PLACEHOLDER_IDS: { [string]: true } = {
	["rbxassetid://0"] = true,
	[""]               = true,
}

local StateValidator = {}

function StateValidator.Validate(states: { [string]: Types.IStateDefinition }): ValidationResult
	local errors:   { string } = {}
	local warnings: { string } = {}

	for name, def in pairs(states) do
		if typeof(def.animationId) ~= "string" or #def.animationId == 0 then
			table.insert(errors, `["{name}"] animationId is missing or empty`)
		elseif PLACEHOLDER_IDS[def.animationId] then
			table.insert(errors, `["{name}"] animationId is a placeholder — replace before shipping`)
		end

		if def.isAction and def.guard == nil then
			table.insert(warnings, `["{name}"] action state has no guard — it can fire from any state`)
		end
		if def.isAction and def.priority == Enum.AnimationPriority.Idle then
			table.insert(warnings, `["{name}"] action state uses Idle priority — will be overridden by most tracks`)
		end
	end

	return { errors = errors, warnings = warnings }
end

function StateValidator.IsValid(result: ValidationResult): boolean
	return #result.errors == 0
end

return StateValidator
