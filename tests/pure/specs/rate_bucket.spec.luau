local load = require("../loader")
local RateBucket = load("src/shared/Logic/RateBucket")

return function(t)
	t.it("allows a burst up to capacity, then rejects", function()
		local bucket = RateBucket.new(3, 1, 0)
		t.ok(RateBucket.take(bucket, 0))
		t.ok(RateBucket.take(bucket, 0))
		t.ok(RateBucket.take(bucket, 0))
		t.ok(not RateBucket.take(bucket, 0))
	end)

	t.it("refills over time without exceeding capacity", function()
		local bucket = RateBucket.new(2, 1, 0)
		RateBucket.take(bucket, 0)
		RateBucket.take(bucket, 0)
		t.near(RateBucket.peek(bucket, 0.5), 0.5, 1e-9)
		t.ok(RateBucket.take(bucket, 1.0))
		t.near(RateBucket.peek(bucket, 100), 2, 1e-9)
	end)

	t.it("rejected takes do not consume tokens", function()
		local bucket = RateBucket.new(1, 0, 0)
		t.ok(RateBucket.take(bucket, 0))
		for _ = 1, 10 do
			t.ok(not RateBucket.take(bucket, 0))
		end
		t.near(RateBucket.peek(bucket, 0), 0, 1e-9)
	end)

	t.it("supports weighted costs", function()
		local bucket = RateBucket.new(5, 0, 0)
		t.ok(RateBucket.take(bucket, 0, 3))
		t.ok(not RateBucket.take(bucket, 0, 3))
		t.ok(RateBucket.take(bucket, 0, 2))
	end)

	t.it("a flood of 100 calls/s against 6 / 4 per s is limited", function()
		local bucket = RateBucket.new(6, 4, 0)
		local allowed = 0
		for i = 0, 99 do
			if RateBucket.take(bucket, i / 100) then
				allowed += 1
			end
		end
		-- 6 burst + ~4 refilled over one second.
		t.ok(allowed >= 9 and allowed <= 10, `allowed {allowed}`)
	end)

	t.it("rejects invalid parameters", function()
		t.throws(function()
			RateBucket.new(0, 1, 0)
		end)
		t.throws(function()
			RateBucket.new(1, -1, 0)
		end)
	end)
end
