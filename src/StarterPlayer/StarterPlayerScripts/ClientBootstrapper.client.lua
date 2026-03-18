--!strict
-- StarterPlayerScripts/ClientBootstrapper

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SSA = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SSA"))

type TrackingEntry = {
	_name: string,
	_namespace: string,
	_path: string,
	_module: any,
	init: (() -> ())?,
	start: (() -> ())?
}

-- Note: A module that appears in Utils will be registered under the "Utils" namespace by both VMs independently. 
-- Because SSA.luau is required separately by each VM, there is no cross-VM collision — each VM has its own isolated registry.

local trackingArray: {TrackingEntry} = {}

local scanTargets = {
	{ folder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"), namespace = "Utils" },
	{ folder = script.Parent:WaitForChild("Client"):WaitForChild("Controllers"), namespace = "Controllers" }
}

-- Phase 1: Require & Register (Synchronous)
for _, target in ipairs(scanTargets) do
	local folder = target.folder
	for _, instance in ipairs(folder:GetDescendants()) do
		if instance:IsA("ModuleScript") then
			local ok, result = pcall(require, instance)
			if not ok then
				warn(string.format("SSA [Phase 1]: Failed to require %s — %s", instance:GetFullName(), tostring(result)))
				continue
			end
			
			local regOk, regErr = pcall(function()
				SSA._register(target.namespace, instance.Name, instance:GetFullName(), result)
			end)
			
			if not regOk then
				warn(string.format("SSA [Phase 1]: Failed to register %s — %s", instance:GetFullName(), tostring(regErr)))
				continue
			end
			
			local entry: TrackingEntry = {
				_name = instance.Name,
				_namespace = target.namespace,
				_path = instance:GetFullName(),
				_module = result,
				init = type(result) == "table" and result.init or nil,
				start = type(result) == "table" and result.start or nil
			}
			table.insert(trackingArray, entry)
		end
	end
end

SSA._lock()

-- Phase 2: Init (Sequential, Synchronous)
-- Sequential init prevents race conditions when one module's init depends on state set by a prior module's init.
-- init and start are always called as plain functions, not as methods (entry.init() not entry._module:init()).
for _, entry in ipairs(trackingArray) do
	local initFn = entry.init
	if initFn then
		local initOk, initErr = pcall(initFn)
		if not initOk then
			warn(string.format("SSA [Phase 2]: Init failed for %s:%s — %s", entry._namespace, entry._name, tostring(initErr)))
			SSA._markFailed(entry._namespace, entry._name, tostring(initErr))
		end
	end
end

-- Phase 3: Start (Asynchronous)
for _, entry in ipairs(trackingArray) do
	local startFn = entry.start
	if startFn then
		task.spawn(function()
			local startOk, startErr = pcall(startFn)
			if not startOk then
				warn(string.format("SSA [Phase 3]: Start error in %s:%s — %s", entry._namespace, entry._name, tostring(startErr)))
				-- Start failures are runtime errors that do not invalidate the module's initialized state. Do NOT call _markFailed.
			end
		end)
	end
end
