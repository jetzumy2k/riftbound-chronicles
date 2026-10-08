--!strict
--[[
	NetSpec
	Validates the remote registry itself. Run by the server at boot (a bad
	registry stops the boot) and by the Lune test suite.

	Pure module: no Roblox APIs. Takes the Schema module as a parameter.
]]

export type RateSpec = { capacity: number, refillPerSecond: number }

export type RemoteSpec = {
	direction: "ClientToServer" | "ServerToClient",
	kind: "Event" | "Function",
	args: { any },
	rate: RateSpec?,
	states: { string }?,
	permission: string?,
}

local NetSpec = {}

local NAME_PATTERN = "^%u[%w_]*$"
local MAX_ARGS = 8

--[[
	Returns (true, nil) if every entry is well formed, otherwise (false, errors).
]]
function NetSpec.validateRegistry(registry: { [string]: any }, Schema: any): (boolean, { string }?)
	local errors: { string } = {}

	local function report(name: string, message: string)
		table.insert(errors, `{name}: {message}`)
	end

	for name, spec in registry do
		if type(name) ~= "string" or string.match(name, NAME_PATTERN) == nil then
			report(tostring(name), "remote name must be PascalCase")
			continue
		end
		if type(spec) ~= "table" then
			report(name, "spec must be a table")
			continue
		end

		local direction = spec.direction
		if direction ~= "ClientToServer" and direction ~= "ServerToClient" then
			report(name, "invalid direction")
		end
		if spec.kind ~= "Event" and spec.kind ~= "Function" then
			report(name, "invalid kind")
		end
		if spec.kind == "Function" and direction == "ServerToClient" then
			report(name, "server-invoked RemoteFunctions are forbidden")
		end

		if type(spec.args) ~= "table" then
			report(name, "args must be a list")
		else
			if #spec.args > MAX_ARGS then
				report(name, `at most {MAX_ARGS} args`)
			end
			local seenOptional = false
			for i, argSpec in spec.args do
				if not Schema.isSpec(argSpec) then
					report(name, `arg {i} is not a valid spec`)
				elseif argSpec.optional then
					seenOptional = true
				elseif seenOptional then
					report(name, `arg {i}: required arg after optional arg`)
				end
			end
		end

		if direction == "ClientToServer" then
			local rate = spec.rate
			if type(rate) ~= "table" or type(rate.capacity) ~= "number" or rate.capacity <= 0 then
				report(name, "ClientToServer remotes need rate.capacity > 0")
			elseif type(rate.refillPerSecond) ~= "number" or rate.refillPerSecond < 0 then
				report(name, "ClientToServer remotes need rate.refillPerSecond >= 0")
			end
			if type(spec.states) ~= "table" then
				report(name, "ClientToServer remotes must declare states (may be empty)")
			end
		else
			if spec.rate ~= nil or spec.states ~= nil or spec.permission ~= nil then
				report(name, "ServerToClient remotes must not declare rate/states/permission")
			end
		end

		if spec.permission ~= nil and type(spec.permission) ~= "string" then
			report(name, "permission must be a string")
		end
	end

	if #errors > 0 then
		table.sort(errors)
		return false, errors
	end
	return true, nil
end

return table.freeze(NetSpec)
