--!strict
--[[
	ZoneAtmosphere — lighting and atmosphere per area (PLAN.md D-37).

	The client (AtmosphereController) blends to the preset of the area the
	camera is in. Colours are {r, g, b}. Display only. Pure module.

	  Neutral  the race selection view and anywhere unclaimed
	  Angel    clear afternoon sky, light blue haze, gentle bloom (white
	           marble washes out under strong exposure / bloom)
	  Devil    low ember-red sun, warm haze, readable dark stone
	  Desert   the Desert Rift war zone
	  Jungle   the Jungle Rift war zone
	  Dungeon  inside dungeon instances
]]

export type Preset = {
	clockTime: number,
	brightness: number,
	ambient: { number },
	outdoorAmbient: { number },
	colorShiftTop: { number },
	exposure: number,
	-- Atmosphere
	density: number,
	haze: number,
	glare: number,
	atmosphereColor: { number },
	decay: { number },
	-- ColorCorrection
	tint: { number },
	saturation: number,
	contrast: number,
	-- Bloom
	bloomIntensity: number,
	bloomThreshold: number,
}

local ZoneAtmosphere = {}

ZoneAtmosphere.Presets = table.freeze({
	Neutral = table.freeze({
		clockTime = 14.5,
		brightness = 2.4,
		ambient = { 110, 110, 120 },
		outdoorAmbient = { 140, 140, 150 },
		colorShiftTop = { 255, 240, 220 },
		exposure = 0,
		density = 0.3,
		haze = 1,
		glare = 0.2,
		atmosphereColor = { 199, 210, 230 },
		decay = { 110, 120, 140 },
		tint = { 255, 252, 248 },
		saturation = 0.05,
		contrast = 0.05,
		bloomIntensity = 0.5,
		bloomThreshold = 1.8,
	} :: Preset),
	Angel = table.freeze({
		clockTime = 14,
		brightness = 2.2,
		ambient = { 120, 122, 135 },
		outdoorAmbient = { 140, 145, 160 },
		colorShiftTop = { 255, 236, 205 },
		exposure = -0.25,
		density = 0.22,
		haze = 0.4,
		glare = 0.1,
		atmosphereColor = { 190, 215, 250 },
		decay = { 92, 128, 182 },
		tint = { 255, 248, 236 },
		saturation = 0.14,
		contrast = 0.16,
		bloomIntensity = 0.3,
		bloomThreshold = 2.4,
	} :: Preset),
	Devil = table.freeze({
		clockTime = 16.8,
		brightness = 2.6,
		ambient = { 150, 92, 80 },
		outdoorAmbient = { 168, 104, 86 },
		colorShiftTop = { 255, 150, 100 },
		exposure = 0.35,
		density = 0.32,
		haze = 1.4,
		glare = 0.3,
		atmosphereColor = { 255, 145, 105 },
		decay = { 140, 56, 42 },
		tint = { 255, 232, 220 },
		saturation = 0.12,
		contrast = 0.1,
		bloomIntensity = 0.55,
		bloomThreshold = 1.8,
	} :: Preset),
	-- War zone: bright desert afternoon, warm sand haze, still readable.
	Desert = table.freeze({
		clockTime = 15,
		brightness = 2.5,
		ambient = { 140, 128, 112 },
		outdoorAmbient = { 168, 152, 128 },
		colorShiftTop = { 255, 226, 180 },
		exposure = -0.1,
		density = 0.3,
		haze = 1.2,
		glare = 0.3,
		atmosphereColor = { 232, 204, 160 },
		decay = { 186, 140, 92 },
		tint = { 255, 246, 232 },
		saturation = 0.1,
		contrast = 0.1,
		bloomIntensity = 0.35,
		bloomThreshold = 2.0,
	} :: Preset),
	-- War zone: humid jungle morning, green-gold haze, soft sun shafts.
	Jungle = table.freeze({
		clockTime = 10.5,
		brightness = 2.2,
		ambient = { 112, 128, 108 },
		outdoorAmbient = { 136, 156, 128 },
		colorShiftTop = { 255, 236, 190 },
		exposure = 0,
		density = 0.38,
		haze = 1.6,
		glare = 0.2,
		atmosphereColor = { 196, 220, 180 },
		decay = { 92, 128, 96 },
		tint = { 246, 255, 240 },
		saturation = 0.18,
		contrast = 0.08,
		bloomIntensity = 0.4,
		bloomThreshold = 1.9,
	} :: Preset),
	-- Inside dungeon instances: cool stone, warm candle glow, readable.
	Dungeon = table.freeze({
		clockTime = 15,
		brightness = 1.4,
		ambient = { 128, 122, 138 },
		outdoorAmbient = { 120, 120, 140 },
		colorShiftTop = { 255, 214, 170 },
		exposure = 0.2,
		density = 0.36,
		haze = 0.8,
		glare = 0.1,
		atmosphereColor = { 120, 132, 165 },
		decay = { 60, 64, 92 },
		tint = { 248, 244, 255 },
		saturation = 0.1,
		contrast = 0.12,
		bloomIntensity = 0.45,
		bloomThreshold = 1.7,
	} :: Preset),
})

--[[
	Zone extras (D-84), switched (not blended) when the camera enters a zone:
	  particles  a client-only emitter around the camera ("Sand", "Motes")
	  wind       Workspace.GlobalWind (sways terrain grass, drifts particles)
	  water      Terrain.WaterColor
	  sunRays    SunRaysEffect intensity
]]
export type Extras = {
	particles: string?,
	wind: { number },
	water: { number },
	sunRays: number,
}

ZoneAtmosphere.Extras = table.freeze({
	Neutral = table.freeze({ wind = { 6, 0, 4 }, water = { 40, 110, 140 }, sunRays = 0.04 } :: Extras),
	Desert = table.freeze({
		particles = "Sand",
		wind = { 12, 0, 7 },
		water = { 48, 156, 168 },
		sunRays = 0.05,
	} :: Extras),
	-- Light motes drifting under the canopy, emerald water, strong sun shafts.
	Jungle = table.freeze({
		particles = "Motes",
		wind = { 4, 0, 3 },
		water = { 36, 112, 96 },
		sunRays = 0.16,
	} :: Extras),
	-- Dust motes hanging in the candlelight under the vaults (D-87).
	Dungeon = table.freeze({
		particles = "Motes",
		wind = { 0, 0, 0 },
		water = { 40, 70, 110 },
		sunRays = 0,
	} :: Extras),
})

--[[
	Event weather (Phase 18 stage 2, D-91): while the event runs, the sky of
	its zone (`zone`: an extras name; nil = everywhere but the dungeons)
	blends WEATHER_WEIGHT of the way to `preset`, and the camera particles
	become `particles` at `rate` per second with `wind`.
]]
export type Weather = {
	zone: string?,
	preset: Preset,
	particles: string,
	rate: number,
	wind: { number },
}

ZoneAtmosphere.WEATHER_WEIGHT = 0.85

ZoneAtmosphere.Weather = table.freeze({
	-- A sandstorm: thick ochre haze, dim sun, sand driving across the view.
	Sandstorm = table.freeze({
		zone = "Desert",
		preset = table.freeze({
			clockTime = 15,
			brightness = 1.4,
			ambient = { 150, 124, 92 },
			outdoorAmbient = { 160, 132, 98 },
			colorShiftTop = { 230, 180, 120 },
			exposure = -0.2,
			density = 0.62,
			haze = 3,
			glare = 0,
			atmosphereColor = { 214, 170, 112 },
			decay = { 170, 120, 70 },
			tint = { 255, 232, 196 },
			saturation = -0.05,
			contrast = 0.05,
			bloomIntensity = 0.2,
			bloomThreshold = 2.2,
		} :: Preset),
		particles = "Sand",
		rate = 90,
		wind = { 36, 0, 22 },
	} :: Weather),
	-- The flood: heavy rain, grey-green gloom, low cloud.
	Flood = table.freeze({
		zone = "Jungle",
		preset = table.freeze({
			clockTime = 16,
			brightness = 1.1,
			ambient = { 92, 104, 104 },
			outdoorAmbient = { 104, 118, 120 },
			colorShiftTop = { 180, 196, 200 },
			exposure = -0.3,
			density = 0.5,
			haze = 2.4,
			glare = 0,
			atmosphereColor = { 140, 158, 160 },
			decay = { 90, 108, 112 },
			tint = { 226, 238, 240 },
			saturation = -0.15,
			contrast = 0.08,
			bloomIntensity = 0.2,
			bloomThreshold = 2.2,
		} :: Preset),
		particles = "Rain",
		rate = 120,
		wind = { 10, 0, 6 },
	} :: Weather),
	-- The Rift Eclipse: a violet dusk over every realm.
	Eclipse = table.freeze({
		preset = table.freeze({
			clockTime = 18.6,
			brightness = 0.9,
			ambient = { 86, 66, 110 },
			outdoorAmbient = { 96, 74, 126 },
			colorShiftTop = { 200, 140, 255 },
			exposure = -0.2,
			density = 0.4,
			haze = 1.6,
			glare = 0.4,
			atmosphereColor = { 150, 110, 200 },
			decay = { 90, 50, 140 },
			tint = { 230, 214, 255 },
			saturation = 0.05,
			contrast = 0.18,
			bloomIntensity = 0.6,
			bloomThreshold = 1.6,
		} :: Preset),
		particles = "Motes",
		rate = 16,
		wind = { 4, 0, 3 },
	} :: Weather),
})

-- Events that bring weather.
ZoneAtmosphere.WEATHER_OF_EVENT = table.freeze({
	DesertStorm = "Sandstorm",
	JungleFlood = "Flood",
	RiftEclipse = "Eclipse",
})

--[[
	The weather showing in zone `name` (an extras name) while `running`
	event ids are live, or nil. The first matching event wins.
]]
function ZoneAtmosphere.weatherFor(name: string, running: { string }): (string?, Weather?)
	for _, id in running do
		local weatherName = (ZoneAtmosphere.WEATHER_OF_EVENT :: any)[id]
		local weather = weatherName and (ZoneAtmosphere.Weather :: any)[weatherName] :: Weather?
		if weather and (weather.zone == name or (weather.zone == nil and name ~= "Dungeon")) then
			return weatherName, weather
		end
	end
	return nil, nil
end

function ZoneAtmosphere.extras(name: string): Extras
	return (ZoneAtmosphere.Extras :: any)[name] or ZoneAtmosphere.Extras.Neutral
end

-- Studs from a capital's centre within which its preset applies fully, and
-- the extra distance over which it blends out to Neutral.
ZoneAtmosphere.FULL_RADIUS = 420
ZoneAtmosphere.BLEND_DISTANCE = 200

function ZoneAtmosphere.get(name: string): Preset
	return (ZoneAtmosphere.Presets :: any)[name] or ZoneAtmosphere.Presets.Neutral
end

-- 0..1 weight of a capital's preset at `distance` from its centre.
function ZoneAtmosphere.weight(distance: number): number
	local t = (distance - ZoneAtmosphere.FULL_RADIUS) / ZoneAtmosphere.BLEND_DISTANCE
	return 1 - math.clamp(t, 0, 1)
end

-- Linear blend of two presets (a at 0, b at 1).
function ZoneAtmosphere.blend(a: Preset, b: Preset, alpha: number): Preset
	local out: any = {}
	for key, value in a :: any do
		local other = (b :: any)[key]
		if type(value) == "number" then
			out[key] = value + (other - value) * alpha
		else
			out[key] = {
				value[1] + (other[1] - value[1]) * alpha,
				value[2] + (other[2] - value[2]) * alpha,
				value[3] + (other[3] - value[3]) * alpha,
			}
		end
	end
	return out
end

return table.freeze(ZoneAtmosphere)
