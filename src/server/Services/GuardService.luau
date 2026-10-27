--!strict
--[[
	GuardService (Layer 5) — war-zone camp guardians (creator request
	2026-10-27, PLAN.md D-108).

	Four guardians (one of each class) stand in a line just outside each
	realm's camp in both war zones, facing the open ground. A player of the
	other realm who comes within PvP.GuardRadius studs of the camp's centre
	is warned, then struck by the nearest guardian for PvP.GuardHitPct of
	their max HP every PvP.GuardHitSeconds (CombatService:GuardStrike), so
	waiting outside a camp to pick off players as they leave (stat padding)
	never pays. A guardian's defeat credits nobody: no PvP victory, Marks or
	title count. Guardians are not combatants: nothing can target or harm
	them. PvP.Guards switches the strikes off (admin).

	Display models are built like the capital quest givers (display only,
	anchored); every check runs here from server-observed positions.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldLayout = require(Shared.Definitions.WorldLayout)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local AnimeArchetypes = require(Shared.Definitions.AnimeArchetypes)
local FacePresets = require(Shared.Definitions.FacePresets)
local Enums = require(Shared.Enums)
local GearLook = require(Shared.Logic.GearLook)
local Log = require(Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CombatService = require(script.Parent.CombatService)
local BodyStyle = require(script.Parent.Parent.Appearance.BodyStyle)
local Wardrobe = require(script.Parent.Parent.Appearance.Wardrobe)
local CharacterFactory = require(script.Parent.Parent.Appearance.Anime.CharacterFactory)

local log = Log.new("GuardService")

local SWEEP_SECONDS = 0.25
-- Guardians stand this far out from the camp centre (the ring is 40), this
-- far apart.
local LINE_OUT = 47
local LINE_GAP = 14
-- Intruders this far above / below the camp floor are ignored (fliers
-- over a canyon, say).
local HEIGHT_REACH = 60
local WARN_SECONDS = 6
local IDLE = "rbxassetid://507766666"
local SKIN = { Angel = Color3.fromRGB(241, 199, 168), Devil = Color3.fromRGB(176, 116, 86) }
local BOLT = { Angel = Color3.fromRGB(255, 225, 140), Devil = Color3.fromRGB(255, 110, 60) }

type Guard = { model: Model, root: BasePart, race: string }
type Camp = { zone: WorldLayout.WarZone, race: string, centre: Vector3, guards: { Guard } }

local GuardService = {}

local camps: { Camp } = {}
local nextHitAt: { [Player]: number } = {}
local warnedAt: { [Player]: number } = {}
local folder: Folder

local function config(): any
	return ConfigurationService:Get("PvP")
end

-- Full tier-3 Legendary gear of the class (display only).
local function lookFor(race: string, job: string): GearLook.Look
	local look: GearLook.Look = {}
	for _, slot in { "Shoulders", "Chest", "Hands", "Legs", "Boots" } do
		look[slot] = { tier = 3, rarity = "Legendary", kind = slot, enhancement = 0 }
	end
	local definition = JobDefinitions.get(job)
	local families = definition and definition.weaponsByRace[race]
	local family = if families then families[1] else nil
	look.Weapon = { tier = 3, rarity = "Legendary", family = family, kind = "Weapon", enhancement = 10 }
	if job == "Warrior" then
		look.OffHand = { tier = 3, rarity = "Legendary", kind = "Shield", enhancement = 0 }
	end
	return look
end

local function groundY(x: number, z: number, fromY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(Vector3.new(x, fromY + 40, z), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position.Y else fromY
end

local function nameplate(root: BasePart, job: string)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(160, 36)
	board.StudsOffset = Vector3.new(0, 3.6, 0)
	board.MaxDistance = 120
	board.AlwaysOnTop = false
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = `🛡️ {job} Guardian\nStrikes intruders`
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 236, 190)
	text.TextStrokeTransparency = 0.4
	text.Parent = board
	board.Parent = root
end

local function buildGuard(camp: Camp, job: string, at: CFrame)
	local anime = ConfigurationService:Get("Appearance.AnimeStyle") == true
		and AnimeArchetypes.forCharacter(camp.race, job) ~= nil
	local description = Instance.new("HumanoidDescription")
	for _, part in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
		(description :: any)[`{part}Color`] = SKIN[camp.race]
	end
	if anime then
		CharacterFactory.dress(description)
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		log:Warn("%s %s guardian not built: %s", camp.race, job, tostring(model))
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if not anime then
			BodyStyle.athlete(humanoid)
		end
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			humanoid:BuildRigFromAttachments()
		end)
	end
	model.Name = `{camp.race} {job} Guardian`
	model:PivotTo(at)
	model.Parent = folder
	task.wait(0.2)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil then
		model:Destroy()
		return
	end
	root.Anchored = true
	Wardrobe.dress(
		model,
		camp.race,
		FacePresets.defaultFor(camp.race),
		job,
		lookFor(camp.race, job),
		if anime then {} else nil
	)
	model:SetAttribute("RC_Guardian", camp.race)
	nameplate(root, job)
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local animation = Instance.new("Animation")
		animation.AnimationId = IDLE
		pcall(function()
			local track = animator:LoadAnimation(animation)
			track.Looped = true
			track:Play()
		end)
	end
	table.insert(camp.guards, { model = model, root = root, race = camp.race })
end

local function buildCamp(zone: WorldLayout.WarZone, race: string)
	local centre = WorldLayout.basePoint(zone, race, 0, 0)
	if centre == nil then
		return
	end
	local camp: Camp = {
		zone = zone,
		race = race,
		centre = Vector3.new(centre[1], centre[2], centre[3]),
		guards = {},
	}
	table.insert(camps, camp)
	local jobs = Enums.Job
	for index, job in jobs do
		local side = (index - (#jobs + 1) / 2) * LINE_GAP
		local p = WorldLayout.basePoint(zone, race, LINE_OUT, side) :: { number }
		local out = WorldLayout.basePoint(zone, race, LINE_OUT + 10, side) :: { number }
		local y = groundY(p[1], p[3], p[2]) + 3.2
		local at = CFrame.lookAt(Vector3.new(p[1], y, p[3]), Vector3.new(out[1], y, out[3]))
		task.spawn(buildGuard, camp, job, at)
	end
end

-- A short bright line from the guardian to its target (display only).
local function bolt(from: Vector3, to: Vector3, race: string)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "GuardBolt"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = BOLT[race] or Color3.new(1, 1, 1)
	part.Size = Vector3.new(0.5, 0.5, length)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Parent = folder
	Debris:AddItem(part, 0.18)
end

-- The guardian of `camp` closest to `position`.
local function nearestGuard(camp: Camp, position: Vector3): Guard?
	local best: Guard? = nil
	local bestDistance = math.huge
	for _, guard in camp.guards do
		local distance = (guard.root.Position - position).Magnitude
		if guard.model.Parent and distance < bestDistance then
			best, bestDistance = guard, distance
		end
	end
	return best
end

local function sweep(now: number)
	local c = config()
	if c.Guards ~= true then
		return
	end
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService:GetData(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if data == nil or data.Race == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local position = root.Position
		for _, camp in camps do
			if camp.race == data.Race then
				continue
			end
			local flat = Vector3.new(position.X - camp.centre.X, 0, position.Z - camp.centre.Z)
			if flat.Magnitude > c.GuardRadius or math.abs(position.Y - camp.centre.Y) > HEIGHT_REACH then
				continue
			end
			if now - (warnedAt[player] or -math.huge) >= WARN_SECONDS then
				warnedAt[player] = now
				NetService:FireClient("Notify", player, { kind = "Warning", textKey = "pvp.guardWarning" })
				-- A moment to turn back before the first strike.
				nextHitAt[player] = math.max(nextHitAt[player] or 0, now + 1)
			end
			if now < (nextHitAt[player] or 0) then
				break
			end
			local guard = nearestGuard(camp, position)
			if guard == nil then
				break
			end
			nextHitAt[player] = now + c.GuardHitSeconds
			if CombatService:GuardStrike(guard.model, camp.race, character :: Model, c.GuardHitPct) then
				local from = guard.root.Position
				guard.root.CFrame = CFrame.lookAt(from, Vector3.new(position.X, from.Y, position.Z))
				bolt(from + Vector3.new(0, 1.5, 0), position, camp.race)
			end
			break
		end
	end
end

function GuardService:Start()
	folder = Instance.new("Folder")
	folder.Name = "RC_Guardians"
	folder.Parent = Workspace
	for _, zone in WorldLayout.WarZones :: { [string]: WorldLayout.WarZone } do
		for race in zone.bases do
			buildCamp(zone, race)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		nextHitAt[player] = nil
		warnedAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(SWEEP_SECONDS)
			local ok, err = pcall(sweep :: any, os.clock())
			if not ok then
				log:Error("guard sweep failed: %s", tostring(err))
			end
		end
	end)
end

return GuardService
