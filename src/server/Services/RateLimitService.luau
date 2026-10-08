--!strict
--[[
	RateLimitService (Layer 0) — skeleton
	Token buckets per (player, key). Used by NetService for the global
	per-player budget and per-remote limits; later phases use it for
	gameplay-level limits (e.g. resets, reports).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateBucket = require(ReplicatedStorage.Shared.Logic.RateBucket)

local RateLimitService = {}

local buckets: { [Player]: { [string]: RateBucket.Bucket } } = {}

--[[
	Consumes `cost` (default 1) tokens from the bucket for (player, key),
	creating it with the given parameters on first use. Returns true if allowed.
]]
function RateLimitService:Consume(
	player: Player,
	key: string,
	capacity: number,
	refillPerSecond: number,
	cost: number?
): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if playerBuckets == nil then
		-- Players that already left must not recreate state.
		if player.Parent ~= Players then
			return false
		end
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if bucket == nil then
		bucket = RateBucket.new(capacity, refillPerSecond, now)
		playerBuckets[key] = bucket
	end
	return RateBucket.take(bucket, now, cost)
end

function RateLimitService:ClearPlayer(player: Player)
	buckets[player] = nil
end

function RateLimitService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:ClearPlayer(player)
	end)
end

return RateLimitService
