--!strict
--[[
	RewardClaims — idempotent reward grants (docs/DATA_MODEL.md §4.2).

	    local status = RewardClaims.claim(data, "Q:FirstSpark", os.time(), function(d)
	        d.Wallet.Gold += 50
	    end)

	The claim is recorded *before* the grant runs, in the same synchronous block.
	If the grant function errors, the claim stays recorded and the error is
	returned for loud logging: a lost reward can be restored by support from the
	logs, while a duplicated reward cannot be taken back cleanly. The grant
	function must not yield.

	Reward id format: "<PREFIX>:<rest>", PREFIX in RETENTION_SECONDS.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

export type ClaimStatus = "granted" | "already" | "invalid" | "error"

local RewardClaims = {}

local DAY = 86400

-- Prefix -> seconds to keep the claim; false = keep forever.
RewardClaims.RETENTION_SECONDS = table.freeze({
	Q = false, -- quest completion
	D = 7 * DAY, -- dungeon clear (runId)
	B = 7 * DAY, -- boss loot (runId:bossId)
	PB = 7 * DAY, -- PvP boss (spawnId)
	E = 14 * DAY, -- event reward (event expiry + buffer)
	A = 30 * DAY, -- admin grant (auditId)
} :: { [string]: number | false })

local MAX_ID_LENGTH = 128
local ID_PATTERN = "^(%u+):[%w_:%-%.]+$"

function RewardClaims.isValidId(rewardId: any): boolean
	if type(rewardId) ~= "string" or #rewardId > MAX_ID_LENGTH then
		return false
	end
	local prefix = string.match(rewardId, ID_PATTERN)
	return prefix ~= nil and RewardClaims.RETENTION_SECONDS[prefix] ~= nil
end

function RewardClaims.isClaimed(data: { [string]: any }, rewardId: string): boolean
	return data.ClaimedRewardIds[rewardId] ~= nil
end

--[[
	Grants a reward at most once per profile. Returns (status, errorMessage?).
]]
function RewardClaims.claim(
	data: { [string]: any },
	rewardId: string,
	now: number,
	grant: (data: { [string]: any }) -> ()
): (ClaimStatus, string?)
	if not RewardClaims.isValidId(rewardId) then
		return "invalid", `invalid reward id '{tostring(rewardId)}'`
	end
	local claimed = data.ClaimedRewardIds
	if claimed[rewardId] ~= nil then
		return "already", nil
	end

	claimed[rewardId] = now
	-- Cast: pcall on a no-result function is typed as returning one value.
	local ok, err = pcall(grant :: any, data)
	if not ok then
		return "error", tostring(err)
	end
	return "granted", nil
end

--[[
	Removes expired claims according to RETENTION_SECONDS. Returns the number
	of removed entries.
]]
function RewardClaims.prune(data: { [string]: any }, now: number): number
	local removed = 0
	local claimed = data.ClaimedRewardIds
	for rewardId, claimedAt in claimed do
		local prefix = string.match(rewardId, "^(%u+):")
		local retention = if prefix then RewardClaims.RETENTION_SECONDS[prefix] else nil
		if retention ~= false and (retention == nil or now - claimedAt > retention) then
			claimed[rewardId] = nil
			removed += 1
		end
	end
	return removed
end

return table.freeze(RewardClaims)
