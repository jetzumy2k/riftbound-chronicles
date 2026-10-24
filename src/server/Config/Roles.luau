--!strict
--[[
	Roles — staff by Roblox UserId (Phase 17, SECURITY_MODEL §6, T-20).

	Edited in code by the Owner only (never from the panel, a remote or the
	DataStore). The creator of a user-owned place is always Owner; for a
	group-owned place, list the owners here. Server-only (never replicated).

	  Owners           full control, including future role tools
	  Admins           everything except role assignment
	  Moderators       kick, inspect (limited), their own audit entries
	  ModeratorGrants  extra "grant-only" permissions for every Moderator:
	                   "moderation.ban", "events.activate"

	Pure data.
]]

return table.freeze({
	-- jetzumy2k (the creator).
	Owners = table.freeze({ 11763195295 }),
	Admins = table.freeze({} :: { number }),
	Moderators = table.freeze({} :: { number }),
	ModeratorGrants = table.freeze({} :: { string }),
})
