local load = require("../loader")
local Migrations = load("src/server/Persistence/Migrations")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")

return function(t)
	t.it("current version matches the template", function()
		t.eq(Migrations.CURRENT_VERSION, ProfileTemplate.SCHEMA_VERSION)
	end)

	t.it("a current profile migrates to an equal copy, input untouched", function()
		local data = ProfileTemplate.new()
		local status, result = Migrations.migrate(data)
		t.eq(status, "ok")
		t.ok(result ~= data, "must return a copy")
		t.eq(result.SchemaVersion, Migrations.CURRENT_VERSION)
		t.eq(result.Level, data.Level)
	end)

	t.it("refuses profiles from a newer build", function()
		local data = ProfileTemplate.new()
		data.SchemaVersion = Migrations.CURRENT_VERSION + 1
		local status, version = Migrations.migrate(data)
		t.eq(status, "newer")
		t.eq(version, Migrations.CURRENT_VERSION + 1)
	end)

	t.it("treats a missing/invalid version as v1", function()
		local status = Migrations.migrate({ SchemaVersion = "x" })
		t.eq(status, "ok")
	end)

	t.it("runs steps in order up to the target version", function()
		local order = {}
		local steps = {
			[1] = function(d)
				table.insert(order, 1)
				d.Gold = d.Coins
				d.Coins = nil
				return d
			end,
			[2] = function(d)
				table.insert(order, 2)
				d.Gold *= 2
				return d
			end,
		}
		local input = { SchemaVersion = 1, Coins = 10 }
		local status, result = Migrations.migrate(input, 3, steps)
		t.eq(status, "ok")
		t.eq(table.concat(order, ","), "1,2")
		t.eq(result.Gold, 20)
		t.eq(result.SchemaVersion, 3)
		t.eq(input.Coins, 10, "input must be untouched")
	end)

	t.it("starts from the stored version, skipping earlier steps", function()
		local ran1 = false
		local steps = {
			[1] = function(d)
				ran1 = true
				return d
			end,
			[2] = function(d)
				return d
			end,
		}
		local status = Migrations.migrate({ SchemaVersion = 2 }, 3, steps)
		t.eq(status, "ok")
		t.eq(ran1, false)
	end)

	t.it("reports missing and failing steps without touching the input", function()
		local input = { SchemaVersion = 1, Value = 1 }
		local status, message = Migrations.migrate(input, 2, {})
		t.eq(status, "error")
		t.ok(string.find(message, "missing", 1, true) ~= nil)

		local status2, message2 = Migrations.migrate(input, 2, {
			[1] = function(d)
				d.Value = 999
				error("boom")
			end,
		})
		t.eq(status2, "error")
		t.ok(string.find(message2, "boom", 1, true) ~= nil)
		t.eq(input.Value, 1)
	end)
end
