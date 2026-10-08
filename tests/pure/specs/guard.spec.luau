local load = require("../loader")
local Guard = load("src/shared/Util/Guard")

return function(t)
	local function fakeLogger()
		local logger = { errors = {} :: { string } }
		function logger:Error(fmt, ...)
			table.insert(self.errors, string.format(fmt, ...))
		end
		return logger
	end

	t.it("returns all results on success", function()
		local logger = fakeLogger()
		local ok, a, b = Guard.call(logger, "add", function(x, y)
			return x + y, "done"
		end, 2, 3)
		t.eq(ok, true)
		t.eq(a, 5)
		t.eq(b, "done")
		t.eq(#logger.errors, 0)
	end)

	t.it("returns false and logs with traceback on failure", function()
		local logger = fakeLogger()
		local ok, err = Guard.call(logger, "explode", function()
			error("kaboom")
		end)
		t.eq(ok, false)
		t.ok(string.find(tostring(err), "kaboom", 1, true) ~= nil)
		t.eq(#logger.errors, 1)
		t.ok(string.find(logger.errors[1], "explode failed", 1, true) ~= nil)
	end)

	t.it("preserves nil results in the middle", function()
		local ok, a, b, c = Guard.call(fakeLogger(), "nils", function()
			return 1, nil, 3
		end)
		t.eq(ok, true)
		t.eq(a, 1)
		t.eq(b, nil)
		t.eq(c, 3)
	end)
end
