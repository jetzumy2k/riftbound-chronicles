local load = require("../loader")
local Signal = load("src/shared/Util/Signal")

return function(t)
	t.it("delivers to handlers in connection order with arguments", function()
		local signal = Signal.new()
		local calls = {}
		signal:Connect(function(a, b)
			table.insert(calls, `1:{a}{b}`)
		end)
		signal:Connect(function(a, b)
			table.insert(calls, `2:{a}{b}`)
		end)
		signal:Fire("x", "y")
		t.eq(table.concat(calls, ","), "1:xy,2:xy")
	end)

	t.it("isolates handler errors", function()
		local errors = 0
		local signal = Signal.new(function()
			errors += 1
		end)
		local reached = false
		signal:Connect(function()
			error("boom")
		end)
		signal:Connect(function()
			reached = true
		end)
		signal:Fire()
		t.eq(errors, 1)
		t.ok(reached)
	end)

	t.it("disconnect stops delivery, including during a fire", function()
		local signal = Signal.new()
		local count = 0
		local second
		signal:Connect(function()
			count += 1
			second:Disconnect()
		end)
		second = signal:Connect(function()
			count += 100
		end)
		signal:Fire()
		t.eq(count, 1)
		t.eq(second.Connected, false)
		signal:Fire()
		t.eq(count, 2)
	end)

	t.it("DisconnectAll clears every handler", function()
		local signal = Signal.new()
		local count = 0
		local connection = signal:Connect(function()
			count += 1
		end)
		signal:DisconnectAll()
		signal:Fire()
		t.eq(count, 0)
		t.eq(connection.Connected, false)
	end)
end
