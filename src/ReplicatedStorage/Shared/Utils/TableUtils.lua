--!strict
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

function TableUtils.Keys(t: { [any]: any }): { any }
	local keys = {}
	for k, _ in pairs(t) do
		table.insert(keys, k)
	end
	return keys
end

return TableUtils
