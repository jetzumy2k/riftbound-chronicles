--!strict
--[[
	Migrations — upgrade stored profiles to the current schema version
	(docs/DATA_MODEL.md §5).

	Each step `STEPS[n]` migrates a profile from version n to n + 1. Steps must be
	pure and idempotent. Migration runs on a deep copy; the caller only adopts the
	result on success, so a failing step never corrupts saved data.

	Schema v1 is the initial version, so there are no steps yet.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local ProfileTemplate = require(script.Parent.ProfileTemplate)

export type Status = "ok" | "newer" | "error"
type Step = (data: { [string]: any }) -> { [string]: any }

local Migrations = {}

Migrations.CURRENT_VERSION = ProfileTemplate.SCHEMA_VERSION

-- [fromVersion] = function(data) -> data (now at fromVersion + 1)
Migrations.STEPS = table.freeze({} :: { [number]: Step })

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

--[[
	Migrates `data` to `currentVersion` using `steps` (defaults: this module's).
	Returns (status, resultOrMessage):
	  "ok", migratedCopy        (a new table; the input is untouched)
	  "newer", storedVersion    (profile saved by a newer build; must not be loaded)
	  "error", message          (missing or failing step)
	A missing or invalid SchemaVersion is treated as version 1.
]]
function Migrations.migrate(
	data: { [string]: any },
	currentVersion: number?,
	steps: { [number]: Step }?
): (Status, any)
	local target = currentVersion or Migrations.CURRENT_VERSION
	local stepTable = steps or Migrations.STEPS

	local version = data.SchemaVersion
	if type(version) ~= "number" or version ~= version or version % 1 ~= 0 or version < 1 then
		version = 1
	end
	if version > target then
		return "newer", version
	end

	local working = deepCopy(data)
	while version < target do
		local step = stepTable[version]
		if step == nil then
			return "error", `missing migration step v{version} -> v{version + 1}`
		end
		local ok, result = pcall(step, working)
		if not ok then
			return "error", `migration v{version} -> v{version + 1} failed: {tostring(result)}`
		end
		if type(result) ~= "table" then
			return "error", `migration v{version} -> v{version + 1} returned no table`
		end
		working = result
		version += 1
		working.SchemaVersion = version
	end
	working.SchemaVersion = target
	return "ok", working
end

return table.freeze(Migrations)
