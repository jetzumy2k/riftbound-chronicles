--[[
	Remote matrix (Phase 21, PLAN.md D-97): every client -> server remote
	with what NetService checks before its handler runs.

	    lune run tools/security/remote_matrix > docs/security/REMOTES.md
]]

local load = require("../../tests/pure/loader")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)

local function describe(spec: any): string
	if spec.kind == "enum" then
		return `enum({#spec.values})`
	elseif spec.kind == "number" then
		return `{if spec.integer then "int" else "number"}({spec.min or "-"}..{spec.max or "-"})`
	elseif spec.kind == "string" then
		return `string(<={spec.maxLen})`
	elseif spec.kind == "struct" then
		local names = {}
		for name in spec.fields do
			table.insert(names, name)
		end
		table.sort(names)
		return `\{{table.concat(names, ", ")}\}`
	elseif spec.kind == "array" then
		return `array<={spec.maxCount} of {describe(spec.of)}`
	elseif spec.kind == "map" then
		return `map<={spec.maxCount}`
	end
	return spec.kind
end

local names = {}
for name, spec in Registry do
	if spec.direction == "ClientToServer" then
		table.insert(names, name)
	end
end
table.sort(names)

local out = {
	"# Client -> server remotes (generated)",
	"",
	"`lune run tools/security/remote_matrix > docs/security/REMOTES.md`. NetService checks, in order, before any handler: global rate budget, this remote's rate limit, argument count and schema (types, ranges, lengths, unknown fields rejected), player states, staff permission (from server Roles). Handler-level checks: docs/security/SECURITY_REVIEW.md.",
	"",
	"| Remote | Kind | Arguments | Rate (burst / per s) | States | Staff permission |",
	"|---|---|---|---|---|---|",
}
for _, name in names do
	local spec = Registry[name]
	local args = {}
	for _, arg in spec.args do
		table.insert(args, describe(arg) .. (if arg.optional then "?" else ""))
	end
	table.insert(
		out,
		`| {name} | {spec.kind} | {if #args > 0 then table.concat(args, "; ") else "none"} | {spec.rate.capacity} / {spec.rate.refillPerSecond} | {table.concat(spec.states or {}, ", ")} | {spec.permission or "-"} |`
	)
end
print(table.concat(out, "\n"))
