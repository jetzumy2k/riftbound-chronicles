--!strict
--[[
	Loader
	Boots server services in manifest order (ARCHITECTURE.md §5.1):
	  1. require every service
	  2. Init() each in order — synchronous wiring only, must not yield
	  3. Start() each in its own thread — may spawn loops

	Failure policy:
	  - Layer 0-1 (critical) failure in require/Init: permanent maintenance and
	    the boot stops. The server never runs without saves or validation.
	  - Layer 2+ failure: the service is disabled, the error is logged and the
	    boot continues (its feature flag is forced off by that service's owner).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local Guard = require(Shared.Util.Guard)

local Maintenance = require(script.Parent.Maintenance)

local CRITICAL_MAX_LAYER = 1

local log = Log.new("Loader")

export type ManifestEntry = { name: string, layer: number }

type Loaded = {
	entry: ManifestEntry,
	service: any,
	enabled: boolean,
}

local Loader = {}

local function fail(entry: ManifestEntry, stage: string): boolean
	if entry.layer <= CRITICAL_MAX_LAYER then
		Maintenance.enter(`{entry.name} failed during {stage}`, true)
		return true -- abort boot
	end
	log:Error("%s disabled after %s failure", entry.name, stage)
	return false
end

--[[
	Boots the services. Returns true if every critical service started.
]]
function Loader.start(servicesFolder: Instance, manifest: { ManifestEntry }): boolean
	local startedAt = os.clock()
	local loaded: { Loaded } = {}

	for _, entry in manifest do
		local module = servicesFolder:FindFirstChild(entry.name)
		local ok, service
		if module == nil or not module:IsA("ModuleScript") then
			log:Error("service module '%s' not found", entry.name)
			ok = false
		else
			ok, service = Guard.call(log, `require {entry.name}`, require, module)
		end
		if not ok then
			if fail(entry, "require") then
				return false
			end
		else
			table.insert(loaded, { entry = entry, service = service, enabled = true })
		end
	end

	for _, item in loaded do
		local init = item.service.Init
		if init then
			local ok = Guard.call(log, `{item.entry.name}.Init`, init, item.service)
			if not ok then
				item.enabled = false
				if fail(item.entry, "Init") then
					return false
				end
			end
		end
	end

	for _, item in loaded do
		local start = item.service.Start
		if item.enabled and start then
			task.spawn(Guard.call, log, `{item.entry.name}.Start`, start, item.service)
		end
	end

	log:Info("booted %d services in %.1f ms", #loaded, (os.clock() - startedAt) * 1000)
	return true
end

return Loader
