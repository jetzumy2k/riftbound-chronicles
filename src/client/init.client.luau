--!strict
--[[
	Client bootstrap. The only client LocalScript; controllers are ModuleScripts
	initialised in a fixed order, then the server is told the client is ready.

	The client sends intents only; it never decides outcomes
	(ARCHITECTURE.md §3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)
local Guard = require(Shared.Util.Guard)
local NetClient = require(Shared.Net.Client)

-- Order matters: controllers listed earlier may be used by later ones.
local CONTROLLER_ORDER = {
	"NotificationController",
	"PlayerDataController",
	"HudController",
	"RaceSelectController",
	"JobSelectController",
	"CharacterMotionController",
	"CombatController",
	"CombatFeedbackController",
}

Log.setLevel(if RunService:IsStudio() then "Debug" else "Info")
local log = Log.new("Client")

if not Guard.call(log, "NetClient.init", NetClient.init) then
	-- Phase 19 shows a reconnect prompt here.
	return
end

local controllers = {}
for _, name in CONTROLLER_ORDER do
	local module = script.Controllers:FindFirstChild(name)
	if module == nil then
		log:Error("controller '%s' not found", name)
		continue
	end
	local ok, controller = Guard.call(log, `require {name}`, require, module)
	if ok then
		table.insert(controllers, { name = name, controller = controller })
	end
end

for _, item in controllers do
	if item.controller.Init then
		Guard.call(log, `{item.name}.Init`, item.controller.Init, item.controller)
	end
end

for _, item in controllers do
	if item.controller.Start then
		task.spawn(Guard.call, log, `{item.name}.Start`, item.controller.Start, item.controller)
	end
end

NetClient.fire("ClientReady")
log:Debug("client ready")
