--!strict
--[[
	PersistenceAdapter
	Thin wrapper around ProfileStore (lm-loleris/profilestore@1.0.3, D-11) so the
	rest of the codebase never touches the library directly.

	Library facts this design relies on (verified in the package source):
	  - Session lock: a waiting server steals a session after SESSION_STEAL = 40 s;
	    a session not updated for ASSUME_DEAD = 630 s is treated as crashed.
	  - Auto-save every 300 s, final save on EndSession / server shutdown
	    (ProfileStore binds to game:BindToClose itself).
	  - Without DataStore access (unpublished place / Studio API access off) it
	    falls back to an in-memory mock: data does not persist between sessions.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("ServerPackages").ProfileStore)

export type Session = {
	-- Live data table; mutations are saved while the session is active.
	getData: (self: Session) -> { [string]: any },
	-- Replaces the data table (used to adopt a migrated copy).
	setData: (self: Session, data: { [string]: any }) -> (),
	isActive: (self: Session) -> boolean,
	endSession: (self: Session) -> (),
	onSessionEnd: (self: Session, callback: () -> ()) -> (),
	addUserId: (self: Session, userId: number) -> (),
}

export type Store = {
	startSession: (self: Store, key: string, isCancelled: () -> boolean) -> Session?,
}

local PersistenceAdapter = {}

local function wrapProfile(profile: any): Session
	local session = {} :: any

	function session.getData(_)
		return profile.Data
	end
	function session.setData(_, data)
		profile.Data = data
	end
	function session.isActive(_)
		return profile:IsActive()
	end
	function session.endSession(_)
		profile:EndSession()
	end
	function session.onSessionEnd(_, callback)
		profile.OnSessionEnd:Connect(callback)
	end
	function session.addUserId(_, userId)
		-- GDPR: associates the key with the user for Roblox erasure requests.
		profile:AddUserId(userId)
	end

	return session :: Session
end

--[[
	Opens a profile store. `template` must be the full default profile.
]]
function PersistenceAdapter.open(storeName: string, template: { [string]: any }): Store
	local store = ProfileStore.New(storeName, template)
	local wrapper = {} :: any

	function wrapper.startSession(_, key: string, isCancelled: () -> boolean): Session?
		local profile = store:StartSessionAsync(key, { Cancel = isCancelled } :: any)
		if profile == nil then
			return nil
		end
		return wrapProfile(profile)
	end

	return wrapper :: Store
end

-- "NotReady" | "NoInternet" | "NoAccess" | "Access"
function PersistenceAdapter.getDataStoreState(): string
	return ProfileStore.DataStoreState
end

return PersistenceAdapter
