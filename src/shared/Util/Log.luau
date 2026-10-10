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
-- `location` is "Folder.Module:line" of the code that logged (nil if unknown).
export type Sink = (level: Level, scope: string, message: string, location: string?) -> ()

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

-- Roblox attributes print/warn to this module ("Log:NN"), so the real call
-- site is appended to each line instead.
local function defaultSink(level: Level, scope: string, message: string, location: string?)
	local line = if location
		then `[RC][{level}][{scope}] {message}  @{location}`
		else `[RC][{level}][{scope}] {message}`
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

--[[
	Returns "Parent.Module:line" for the stack frame `depth` levels above the
	caller of this function, or nil.
]]
local function callSite(depth: number): string?
	local source, line = debug.info(depth + 1, "sl")
	if source == nil or line == nil then
		return nil
	end
	-- Keep the last two path segments: "Services.NetService" / "specs/log.spec".
	local segments = string.split((string.gsub(source, "[/]", ".")), ".")
	local count = #segments
	local short = if count >= 2 then `{segments[count - 1]}.{segments[count]}` else source
	return `{short}:{line}`
end

local function emit(level: Level, scope: string, location: string?, fmt: string, ...: any)
	if LEVEL_RANK[level] < minimumRank then
		return
	end
	-- Cast: pcall on a no-result function is typed as returning one value.
	local ok, err = pcall(sink :: any, level, scope, format(fmt, ...), location)
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

	-- callSite(2): skip callSite's caller (this method) to reach the logging code.
	function logger:Debug(fmt: string, ...: any)
		emit("Debug", scope, callSite(2), fmt, ...)
	end
	function logger:Info(fmt: string, ...: any)
		emit("Info", scope, callSite(2), fmt, ...)
	end
	function logger:Warn(fmt: string, ...: any)
		emit("Warn", scope, callSite(2), fmt, ...)
	end
	function logger:Error(fmt: string, ...: any)
		emit("Error", scope, callSite(2), fmt, ...)
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
		emit(level, scope, callSite(2), "%s", message)
	end

	return logger :: Logger
end

return Log
