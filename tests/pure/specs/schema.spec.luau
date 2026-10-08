local load = require("../loader")
local S = load("src/shared/Logic/Schema")

return function(t)
	t.describe("numbers", function()
		local spec = S.int(0, 10)

		t.it("accepts in-range integers", function()
			t.ok(S.validate(spec, 0))
			t.ok(S.validate(spec, 10))
		end)

		t.it("rejects NaN and infinities", function()
			local nan = 0 / 0
			t.rejects("finite", S.validate(S.number(), nan))
			t.rejects("finite", S.validate(S.number(), math.huge))
			t.rejects("finite", S.validate(S.number(), -math.huge))
		end)

		t.it("rejects non-integers, out-of-range and wrong types", function()
			t.rejects("integer", S.validate(spec, 1.5))
			t.rejects("minimum", S.validate(spec, -1))
			t.rejects("maximum", S.validate(spec, 11))
			t.rejects("expected number", S.validate(spec, "5"))
			t.rejects("required", S.validate(spec, nil))
		end)
	end)

	t.describe("strings", function()
		t.it("enforces length in characters", function()
			t.ok(S.validate(S.string(3), "abc"))
			t.rejects("too long", S.validate(S.string(3), "abcd"))
			t.rejects("too short", S.validate(S.string(3, 2), "a"))
		end)

		t.it("rejects invalid UTF-8", function()
			t.rejects("UTF-8", S.validate(S.string(10), "\255\254"))
		end)

		t.it("rejects huge strings without scanning them fully", function()
			t.rejects("too long", S.validate(S.string(16), string.rep("x", 100000)))
		end)

		t.it("enforces pattern", function()
			local spec = S.string(20, 1, "^[%w_]+$")
			t.ok(S.validate(spec, "ok_key1"))
			t.rejects("format", S.validate(spec, "bad key"))
		end)
	end)

	t.describe("enum and boolean", function()
		t.it("enum accepts members only", function()
			local spec = S.enum({ "A", "B" })
			t.ok(S.validate(spec, "A"))
			t.rejects("enum", S.validate(spec, "C"))
			t.rejects("enum", S.validate(spec, 1))
		end)

		t.it("boolean is strict", function()
			t.ok(S.validate(S.boolean(), false))
			t.rejects("boolean", S.validate(S.boolean(), 0))
		end)
	end)

	t.describe("arrays", function()
		local spec = S.array(S.int(), 3)

		t.it("accepts proper arrays", function()
			t.ok(S.validate(spec, {}))
			t.ok(S.validate(spec, { 1, 2, 3 }))
		end)

		t.it("rejects oversize, holes, string keys and bad elements", function()
			t.rejects("too many", S.validate(spec, { 1, 2, 3, 4 }))
			t.rejects("holes", S.validate(spec, { [1] = 1, [3] = 3 }))
			t.rejects("non-index", S.validate(spec, { 1, x = 2 }))
			t.rejects("[2]", S.validate(spec, { 1, 2.5 }))
		end)

		t.it("rejects tables with metatables", function()
			t.rejects("metatable", S.validate(spec, setmetatable({}, {})))
		end)
	end)

	t.describe("structs", function()
		local spec = S.struct({
			name = S.string(10),
			count = S.optional(S.int(0, 5)),
		})

		t.it("accepts valid shapes with optional fields", function()
			t.ok(S.validate(spec, { name = "x" }))
			t.ok(S.validate(spec, { name = "x", count = 2 }))
		end)

		t.it("rejects unknown keys, missing fields, bad fields", function()
			t.rejects("unexpected key", S.validate(spec, { name = "x", extra = true }))
			t.rejects(".name", S.validate(spec, { count = 1 }))
			t.rejects(".count", S.validate(spec, { name = "x", count = 9 }))
			t.rejects("unexpected key", S.validate(spec, { [1] = "x" }))
		end)
	end)

	t.describe("maps", function()
		local spec = S.map(S.string(8), S.int(), 2)

		t.it("validates keys, values and count", function()
			t.ok(S.validate(spec, { a = 1, b = 2 }))
			t.rejects("too many", S.validate(spec, { a = 1, b = 2, c = 3 }))
			t.rejects("<key>", S.validate(spec, { [1] = 1 }))
			t.rejects(".a", S.validate(spec, { a = "1" }))
		end)
	end)

	t.describe("validateArgs", function()
		local specs = { S.string(5), S.optional(S.int()) }

		t.it("accepts exact and trailing-optional argument lists", function()
			t.ok(S.validateArgs(specs, 2, { "a", 1 }))
			t.ok(S.validateArgs(specs, 1, { "a" }))
			t.ok(S.validateArgs(specs, 2, { "a", nil }))
		end)

		t.it("rejects extra arguments with BadArity", function()
			local ok, _, code = S.validateArgs(specs, 3, { "a", 1, "extra" })
			t.eq(ok, false)
			t.eq(code, "BadArity")
		end)

		t.it("rejects zero-arg remotes receiving arguments", function()
			local ok, _, code = S.validateArgs({}, 1, { true })
			t.eq(ok, false)
			t.eq(code, "BadArity")
		end)

		t.it("rejects bad or missing arguments with BadArgs", function()
			local ok, reason, code = S.validateArgs(specs, 1, { 5 })
			t.eq(ok, false)
			t.eq(code, "BadArgs")
			t.ok(string.find(reason, "arg1", 1, true) ~= nil)
			local ok2, _, code2 = S.validateArgs(specs, 0, {})
			t.eq(ok2, false)
			t.eq(code2, "BadArgs")
		end)
	end)

	t.describe("isSpec and immutability", function()
		t.it("recognises valid specs", function()
			t.ok(S.isSpec(S.int()))
			t.ok(S.isSpec(S.struct({ a = S.array(S.string(3), 2) })))
			t.ok(not S.isSpec({ kind = "string" }))
			t.ok(not S.isSpec({ kind = "weird" }))
			t.ok(not S.isSpec(nil))
		end)

		t.it("specs are frozen and optional() copies", function()
			local base = S.int()
			local opt = S.optional(base)
			t.ok(table.isfrozen(base))
			t.ok(opt.optional == true)
			t.ok(base.optional ~= true)
		end)
	end)
end
