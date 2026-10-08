--!strict
--[[
	Log
	Scoped, leveled logging with throttling.

	    local log = Log.new("NetService")
	    log:Info("created %d remotes", count)
	    log:Throttled("reject:" .. userId, 10, "Warn", "rejected %s", code)

	The sink is injectable so tests (and later an external log sink) can capture
	output. Messages never include chat text or secrets (SECURITY_MODEL.md §7).

	Pure module: no Roblox APIs.
]]

export type Level = "Debug" | "Info" | "Warn" | "Error"
export type Sink = (level: Level, scope: string, message: string) -> ()

export type Logger = {
	scope: string,
	Debug: (self: Logger, fmt: string, ...any) -> (),
	Info: (self: Logger, fmt: string, ...any) -> (),
	Warn: (self: Logger, fmt: string, ...any) -> (),
	Error: (self: Logger, fmt: string, ...any) -> (),
	Throttled: (self: Logger, key: string, seconds: number, level: Level, fmt: string, ...any) -> (),
}

local LEVEL_RANK: { [string]: number } = { Debug = 1, Info = 2, Warn = 3, Error = 4 }

local Log = {}

local minimumRank = LEVEL_RANK.Info

local function defaultSink(level: Level, scope: string, message: string)
	local line = `[RC][{level}][{scope}] {message}`
	if level == "Warn" or level == "Error" then
		warn(line)
	else
		print(line)
	end
end

local sink: Sink = defaultSink

-- key -> { nextAllowedAt, suppressed }
local throttleState: { [string]: { nextAllowedAt: number, suppressed: number } } = {}

local function format(fmt: string, ...: any): string
	if select("#", ...) == 0 then
		return fmt
	end
	local ok, result = pcall(string.format, fmt, ...)
	if ok then
		return result
	end
	-- Never let a bad format string break the caller.
	return `{fmt} <format error: {tostring(result)}>`
end

local function emit(level: Level, scope: string, fmt: string, ...: any)
	if LEVEL_RANK[level] < minimumRank then
		return
	end
	-- Cast: pcall on a no-result function is typed as returning one value.
	local ok, err = pcall(sink :: any, level, scope, format(fmt, ...))
	if not ok then
		defaultSink("Error", "Log", `sink failed: {tostring(err)}`)
	end
end

function Log.setLevel(level: Level)
	local rank = LEVEL_RANK[level]
	assert(rank ~= nil, `unknown log level '{tostring(level)}'`)
	minimumRank = rank
end

function Log.getLevel(): Level
	for level, rank in LEVEL_RANK do
		if rank == minimumRank then
			return level :: Level
		end
	end
	return "Info"
end

-- Replaces the output sink; pass nil to restore the default.
function Log.setSink(newSink: Sink?)
	sink = newSink or defaultSink
end

-- Clears throttle state for keys starting with `prefix` (e.g. on player leave).
function Log.clearThrottle(prefix: string)
	for key in throttleState do
		if string.sub(key, 1, #prefix) == prefix then
			throttleState[key] = nil
		end
	end
end

function Log.new(scope: string): Logger
	local logger = { scope = scope } :: any

	function logger:Debug(fmt: string, ...: any)
		emit("Debug", scope, fmt, ...)
	end
	function logger:Info(fmt: string, ...: any)
		emit("Info", scope, fmt, ...)
	end
	function logger:Warn(fmt: string, ...: any)
		emit("Warn", scope, fmt, ...)
	end
	function logger:Error(fmt: string, ...: any)
		emit("Error", scope, fmt, ...)
	end

	--[[
		Emits at most once per `seconds` per `key`. The next emitted line reports
		how many messages were suppressed in between.
	]]
	function logger:Throttled(key: string, seconds: number, level: Level, fmt: string, ...: any)
		local now = os.clock()
		local state = throttleState[key]
		if state and now < state.nextAllowedAt then
			state.suppressed += 1
			return
		end
		local suppressed = if state then state.suppressed else 0
		throttleState[key] = { nextAllowedAt = now + seconds, suppressed = 0 }
		local message = format(fmt, ...)
		if suppressed > 0 then
			message ..= ` (+{suppressed} suppressed)`
		end
		emit(level, scope, "%s", message)
	end

	return logger :: Logger
end

return Log
