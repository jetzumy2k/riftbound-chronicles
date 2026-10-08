--!strict
--[[
	Schema
	Declarative validation for untrusted values: remote arguments and config.

	Design rules (docs/SECURITY_MODEL.md §4):
	- Recursion follows the *spec*, never the value, so a hostile payload cannot
	  force unbounded work or depth.
	- Collections are size-checked with early exit before element validation.
	- Numbers must be finite; NaN and +/-inf are rejected.
	- Strings must be valid UTF-8 and within length bounds.
	- Structs reject unknown keys; arrays reject holes and non-integer keys.
	- Tables with metatables are rejected.

	Pure module: no Roblox APIs (Vector3/Instance checks use `typeof` and only run
	when such a spec is used in-game).
]]

export type Spec = {
	kind: string,
	optional: boolean?,
	-- number
	min: number?,
	max: number?,
	integer: boolean?,
	-- string
	minLen: number?,
	maxLen: number?,
	pattern: string?,
	-- enum
	values: { string }?,
	-- array / map
	of: Spec?,
	keys: Spec?,
	maxCount: number?,
	-- struct
	fields: { [string]: Spec }?,
	-- vector3
	unit: boolean?,
	-- instance
	className: string?,
}

local Schema = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function fail(path: string, message: string): (boolean, string?)
	return false, `{path}: {message}`
end

local function freezeSpec(spec: Spec): Spec
	return table.freeze(spec) :: any
end

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------

function Schema.number(min: number?, max: number?): Spec
	return freezeSpec({ kind = "number", min = min, max = max })
end

function Schema.int(min: number?, max: number?): Spec
	return freezeSpec({ kind = "number", min = min, max = max, integer = true })
end

function Schema.string(maxLen: number, minLen: number?, pattern: string?): Spec
	return freezeSpec({ kind = "string", maxLen = maxLen, minLen = minLen, pattern = pattern })
end

function Schema.boolean(): Spec
	return freezeSpec({ kind = "boolean" })
end

function Schema.enum(values: { string }): Spec
	assert(#values > 0, "Schema.enum requires at least one value")
	return freezeSpec({ kind = "enum", values = values })
end

function Schema.array(of: Spec, maxCount: number): Spec
	return freezeSpec({ kind = "array", of = of, maxCount = maxCount })
end

function Schema.map(keys: Spec, of: Spec, maxCount: number): Spec
	return freezeSpec({ kind = "map", keys = keys, of = of, maxCount = maxCount })
end

function Schema.struct(fields: { [string]: Spec }): Spec
	return freezeSpec({ kind = "struct", fields = table.freeze(fields) })
end

function Schema.vector3(unit: boolean?): Spec
	return freezeSpec({ kind = "vector3", unit = unit })
end

function Schema.instance(className: string): Spec
	return freezeSpec({ kind = "instance", className = className })
end

-- Returns a copy of `spec` that also accepts nil.
function Schema.optional(spec: Spec): Spec
	local copy = table.clone(spec) :: any
	copy.optional = true
	return freezeSpec(copy)
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local validate: (spec: Spec, value: any, path: string) -> (boolean, string?)

local function validateNumber(spec: Spec, value: any, path: string): (boolean, string?)
	if type(value) ~= "number" then
		return fail(path, `expected number, got {typeof(value)}`)
	end
	if not isFinite(value) then
		return fail(path, "number must be finite")
	end
	if spec.integer and value % 1 ~= 0 then
		return fail(path, "expected integer")
	end
	if spec.min ~= nil and value < spec.min then
		return fail(path, `below minimum {spec.min}`)
	end
	if spec.max ~= nil and value > spec.max then
		return fail(path, `above maximum {spec.max}`)
	end
	return true, nil
end

local function validateString(spec: Spec, value: any, path: string): (boolean, string?)
	if type(value) ~= "string" then
		return fail(path, `expected string, got {typeof(value)}`)
	end
	local maxLen = spec.maxLen :: number
	-- Byte length check first: cheap, and bounds the UTF-8 scan below.
	if #value > maxLen * 4 then
		return fail(path, "string too long")
	end
	local length = utf8.len(value)
	if length == nil then
		return fail(path, "invalid UTF-8")
	end
	if length > maxLen then
		return fail(path, "string too long")
	end
	if spec.minLen ~= nil and length < spec.minLen then
		return fail(path, "string too short")
	end
	if spec.pattern ~= nil and string.match(value, spec.pattern) == nil then
		return fail(path, "string has invalid format")
	end
	return true, nil
end

local function plainTable(value: any, path: string): (boolean, string?)
	if type(value) ~= "table" then
		return fail(path, `expected table, got {typeof(value)}`)
	end
	if getmetatable(value) ~= nil then
		return fail(path, "table must not have a metatable")
	end
	return true, nil
end

local function validateArray(spec: Spec, value: any, path: string): (boolean, string?)
	local ok, err = plainTable(value, path)
	if not ok then
		return ok, err
	end
	local maxCount = spec.maxCount :: number
	local count = 0
	for key in value do
		count += 1
		if count > maxCount then
			return fail(path, "too many elements")
		end
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return fail(path, "array has non-index key")
		end
	end
	if count ~= #value then
		return fail(path, "array has holes")
	end
	for i = 1, count do
		local elementOk, elementErr = validate(spec.of :: Spec, value[i], `{path}[{i}]`)
		if not elementOk then
			return elementOk, elementErr
		end
	end
	return true, nil
end

local function validateMap(spec: Spec, value: any, path: string): (boolean, string?)
	local ok, err = plainTable(value, path)
	if not ok then
		return ok, err
	end
	local maxCount = spec.maxCount :: number
	local count = 0
	for _ in value do
		count += 1
		if count > maxCount then
			return fail(path, "too many entries")
		end
	end
	for key, entry in value do
		local keyOk, keyErr = validate(spec.keys :: Spec, key, `{path}<key>`)
		if not keyOk then
			return keyOk, keyErr
		end
		local entryOk, entryErr = validate(spec.of :: Spec, entry, `{path}.{tostring(key)}`)
		if not entryOk then
			return entryOk, entryErr
		end
	end
	return true, nil
end

local function validateStruct(spec: Spec, value: any, path: string): (boolean, string?)
	local ok, err = plainTable(value, path)
	if not ok then
		return ok, err
	end
	local fields = spec.fields :: { [string]: Spec }
	for key in value do
		if type(key) ~= "string" or fields[key] == nil then
			return fail(path, `unexpected key '{tostring(key)}'`)
		end
	end
	for name, fieldSpec in fields do
		local fieldOk, fieldErr = validate(fieldSpec, value[name], `{path}.{name}`)
		if not fieldOk then
			return fieldOk, fieldErr
		end
	end
	return true, nil
end

local function validateVector3(spec: Spec, value: any, path: string): (boolean, string?)
	if typeof(value) ~= "Vector3" then
		return fail(path, `expected Vector3, got {typeof(value)}`)
	end
	if not (isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)) then
		return fail(path, "vector must be finite")
	end
	if spec.unit then
		local magnitude = value.Magnitude
		if magnitude < 0.99 or magnitude > 1.01 then
			return fail(path, "expected unit vector")
		end
	end
	return true, nil
end

local function validateInstance(spec: Spec, value: any, path: string): (boolean, string?)
	if typeof(value) ~= "Instance" then
		return fail(path, `expected Instance, got {typeof(value)}`)
	end
	if not value:IsA(spec.className :: string) then
		return fail(path, `expected {spec.className}`)
	end
	if value.Parent == nil then
		return fail(path, "instance is not in the DataModel")
	end
	return true, nil
end

function validate(spec: Spec, value: any, path: string): (boolean, string?)
	if value == nil then
		if spec.optional then
			return true, nil
		end
		return fail(path, "required value missing")
	end

	local kind = spec.kind
	if kind == "number" then
		return validateNumber(spec, value, path)
	elseif kind == "string" then
		return validateString(spec, value, path)
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then
			return fail(path, `expected boolean, got {typeof(value)}`)
		end
		return true, nil
	elseif kind == "enum" then
		if type(value) ~= "string" or table.find(spec.values :: { string }, value) == nil then
			return fail(path, "value not in enum")
		end
		return true, nil
	elseif kind == "array" then
		return validateArray(spec, value, path)
	elseif kind == "map" then
		return validateMap(spec, value, path)
	elseif kind == "struct" then
		return validateStruct(spec, value, path)
	elseif kind == "vector3" then
		return validateVector3(spec, value, path)
	elseif kind == "instance" then
		return validateInstance(spec, value, path)
	end
	return fail(path, `unknown spec kind '{kind}'`)
end

--[[
	Validates a single value. Returns (true, nil) or (false, reason).
]]
function Schema.validate(spec: Spec, value: any, path: string?): (boolean, string?)
	return validate(spec, value, path or "value")
end

--[[
	Validates a remote argument list.
	`count` is select("#", ...) from the caller so trailing nils are counted and
	extra arguments are rejected. Returns (true, nil) or (false, reason, code)
	where code is "BadArity" or "BadArgs".
]]
function Schema.validateArgs(specs: { Spec }, count: number, args: { any }): (boolean, string?, string?)
	if count > #specs then
		return false, `expected at most {#specs} arguments, got {count}`, "BadArity"
	end
	for i, spec in specs do
		local ok, err = validate(spec, args[i], `arg{i}`)
		if not ok then
			return false, err, "BadArgs"
		end
	end
	return true, nil, nil
end

--[[
	Returns true if `spec` is a well-formed spec (used to validate the remote
	registry and config schema at boot).
]]
function Schema.isSpec(spec: any): boolean
	if type(spec) ~= "table" or type(spec.kind) ~= "string" then
		return false
	end
	local kind = spec.kind
	if kind == "string" then
		return type(spec.maxLen) == "number"
	elseif kind == "enum" then
		return type(spec.values) == "table" and #spec.values > 0
	elseif kind == "array" then
		return type(spec.maxCount) == "number" and Schema.isSpec(spec.of)
	elseif kind == "map" then
		return type(spec.maxCount) == "number" and Schema.isSpec(spec.keys) and Schema.isSpec(spec.of)
	elseif kind == "struct" then
		if type(spec.fields) ~= "table" then
			return false
		end
		for _, fieldSpec in spec.fields do
			if not Schema.isSpec(fieldSpec) then
				return false
			end
		end
		return true
	elseif kind == "instance" then
		return type(spec.className) == "string"
	end
	return kind == "number" or kind == "boolean" or kind == "vector3"
end

return table.freeze(Schema)
