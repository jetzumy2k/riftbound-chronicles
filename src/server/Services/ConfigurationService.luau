--!strict
--[[
	ConfigurationService (Layer 0)
	Owns the effective server configuration (ARCHITECTURE.md §7):
	  - Defaults in code (server/Config/Defaults), validated at boot. Invalid
	    defaults stop the boot.
	  - Optional live override in DataStore `RC_Config_v1` / key `override`:
	    { version, values, changedBy, changedAt }. Validated with the same schema;
	    an invalid override is rejected and the last good config stays active.
	  - Invalidation over MessagingService topic `RC_ConfigChanged` (payload =
	    new version number) plus a slow poll as fallback.

	Writing overrides is an admin action and arrives in Phase 17.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Schema = require(Shared.Logic.Schema)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ConfigFolder = script.Parent.Parent.Config
local Defaults = require(ConfigFolder.Defaults)
local ConfigCore = require(ConfigFolder.ConfigCore)
local buildConfigSchema = require(ConfigFolder.ConfigSchema)

local STORE_NAME = "RC_Config_v1"
local OVERRIDE_KEY = "override"
local TOPIC = "RC_ConfigChanged"

local log = Log.new("ConfigurationService")

local ConfigurationService = {
	-- Fired with (newVersion) after a new override has been applied.
	Changed = Signal.new(),
}

local configSpec: any = nil
local effective: any = nil
local currentVersion = 0
local refreshing = false
local refreshQueued = false

local function applyLogLevel()
	if RunService:IsStudio() then
		Log.setLevel("Debug")
	else
		Log.setLevel(effective.Log.Level)
	end
end

local function publishVersion()
	ReplicatedStorage:SetAttribute(Constants.Attributes.ConfigVersion, currentVersion)
end

local function fetchOverride(): (boolean, any)
	return pcall(function()
		local store = DataStoreService:GetDataStore(STORE_NAME)
		return store:GetAsync(OVERRIDE_KEY)
	end)
end

local function refreshOnce()
	local ok, override = fetchOverride()
	if not ok then
		log:Info("override unavailable (%s); keeping config v%d", tostring(override), currentVersion)
		return
	end
	if override == nil then
		return
	end
	if type(override) ~= "table" or type(override.version) ~= "number" then
		log:Error("override record is malformed; ignored")
		return
	end
	if override.version <= currentVersion then
		return
	end

	local resolved, result = ConfigCore.resolve(Defaults, override, configSpec, Schema)
	if not resolved then
		log:Error("override v%d rejected: %s", override.version, tostring(result))
		return
	end

	effective = result
	currentVersion = override.version
	applyLogLevel()
	publishVersion()
	log:Info("applied config override v%d", currentVersion)
	ConfigurationService.Changed:Fire(currentVersion)
end

-- Serialises refreshes: concurrent triggers collapse into one follow-up run.
local function refresh()
	if refreshing then
		refreshQueued = true
		return
	end
	refreshing = true
	repeat
		refreshQueued = false
		local ok, err = pcall(refreshOnce :: any)
		if not ok then
			log:Error("refresh failed: %s", tostring(err))
		end
	until not refreshQueued
	refreshing = false
end

function ConfigurationService:Init()
	configSpec = buildConfigSchema(Schema)
	local ok, result = ConfigCore.resolve(Defaults, nil, configSpec, Schema)
	if not ok then
		error(`invalid config defaults: {result}`)
	end
	effective = result
	currentVersion = 0
	applyLogLevel()
	publishVersion()
end

function ConfigurationService:Start()
	if not self:GetFlag("ConfigOverrides") then
		log:Info("live overrides disabled by flag")
		return
	end

	task.spawn(refresh)

	local subscribed, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local version = message.Data
			if type(version) == "number" and version > currentVersion then
				task.spawn(refresh)
			end
		end)
	end)
	if not subscribed then
		log:Info("config invalidation unavailable (%s); polling only", tostring(err))
	end

	task.spawn(function()
		while true do
			task.wait(effective.Config.PollSeconds)
			refresh()
		end
	end)
end

--[[
	Returns the config value at a dotted path, e.g. "Net.GlobalCapacity".
	Unknown paths are programmer errors and raise.
	Returned tables are frozen.
]]
function ConfigurationService:Get(path: string): any
	local value = ConfigCore.getPath(effective, path)
	if value == nil then
		error(`unknown config path '{path}'`, 2)
	end
	return value
end

function ConfigurationService:GetFlag(name: string): boolean
	local value = self:Get(`Flags.{name}`)
	assert(type(value) == "boolean", `flag '{name}' is not a boolean`)
	return value
end

function ConfigurationService:GetVersion(): number
	return currentVersion
end

return ConfigurationService
