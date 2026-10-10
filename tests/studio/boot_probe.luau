--[[
	Boot probe for run-in-roblox (server-only "Run" mode, no clients).

	    rojo build -o build/RiftboundChronicles.rbxlx
	    run-in-roblox --place build/RiftboundChronicles.rbxlx --script tests/studio/boot_probe.luau

	Waits for the server bootstrap, then asserts the Phase 1 acceptance points
	that are observable without a client. Prints PROBE PASS / PROBE FAIL lines.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local failures = 0
local function check(condition: boolean, label: string)
	if condition then
		print(`PROBE PASS {label}`)
	else
		failures += 1
		warn(`PROBE FAIL {label}`)
	end
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
task.wait(1) -- let Start() threads run

check(remotes ~= nil, "server published the Remotes folder")
if remotes then
	check(remotes:FindFirstChild("ClientReady") ~= nil, "ClientReady remote exists")
	check(remotes:FindFirstChild("Notify") ~= nil, "Notify remote exists")
	check(remotes.ClientReady:IsA("RemoteEvent"), "ClientReady is a RemoteEvent")
	check(remotes:FindFirstChild("ProfileSnapshot") ~= nil, "ProfileSnapshot remote exists")
	check(remotes:FindFirstChild("ProgressionUpdate") ~= nil, "ProgressionUpdate remote exists")
	check(remotes:FindFirstChild("SelectRace") ~= nil, "SelectRace remote exists")
	check(remotes:FindFirstChild("SelectJob") ~= nil, "SelectJob remote exists")
	check(remotes:FindFirstChild("BasicAttack") ~= nil, "BasicAttack remote exists")
	check(#remotes:GetChildren() == 8, `exactly the registered remotes exist ({#remotes:GetChildren()})`)
end

check(ReplicatedStorage:GetAttribute("RC_Maintenance") ~= true, "server is not in maintenance")
check(ReplicatedStorage:GetAttribute("RC_ConfigVersion") == 0, "config defaults active (version 0)")

-- No server code or config replicated.
local shared = ReplicatedStorage:FindFirstChild("Shared")
check(shared ~= nil, "Shared folder replicated")
check(ReplicatedStorage:FindFirstChild("Config", true) == nil, "no Config module in ReplicatedStorage")
check(ReplicatedStorage:FindFirstChild("Services", true) == nil, "no Services in ReplicatedStorage")
check(ServerScriptService:FindFirstChild("Server") ~= nil, "server bootstrap present in ServerScriptService")

-- Service API smoke checks through the real modules.
local Services = ServerScriptService.Server.Services
local ConfigurationService = require(Services.ConfigurationService)
check(ConfigurationService:Get("Net.GlobalCapacity") == 40, "config Get() returns defaults")
check(ConfigurationService:GetFlag("Maintenance") == false, "maintenance flag off")
check(not pcall(function()
	ConfigurationService:Get("Net.DoesNotExist")
end), "unknown config path raises")
check(table.isfrozen(ConfigurationService:Get("Net")), "config tables are frozen")

local NetService = require(Services.NetService)
check(not pcall(function()
	NetService:Handle("Notify", function() end)
end), "cannot register a handler on a server->client remote")
check(not pcall(function()
	NetService:Handle("ClientReady", function() end)
end), "cannot register a second handler")

-- Phase 2: progression services exist and expose no client entry points.
local LevelService = require(Services.LevelService)
local StatsService = require(Services.StatsService)
check(type(LevelService.GrantXP) == "function", "LevelService.GrantXP exists (server-internal)")
check(StatsService:GetBaseStats(nil :: any) == nil, "stats for an unloaded player are nil")

-- Phase 3: graybox world, fixed spawns, no auto-spawned characters.
local world = workspace:FindFirstChild("RC_World")
check(world ~= nil, "graybox world built")
check(world ~= nil and world:FindFirstChild("Spawn_Angel", true) ~= nil, "Angel spawn exists")
check(world ~= nil and world:FindFirstChild("Spawn_Devil", true) ~= nil, "Devil spawn exists")
check(game:GetService("Players").CharacterAutoLoads == false, "characters only spawn after race choice")

print(if failures == 0 then "PROBE RESULT: ALL PASSED" else `PROBE RESULT: {failures} FAILED`)
