--[[
	Minimal test harness for pure Luau modules under Lune.

	    return function(t)
	        t.describe("Thing", function()
	            t.it("does x", function()
	                t.eq(1 + 1, 2)
	            end)
	        end)
	    end
]]

local harness = {}

local state = {
	passed = 0,
	failed = 0,
	failures = {} :: { string },
	suite = "",
}

local function render(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local t = {}

function t.describe(name: string, fn: () -> ())
	local previous = state.suite
	state.suite = if previous == "" then name else `{previous} > {name}`
	fn()
	state.suite = previous
end

function t.it(name: string, fn: () -> ())
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		state.passed += 1
	else
		state.failed += 1
		table.insert(state.failures, `{state.suite} > {name}\n    {tostring(err)}`)
	end
end

function t.ok(condition: any, message: string?)
	if not condition then
		error(message or "expected truthy value", 2)
	end
end

function t.eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {render(expected)}, got {render(actual)}`, 2)
	end
end

function t.near(actual: number, expected: number, epsilon: number, message: string?)
	if math.abs(actual - expected) > epsilon then
		error(`{message or "not near"}: expected {expected} ± {epsilon}, got {actual}`, 2)
	end
end

-- Asserts that fn() raises; optionally that the message contains `fragment`.
function t.throws(fn: () -> (), fragment: string?)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error", 2)
	end
	if fragment and not string.find(tostring(err), fragment, 1, true) then
		error(`error '{tostring(err)}' does not contain '{fragment}'`, 2)
	end
end

--[[
	Asserts an (ok, reason, ...) result is a rejection whose reason contains
	`fragment` (pass nil to skip the reason check). The fragment comes first so
	the checked call can be the last argument and keep all of its return values:
	    t.rejects("too long", Schema.validate(spec, value))
]]
function t.rejects(fragment: string?, ok: boolean, reason: any)
	if ok then
		error("expected rejection, got success", 2)
	end
	if fragment and not string.find(tostring(reason), fragment, 1, true) then
		error(`reason '{tostring(reason)}' does not contain '{fragment}'`, 2)
	end
end

harness.t = t
harness.state = state

return harness
