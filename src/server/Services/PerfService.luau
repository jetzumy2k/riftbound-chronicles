--!strict
--[[
	PerfService — a periodic performance report (Phase 23, PLAN.md D-102).

	Every Perf.ReportSeconds (60) it logs one line: players, the server
	frame time (Heartbeat step, average and 95th percentile), memory, remote
	events per player per second both ways (NetService:TakeTraffic),
	creatures alive / awake (MobService:Counts) and the largest player
	outfit in parts. Anything over Logic/PerfBudget's limits is logged as a
	warning. Read-only: one Heartbeat connection that stores the step time,
	nothing sent to clients.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local PerfBudget = require(Shared.Logic.PerfBudget)

local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local MobService = require(script.Parent.MobService)

local PerfService = {}

local log = Log.new("PerfService")

-- At most this many frame samples a window (60 Hz x 10 min).
local MAX_SAMPLES = 36000

local samples: { number } = {}

-- The largest outfit among player characters, in parts.
local function largestOutfit(): number
	local largest = 0
	for _, player in Players:GetPlayers() do
		local outfit = player.Character and player.Character:FindFirstChild("RC_Outfit")
		if outfit then
			local count = outfit:GetAttribute("RC_AnimeParts")
			largest = math.max(largest, if type(count) == "number" then count else #outfit:GetChildren())
		end
	end
	return largest
end

local function report(seconds: number)
	local frames = samples
	samples = {}
	local inbound, outbound = NetService:TakeTraffic()
	local players = #Players:GetPlayers()
	local live, awake = MobService:Counts()
	local data: PerfBudget.Report = {
		players = players,
		frameAvgMs = PerfBudget.average(frames),
		frameP95Ms = PerfBudget.percentile(frames, 0.95),
		memoryMb = Stats:GetTotalMemoryUsageMb(),
		outPerPlayerPerSecond = PerfBudget.rate(outbound, players, seconds),
		inPerPlayerPerSecond = PerfBudget.rate(inbound, players, seconds),
		characterParts = largestOutfit(),
	}
	log:Info(
		"perf: players=%d frame avg %.1f ms p95 %.1f ms, memory %d MB, remotes/player/s out %.1f in %.1f, creatures %d live %d awake, largest outfit %d parts",
		players,
		data.frameAvgMs,
		data.frameP95Ms,
		math.floor(data.memoryMb),
		data.outPerPlayerPerSecond,
		data.inPerPlayerPerSecond,
		live,
		awake,
		data.characterParts
	)
	for _, over in PerfBudget.check(data) do
		log:Warn("perf over budget: %s %.1f > %.1f", over.field, over.value, over.limit)
	end
end

function PerfService:Start()
	RunService.Heartbeat:Connect(function(dt: number)
		if #samples < MAX_SAMPLES then
			table.insert(samples, dt * 1000)
		end
	end)
	task.spawn(function()
		while true do
			local seconds = ConfigurationService:Get("Perf.ReportSeconds")
			task.wait(seconds)
			xpcall(report, function(err)
				log:Error("perf report failed: %s", tostring(err))
			end, seconds)
		end
	end)
end

return PerfService
