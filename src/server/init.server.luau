--!strict
--[[
	Server bootstrap. The only server Script; everything else is a ModuleScript
	loaded by Loader in manifest order.
]]

local Loader = require(script.Loader)
local Maintenance = require(script.Maintenance)
local Manifest = require(script.Services.Manifest)

local booted = Loader.start(script.Services, Manifest)

if booted then
	local ConfigurationService = require(script.Services.ConfigurationService)

	local function applyMaintenanceFlag()
		if ConfigurationService:GetFlag("Maintenance") then
			Maintenance.enter("Flags.Maintenance enabled")
		else
			Maintenance.exit()
		end
	end

	ConfigurationService.Changed:Connect(applyMaintenanceFlag)
	applyMaintenanceFlag()
end
