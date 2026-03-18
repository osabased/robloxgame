--!strict
-- ReplicatedStorage/Shared/Utils/TableUtils.luau

-- CRITICAL RULE: Never call SSA.GetService / SSA.GetController / SSA.GetUtil
-- at the root level of any module. The root level executes during Phase 1 before
-- the registry is populated. All SSA getter calls must be deferred to inside
-- init, start, or other functions. This module has no SSA dependencies, but
-- this rule applies to every module in the architecture.

local TableUtils = {}

function TableUtils.DeepCopy<T>(t: T & any): T
	if type(t) ~= "table" then
		return t
	end
	
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and TableUtils.DeepCopy(v) or v
	end
	
	return (copy :: any) :: T
end

function TableUtils.Keys(t: {[any]: any}): {any}
	local keys = {}
	for k, _ in pairs(t) do
		table.insert(keys, k)
	end
	return keys
end

return TableUtils
