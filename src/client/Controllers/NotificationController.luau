--!strict
--[[
	NotificationController
	Receives server notifications. Phase 1 logs them; the mobile-first toast UI
	arrives with the UI framework (Phase 3 onward, polished in Phase 19).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)
local NetClient = require(Shared.Net.Client)

local log = Log.new("Notification")

local NotificationController = {}

function NotificationController:Init()
	NetClient.on("Notify", function(payload)
		if type(payload) ~= "table" then
			return
		end
		log:Info("%s: %s", tostring(payload.kind), tostring(payload.textKey))
	end)
end

return NotificationController
