--!strict
--[[
	Maintenance
	Puts this server into maintenance: current players are kicked with a friendly
	message and new joins are refused (ARCHITECTURE.md §5.1, §9).

	Entered permanently when a critical (layer 0-1) service fails to boot — the
	server must never run without working saves or validation. Also toggled by
	the `Flags.Maintenance` config flag (non-permanent; can be lifted live).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Log = require(Shared.Util.Log)

local KICK_MESSAGE = "Riftbound Chronicles is down for maintenance. Please try again in a few minutes."

local log = Log.new("Maintenance")

local Maintenance = {}

local active = false
local permanent = false
local joinConnection: RBXScriptConnection? = nil

local function kick(player: Player)
	player:Kick(KICK_MESSAGE)
end

--[[
	Enters maintenance. `isPermanent` = true for boot failures (cannot be lifted).
]]
function Maintenance.enter(reason: string, isPermanent: boolean?)
	permanent = permanent or (isPermanent == true)
	if active then
		return
	end
	active = true
	ReplicatedStorage:SetAttribute(Constants.Attributes.Maintenance, true)
	log:Error("server entering maintenance: %s", reason)
	joinConnection = Players.PlayerAdded:Connect(kick)
	for _, player in Players:GetPlayers() do
		kick(player)
	end
end

-- Lifts flag-driven maintenance. Boot-failure maintenance cannot be lifted.
function Maintenance.exit()
	if not active or permanent then
		return
	end
	active = false
	ReplicatedStorage:SetAttribute(Constants.Attributes.Maintenance, false)
	if joinConnection then
		joinConnection:Disconnect()
		joinConnection = nil
	end
	log:Info("maintenance lifted")
end

function Maintenance.isActive(): boolean
	return active
end

return Maintenance
