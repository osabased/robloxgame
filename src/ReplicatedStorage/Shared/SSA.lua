--!strict
local SSA = {}

local _services: { [string]: any } = {}
local _controllers: { [string]: any } = {}
local _utils: { [string]: any } = {}
local _failed: { [string]: { reason: string, module: any? } } = {}
local _paths: { [string]: string } = {}
local _locked = false

function SSA._register(namespace: string, name: string, path: string, moduleTable: any)
	if _locked then
		error("SSA._register failed: Registry is locked. Cannot register " .. path)
	end

	local store: { [string]: any }
	if namespace == "Services" then
		store = _services
	elseif namespace == "Controllers" then
		store = _controllers
	elseif namespace == "Utils" then
		store = _utils
	else
		error("SSA._register failed: Invalid namespace '" .. namespace .. "' for " .. path)
	end

	if store[name] ~= nil then
		local existingPath = _paths[namespace .. ":" .. name] or "Unknown Path"
		error("SSA._register failed: Name collision for '" .. name .. "' in namespace '" .. namespace .. "'. Existing: " .. existingPath .. ", duplicate: " .. path)
	end

	_paths[namespace .. ":" .. name] = path
	store[name] = moduleTable
end

function SSA._markFailed(namespace: string, name: string, reason: string)
	local store: { [string]: any }
	if namespace == "Services" then
		store = _services
	elseif namespace == "Controllers" then
		store = _controllers
	elseif namespace == "Utils" then
		store = _utils
	else
		error("SSA._markFailed failed: Invalid namespace '" .. namespace .. "'")
	end

	local mod = store[name]
	_failed[namespace .. ":" .. name] = { reason = reason, module = mod }
end

function SSA._lock()
	_locked = true

	local function createProxy(originalStore: { [string]: any })
		-- Proxy must be empty so __newindex fires on all write attempts.
		local proxy = {}
		setmetatable(proxy, {
			__index = originalStore,
			__newindex = function()
				error("SSA registry is locked. Cannot modify stores.")
			end,
		})
		return proxy
	end

	_services = createProxy(_services)
	_controllers = createProxy(_controllers)
	_utils = createProxy(_utils)
end

local function getModule(namespace: string, name: string, store: { [string]: any })
	local failedKey = namespace .. ":" .. name
	local failedEntry = _failed[failedKey]

	if failedEntry then
		warn("SSA Get error: " .. failedEntry.reason)
		return failedEntry.module
	end

	local mod = store[name]
	if mod then
		return mod
	else
		warn("SSA Get warning: Module not found - " .. name)
		return nil
	end
end

function SSA.GetService(name: string): unknown
	return getModule("Services", name, _services)
end

function SSA.GetController(name: string): unknown
	return getModule("Controllers", name, _controllers)
end

function SSA.GetUtil(name: string): unknown
	return getModule("Utils", name, _utils)
end

return SSA
