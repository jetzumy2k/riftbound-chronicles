--!strict
--[[
	Signal
	Minimal synchronous signal. Handlers run in connection order on the firing
	thread, each inside xpcall so one failing handler cannot break the others or
	the caller. Synchronous delivery keeps server state transitions atomic
	(docs/DATA_MODEL.md §4.1): handlers must not yield.

	Pure module: no Roblox APIs.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

type Handler = {
	fn: (...any) -> (),
	connection: Connection,
}

local Signal = {}

local function defaultErrorHandler(err: any)
	warn(`[RC][Signal] handler error: {tostring(err)}`)
end

--[[
	Creates a signal. `onError` receives (error, traceback) for failing handlers.
]]
function Signal.new(onError: ((err: any, trace: string) -> ())?): Signal
	local handlers: { Handler } = {}

	local signal = {} :: any

	function signal.Connect(_: any, fn: (...any) -> ()): Connection
		local connection = { Connected = true } :: any
		local entry: Handler = { fn = fn, connection = connection }

		function connection.Disconnect(_: any)
			if not connection.Connected then
				return
			end
			connection.Connected = false
			local index = table.find(handlers, entry)
			if index then
				table.remove(handlers, index)
			end
		end

		table.insert(handlers, entry)
		return connection
	end

	function signal.Fire(_: any, ...: any)
		-- Snapshot so handlers that (dis)connect during Fire do not affect this dispatch.
		local snapshot = table.clone(handlers)
		for _, entry in snapshot do
			if entry.connection.Connected then
				local ok, err = xpcall(entry.fn :: any, debug.traceback, ...)
				if not ok then
					if onError then
						onError(err, tostring(err))
					else
						defaultErrorHandler(err)
					end
				end
			end
		end
	end

	function signal.DisconnectAll(_: any)
		for _, entry in handlers do
			entry.connection.Connected = false
		end
		table.clear(handlers)
	end

	return signal :: Signal
end

return table.freeze(Signal)
