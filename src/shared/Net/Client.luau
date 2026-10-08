--!strict
--[[
	Net.Client
	Client-side access to remotes declared in the Registry. The client never
	creates remotes; it waits for the server-created folder.

	    NetClient.init()
	    NetClient.on("Notify", function(payload) ... end)
	    NetClient.fire("ClientReady")

	Client calls are *intents*. The server validates and decides every outcome.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent.Parent
local Constants = require(Shared.Constants)
local Schema = require(Shared.Logic.Schema)
local Log = require(Shared.Util.Log)
local Registry: { [string]: any } = require(script.Parent.Registry)(Schema)

local log = Log.new("NetClient")

local NetClient = {}

local folder: Folder? = nil

local function getRemote(name: string): Instance
	local spec = Registry[name]
	assert(spec ~= nil, `unknown remote '{name}'`)
	assert(folder ~= nil, "NetClient.init() must be called first")
	local remote = folder:FindFirstChild(name)
	assert(remote ~= nil, `remote '{name}' was not published by the server`)
	return remote
end

--[[
	Waits for the server to publish the remotes folder. Errors on timeout so the
	client bootstrap can show a connection problem instead of silently failing.
]]
function NetClient.init()
	if folder then
		return
	end
	local found =
		ReplicatedStorage:WaitForChild(Constants.Net.RemotesFolderName, Constants.Net.ClientRemoteWaitSeconds)
	if found == nil or not found:IsA("Folder") then
		error("timed out waiting for server remotes")
	end
	folder = found :: Folder
	log:Debug("remotes ready")
end

-- Sends a ClientToServer event.
function NetClient.fire(name: string, ...: any)
	local spec = Registry[name]
	assert(
		spec and spec.direction == "ClientToServer" and spec.kind == "Event",
		`'{name}' is not a client event`
	)
	local remote = getRemote(name) :: RemoteEvent
	remote:FireServer(...)
end

-- Invokes a ClientToServer function and returns the server's reply.
function NetClient.invoke(name: string, ...: any): any
	local spec = Registry[name]
	assert(
		spec and spec.direction == "ClientToServer" and spec.kind == "Function",
		`'{name}' is not a client function`
	)
	local remote = getRemote(name) :: RemoteFunction
	return remote:InvokeServer(...)
end

-- Listens to a ServerToClient event. Returns the RBXScriptConnection.
function NetClient.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local spec = Registry[name]
	assert(spec and spec.direction == "ServerToClient", `'{name}' is not a server event`)
	local remote = getRemote(name) :: RemoteEvent
	return remote.OnClientEvent:Connect(handler)
end

return table.freeze(NetClient)
