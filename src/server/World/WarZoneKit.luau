--!strict
--[[
	WarZoneKit — pieces every war zone shares (Phases 12-13, D-41/D-43).

	  camp     a realm's base: paved floor and trim ring, the "Return Home"
	           portal at the back, four dwellings (the zone draws them: tents
	           in the Desert, stilt huts in the Jungle), banners, lamps and a
	           shimmering ring. The ring is a marker only: nothing collides
	           with it and the server keeps the other realm out
	           (PvPService), so nobody is ever trapped in their own camp.
	  bounds   invisible walls just inside the rim cliffs
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.Definitions.WorldLayout)
local Architecture = require(script.Parent.Architecture)

local WarZoneKit = {}

local A = Architecture

-- Draws one dwelling standing on `cf` (its front faces the camp's centre
-- line). `index` 1-4: front pair, then back pair.
export type Dwelling = (parent: Instance, cf: CFrame, index: number, style: Architecture.Style) -> ()

-- Builds `race`'s camp in `zone`; returns its return-portal surface.
function WarZoneKit.camp(model: Model, zone: WorldLayout.WarZone, race: string, dwelling: Dwelling): BasePart?
	local def = zone.bases[race]
	local style = (Architecture.Styles :: any)[race] :: Architecture.Style
	local centre = WorldLayout.basePoint(zone, race, 0, 0)
	local inward = WorldLayout.basePoint(zone, race, 10, 0)
	if def == nil or style == nil or centre == nil or inward == nil then
		return nil
	end
	local camp = Instance.new("Model")
	camp.Name = `{race}Camp`
	local c = Vector3.new(centre[1], centre[2], centre[3])
	local facing = CFrame.lookAt(c, Vector3.new(inward[1], centre[2], inward[3]))
	-- Paved floor with the realm's trim ring.
	A.disc(camp, def.radius - 2, 0.4, facing, style.stone, style.stoneMaterial, { decor = true })
	A.ring(camp, def.radius - 4, 1, 0.5, 40, facing, style.trim, style.trimMaterial, { decor = true })
	-- Return portal at the back, facing the zone.
	local portal =
		A.portalGate(camp, facing * CFrame.new(0, 0, def.radius - 14) * CFrame.Angles(0, math.pi, 0), {
			label = "Return Home",
			opensIn = "",
			active = true,
		}, style)
	-- Dwellings along both sides, banners and lamps at the entrance.
	for i, side in { -1, 1, -1, 1 } do
		local back = if i <= 2 then 6 else 20
		dwelling(
			camp,
			facing * CFrame.new(side * 22, 0, back) * CFrame.Angles(0, side * math.pi / 2, 0),
			i,
			style
		)
	end
	for _, side in { -1, 1 } do
		A.cylinder(camp, 0.35, 16, facing * CFrame.new(side * 14, 0, -16), style.trim, style.trimMaterial)
		A.banner(camp, facing * CFrame.new(side * 14, 15, -16), 5, 10, style)
		A.lamp(camp, facing * CFrame.new(side * 9, 0, -def.radius + 8), style)
	end
	-- Barrier ring: a shimmering marker only (see the header).
	local segments = 32
	local radius = def.radius + 1
	local chord = 2 * radius * math.sin(math.pi / segments) + 0.2
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "RealmBarrier"
		wall.Anchored = true
		wall.Size = Vector3.new(chord, 16, 1)
		wall.CFrame = CFrame.new(c) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 8, -radius)
		wall.Material = Enum.Material.ForceField
		wall.Color = style.glow
		wall.Transparency = 0.55
		wall.CastShadow = false
		wall.CanCollide = false
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Parent = camp
	end
	camp.Parent = model
	return portal
end

-- Invisible walls `rimWidth * 0.45` inside the zone edge (on the rim cliffs).
function WarZoneKit.bounds(model: Model, zone: WorldLayout.WarZone, rimWidth: number)
	local c = zone.center
	local inner = zone.size / 2 - rimWidth * 0.45
	for _, spec in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local wall = A.part(
			model,
			Vector3.new(if spec[1] ~= 0 then 4 else inner * 2, 400, if spec[2] ~= 0 then 4 else inner * 2),
			CFrame.new(c[1] + spec[1] * inner, c[2] + 150, c[3] + spec[2] * inner),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			{ transparency = 1, shadow = false }
		)
		wall.Name = "Boundary"
		wall.CanQuery = false
	end
end

return WarZoneKit
