--!strict
--[[
	SafeZoneService (Layer 4)
	Server-side safe-zone membership (SECURITY_MODEL.md §5A.3).

	  - `IsInSafeZone(player)` / `GetZoneAt(position)` compute membership from
	    the server-observed position at call time. Combat (Phase 6) must call
	    these inside every hostile check and never trust the cached attribute.
	  - A 4 Hz sweep publishes the "SafeZone" player attribute (zone id or nil)
	    for UI only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WorldLayout = require(Shared.Definitions.WorldLayout)
local ZoneGeometry = require(Shared.Logic.ZoneGeometry)
local Signal = require(Shared.Util.Signal)

local SWEEP_INTERVAL = 0.25

local SafeZoneService = {
	-- (player, oldZoneId?, newZoneId?) from the 4 Hz sweep. Handlers must not yield.
	ZoneChanged = Signal.new(),
}

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

--[[
	Returns the safe zone record (WorldLayout.SafeZones entry) containing
	`position`, or nil.
]]
function SafeZoneService:GetZoneAt(position: Vector3): WorldLayout.SafeZone?
	return ZoneGeometry.findZone(WorldLayout.SafeZones, { position.X, position.Y, position.Z })
end

--[[
	Authoritative check from the current server-side position.
	Players without a character are treated as not in a safe zone.
]]
function SafeZoneService:IsInSafeZone(player: Player): boolean
	local position = rootPosition(player)
	return position ~= nil and self:GetZoneAt(position) ~= nil
end

function SafeZoneService:Start()
	task.spawn(function()
		while true do
			task.wait(SWEEP_INTERVAL)
			for _, player in Players:GetPlayers() do
				local position = rootPosition(player)
				local zone = if position then self:GetZoneAt(position) else nil
				local id = if zone then zone.id else nil
				local previous = player:GetAttribute("SafeZone")
				if previous ~= id then
					player:SetAttribute("SafeZone", id)
					SafeZoneService.ZoneChanged:Fire(player, previous, id)
				end
			end
		end
	end)
end

return SafeZoneService
