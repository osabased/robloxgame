--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SSA = require(ReplicatedStorage.Shared.SSA)

type TrackingEntry = {
	_name: string,
	_namespace: string,
	_path: string,
	_module: {},
	init: (() -> ())?,
	start: (() -> ())?,
}

local trackingArray: { TrackingEntry } = {}

local scanTargets = {
	{ folder = ReplicatedStorage.Shared:FindFirstChild("Utils"), path = "ReplicatedStorage.Shared.Utils", namespace = "Utils" },
	{ folder = ServerScriptService.Server:FindFirstChild("Services"), path = "ServerScriptService.Server.Services", namespace = "Services" },
}

-- Phase 1: Require & Register
for _, target in ipairs(scanTargets) do
	local folder = target.folder
	if folder then
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
					init = type(result) == "table" and typeof(result.init) == "function" and result.init or nil,
					start = type(result) == "table" and typeof(result.start) == "function" and result.start or nil,
				}
				table.insert(trackingArray, entry)
			end
		end
	else
		warn(string.format("SSA [Phase 1]: Scan target folder not found — %s", target.path))
	end
end

SSA._lock()

-- Phase 2: Init (sequential — prevents race conditions between dependent inits)
for _, entry in ipairs(trackingArray) do
	if entry.init then
		local initOk, initErr = pcall(entry.init)
		if not initOk then
			warn(string.format("SSA [Phase 2]: Init failed for %s:%s — %s", entry._namespace, entry._name, tostring(initErr)))
			SSA._markFailed(entry._namespace, entry._name, tostring(initErr))
		end
	end
end

-- Phase 3: Start (async)
for _, entry in ipairs(trackingArray) do
	if entry.start then
		task.spawn(function()
			local startOk, startErr = pcall(entry.start)
			if not startOk then
				warn(string.format("SSA [Phase 3]: Start error in %s:%s — %s", entry._namespace, entry._name, tostring(startErr)))
			end
		end)
	end
end
