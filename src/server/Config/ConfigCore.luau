--!strict
--[[
	ConfigCore
	Pure helpers for building the effective configuration:
	  effective = validate(deepMerge(defaults, override.values))

	Merge rules:
	  - Dictionaries merge recursively.
	  - Arrays (non-empty sequential tables) and scalars in the override replace
	    the default wholesale.
	  - The result is deep-copied and deep-frozen so services cannot mutate it.

	Pure module: no Roblox APIs. Schema is passed in.
]]

export type Override = {
	version: number,
	values: { [string]: any },
	changedBy: number?,
	changedAt: number?,
}

local ConfigCore = {}

local function isArray(t: { [any]: any }): boolean
	local count = 0
	for _ in t do
		count += 1
	end
	return count > 0 and count == #t
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

function ConfigCore.deepMerge(base: any, override: any): any
	if type(base) ~= "table" or type(override) ~= "table" or isArray(override) or isArray(base) then
		return deepCopy(override)
	end
	local result = deepCopy(base)
	for key, value in override do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = ConfigCore.deepMerge(result[key], value)
		else
			result[key] = deepCopy(value)
		end
	end
	return result
end

function ConfigCore.deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			ConfigCore.deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

--[[
	Builds the effective config. Returns (true, frozenConfig) or (false, reason).
	`override` may be nil (defaults only).
]]
function ConfigCore.resolve(defaults: any, override: Override?, spec: any, Schema: any): (boolean, any)
	local merged
	if override ~= nil then
		if type(override) ~= "table" or type(override.values) ~= "table" then
			return false, "override is malformed"
		end
		if type(override.version) ~= "number" or override.version < 1 or override.version % 1 ~= 0 then
			return false, "override.version must be a positive integer"
		end
		merged = ConfigCore.deepMerge(defaults, override.values)
	else
		merged = deepCopy(defaults)
	end

	local ok, err = Schema.validate(spec, merged, "config")
	if not ok then
		return false, err
	end
	return true, ConfigCore.deepFreeze(merged)
end

--[[
	Reads a dotted path ("Net.GlobalCapacity") from a config table. Returns nil
	if any segment is missing.
]]
function ConfigCore.getPath(config: any, path: string): any
	local node = config
	for segment in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return node
end

return table.freeze(ConfigCore)
