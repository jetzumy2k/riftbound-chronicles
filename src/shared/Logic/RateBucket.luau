--!strict
--[[
	RateBucket
	Token bucket used for per-player, per-remote rate limiting.

	Time is passed in by the caller (os.clock() in-game) so the logic is
	deterministic and testable. Pure module: no Roblox APIs.
]]

export type Bucket = {
	tokens: number,
	capacity: number,
	refillPerSecond: number,
	updatedAt: number,
}

local RateBucket = {}

function RateBucket.new(capacity: number, refillPerSecond: number, now: number): Bucket
	assert(capacity > 0, "capacity must be positive")
	assert(refillPerSecond >= 0, "refillPerSecond must be non-negative")
	return {
		tokens = capacity,
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		updatedAt = now,
	}
end

local function refill(bucket: Bucket, now: number)
	local elapsed = now - bucket.updatedAt
	if elapsed > 0 then
		bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)
	end
	bucket.updatedAt = now
end

--[[
	Attempts to take `cost` tokens (default 1). Returns true if allowed.
	A rejected call does not consume tokens.
]]
function RateBucket.take(bucket: Bucket, now: number, cost: number?): boolean
	local amount = cost or 1
	refill(bucket, now)
	if bucket.tokens >= amount then
		bucket.tokens -= amount
		return true
	end
	return false
end

--[[
	Returns the current token count after refilling (for diagnostics/tests).
]]
function RateBucket.peek(bucket: Bucket, now: number): number
	refill(bucket, now)
	return bucket.tokens
end

return table.freeze(RateBucket)
