--!strict
--[[
	Guard
	Error boundary helper. Runs a function in xpcall with a traceback and reports
	failures through a logger instead of propagating them.

	    local ok, result = Guard.call(log, "ConfigurationService.Init", fn, arg)

	Pure module: no Roblox APIs.
]]

type LoggerLike = {
	Error: (self: any, fmt: string, ...any) -> (),
}

local Guard = {}

--[[
	Calls fn(...) safely. Returns (true, ...results) on success or (false, errorMessage)
	on failure; failures are logged with `label` and the traceback.
]]
function Guard.call(logger: LoggerLike, label: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(xpcall(fn, function(err)
		return debug.traceback(tostring(err), 2)
	end, ...))
	if not results[1] then
		logger:Error("%s failed: %s", label, tostring(results[2]))
		return false, results[2]
	end
	return table.unpack(results, 1, results.n)
end

return table.freeze(Guard)
