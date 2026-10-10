--!strict
--[[
	JobService (Layer 2)
	Server-authoritative job (CLAUDE.md §6, Phase 4).

	  - Exactly one job per character, chosen once via `SelectJob(job)` after a
	    race is chosen. Repeat attempts are rejected and logged; job changes are
	    an admin action (PLAN.md D-21, Phase 17).
	  - Publishes the public "Job" player attribute.
	  - `CanUseSkillCategory` / `CanUseWeapon` are the server rules later phases
	    call (SkillService Phase 5, EquipmentService Phase 7). They read the job
	    from the profile, never from the client.
	  - Fires `JobChosen(player, job)`; TravelService spawns the player once
	    both race and job are set.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Enums = require(Shared.Enums)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local log = Log.new("JobService")

local JobService = {
	-- (player, job). Fired once per character, when the job is first chosen.
	JobChosen = Signal.new(),
}

local function publish(player: Player, job: string?)
	player:SetAttribute("Job", job)
end

local function onSelectJob(player: Player, job: string)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	if data.Job ~= nil then
		AuditLogService:Security(player, "JobAlreadyChosen", `has {data.Job}, asked {job}`)
		return
	end
	if data.Race == nil or not Enums.has(Enums.Job, job) then
		AuditLogService:Security(player, "InvalidJobChoice", `race={tostring(data.Race)} job={tostring(job)}`)
		return
	end

	-- Synchronous commit.
	data.Job = job

	publish(player, job)
	log:Info("user=%d chose %s", player.UserId, job)
	PlayerDataService:PushSnapshot(player)
	JobService.JobChosen:Fire(player, job)
end

function JobService:Init()
	NetService:RegisterStateCheck("HasJob", function(player)
		local data = PlayerDataService:GetData(player)
		return data ~= nil and data.Job ~= nil
	end)
	NetService:Handle("SelectJob", onSelectJob)
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		publish(player, data.Job)
	end)
end

function JobService:GetJob(player: Player): string?
	local data = PlayerDataService:GetData(player)
	return if data then data.Job else nil
end

-- May this player equip a skill of `category`? (server rule, Phase 5)
function JobService:CanUseSkillCategory(player: Player, category: string): boolean
	local data = PlayerDataService:GetData(player)
	return data ~= nil and JobDefinitions.allowsSkillCategory(data.Job, category)
end

-- May this player wield `weaponType`? (server rule, Phase 7)
function JobService:CanUseWeapon(player: Player, weaponType: string): boolean
	local data = PlayerDataService:GetData(player)
	return data ~= nil and JobDefinitions.allowsWeapon(data.Job, data.Race, weaponType)
end

return JobService
