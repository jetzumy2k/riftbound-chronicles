local load = require("../loader")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")

local DAY = 86400

return function(t)
	t.it("grants once and only once", function()
		local data = ProfileTemplate.new()
		local grants = 0
		local function grant(d)
			grants += 1
			d.Wallet.Gold += 50
		end
		t.eq(RewardClaims.claim(data, "Q:FirstSpark", 1000, grant), "granted")
		for _ = 1, 20 do
			t.eq(RewardClaims.claim(data, "Q:FirstSpark", 1000, grant), "already")
		end
		t.eq(grants, 1)
		t.eq(data.Wallet.Gold, 50)
		t.ok(RewardClaims.isClaimed(data, "Q:FirstSpark"))
	end)

	t.it("rejects malformed or unknown-prefix ids", function()
		local data = ProfileTemplate.new()
		local function grant() end
		t.eq(RewardClaims.claim(data, "FirstSpark", 0, grant), "invalid")
		t.eq(RewardClaims.claim(data, "X:Thing", 0, grant), "invalid")
		t.eq(RewardClaims.claim(data, "Q:has space", 0, grant), "invalid")
		t.eq(RewardClaims.claim(data, "Q:" .. string.rep("a", 200), 0, grant), "invalid")
		t.eq(RewardClaims.claim(data, 5 :: any, 0, grant), "invalid")
	end)

	t.it("a failing grant keeps the claim (no duplication) and reports the error", function()
		local data = ProfileTemplate.new()
		local status, err = RewardClaims.claim(data, "D:job1:7", 0, function()
			error("bad grant")
		end)
		t.eq(status, "error")
		t.ok(string.find(err, "bad grant", 1, true) ~= nil)
		t.eq(RewardClaims.claim(data, "D:job1:7", 0, function() end), "already")
	end)

	t.it("prunes expired claims by prefix, keeps quests forever", function()
		local data = ProfileTemplate.new()
		data.ClaimedRewardIds = {
			["Q:FirstSpark"] = 0,
			["D:old"] = 0,
			["D:new"] = 10 * DAY,
			["A:grant"] = 0,
			["E:event"] = 5 * DAY,
		}
		-- Day 12: D:old (7d) expired; E (14d) and A (30d) still retained.
		local removed = RewardClaims.prune(data, 12 * DAY)
		t.eq(removed, 1)
		t.ok(data.ClaimedRewardIds["Q:FirstSpark"] ~= nil)
		t.eq(data.ClaimedRewardIds["D:old"], nil)
		t.ok(data.ClaimedRewardIds["D:new"] ~= nil)
		t.ok(data.ClaimedRewardIds["A:grant"] ~= nil)
		t.ok(data.ClaimedRewardIds["E:event"] ~= nil)
		t.eq(data.ClaimedRewardIds["X"], nil)
	end)

	t.it("prunes ids with unknown prefixes", function()
		local data = ProfileTemplate.new()
		data.ClaimedRewardIds = { ["ZZ:legacy"] = 0, ["nocolon"] = 0 }
		t.eq(RewardClaims.prune(data, 0), 2)
	end)
end
