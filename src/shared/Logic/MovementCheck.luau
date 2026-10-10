--!strict
--[[
	MovementCheck — pure movement-sanity evaluation (SECURITY_MODEL.md §5A.2).

	AntiExploitService samples each character on the server and calls
	`evaluate(previous, current, dt, allowance, config)`. It returns violation
	points and reasons; the service turns points into rubber-banding / strikes
	according to the configured mode (Off / Shadow / Enforce).

	Legitimate server-driven movement (travel, dashes, knockback) must be
	covered by an allowance granted *before* it happens.

	Positions are {x, y, z} tables. Pure module.
]]

export type Sample = {
	position: { number },
	grounded: boolean,
	airTime: number, -- seconds continuously airborne at this sample
}

export type Allowance = {
	-- Extra horizontal speed permitted (studs/s), e.g. a dash.
	extraSpeed: number,
	-- Ignore all checks (teleports, respawns).
	grace: boolean,
}

export type Config = {
	SpeedFactor: number,
	SpeedToleranceStuds: number,
	MaxAirSeconds: number,
	TeleportStuds: number,
}

export type Result = {
	points: number,
	reasons: { string },
	teleport: boolean,
}

local MovementCheck = {}

local function horizontalDistance(a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[3] - a[3]
	return math.sqrt(dx * dx + dz * dz)
end

function MovementCheck.evaluate(
	previous: Sample,
	current: Sample,
	dt: number,
	walkSpeed: number,
	allowance: Allowance?,
	config: Config
): Result
	local result: Result = { points = 0, reasons = {}, teleport = false }
	if allowance and allowance.grace then
		return result
	end
	if dt <= 0 then
		return result
	end

	local moved = horizontalDistance(previous.position, current.position)
	local extra = if allowance then allowance.extraSpeed else 0

	-- One huge jump no lag can explain.
	if moved > config.TeleportStuds then
		result.points += 10
		result.teleport = true
		table.insert(result.reasons, `teleport {math.floor(moved)} studs`)
		return result
	end

	local maxDistance = (walkSpeed * config.SpeedFactor + extra) * dt
		+ config.SpeedToleranceStuds * math.min(dt * 4, 1)
	if moved > maxDistance then
		result.points += 1
		table.insert(result.reasons, `speed {string.format("%.1f", moved / dt)} studs/s`)
	end

	if current.airTime > config.MaxAirSeconds and not current.grounded then
		local rising = current.position[2] - previous.position[2]
		-- Hovering or rising while long airborne = flying. Falling is fine.
		if rising > -0.5 * dt then
			result.points += 1
			table.insert(result.reasons, `airborne {string.format("%.1f", current.airTime)} s`)
		end
	end

	return result
end

-- Leaky bucket: points drain at 1 per second.
function MovementCheck.drain(points: number, dt: number): number
	return math.max(0, points - dt)
end

return table.freeze(MovementCheck)
