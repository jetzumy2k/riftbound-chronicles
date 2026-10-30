--!strict
--[[
	AdminRules — pure rules for the admin / moderator panel (Phase 17,
	PLAN.md D-77, SECURITY_MODEL §6, T-19 / T-20).

	  roleFor            a UserId's staff role from the Roles config and the
	                     place's creator (nil = not staff)
	  has / permissionsFor   the permission matrix (SECURITY_MODEL §6); a
	                     Moderator gets "grant-only" permissions only when
	                     listed in Roles.ModeratorGrants
	  permissionForPath  which permission edits a config value (nil = not
	                     editable from the panel: network, logging, anti-cheat
	                     and the override switch itself stay code-only)
	  flatten            every editable config value as a flat entry (path,
	                     kind, limits, current and default value) for the panel
	  applyChanges       a new override (nested values) with a batch of
	                     changes applied; lists replace whole (ConfigCore rule)
	  ACTION_PERMISSION  which permission each player action needs

	The matrix is not secret (who is staff is: Roles stays on the server).
	Pure module.
]]

local AdminRules = {}

-- GameMaster: assigned in the panel only (D-112, StaffRules).
export type Role = "Owner" | "Admin" | "Moderator" | "GameMaster"

AdminRules.ROLES = table.freeze({ "Owner", "Admin", "Moderator", "GameMaster" })

-- Every permission, in display order.
AdminRules.PERMISSIONS = table.freeze({
	"panel.open",
	"player.inspect",
	"player.inspectFull",
	"player.edit",
	"items.grant",
	"items.remove",
	"quests.manage",
	"bosses.manage",
	"config.view",
	"config.dropRates",
	"config.enhancement",
	"config.game",
	"moderation.kick",
	"moderation.ban",
	"events.activate",
	"audit.view",
	"audit.viewAll",
	"roles.assign",
	-- D-111: the whole-game reset (Owner only).
	"system.reset",
	-- D-112: the panel staff list and pay (Owner and Admins; an Admin's
	-- assignments wait for the Owner, StaffRules.decide).
	"staff.manage",
})

-- Moderators: support and moderation only (CLAUDE.md §21: no economy, drop
-- rates, item creation, roles or data editing).
local MODERATOR = table.freeze({
	["panel.open"] = true,
	["player.inspect"] = true,
	["moderation.kick"] = true,
	["audit.view"] = true,
})
-- Moderator permissions that need an explicit grant (Roles.ModeratorGrants).
AdminRules.GRANT_ONLY = table.freeze({
	["moderation.ban"] = true,
	["events.activate"] = true,
})

function AdminRules.has(role: Role?, permission: string, grants: { string }?): boolean
	if role == "Owner" then
		return table.find(AdminRules.PERMISSIONS, permission) ~= nil
	elseif role == "Admin" then
		return permission ~= "roles.assign"
			and permission ~= "system.reset"
			and table.find(AdminRules.PERMISSIONS, permission) ~= nil
	elseif role == "Moderator" then
		if MODERATOR[permission] then
			return true
		end
		return AdminRules.GRANT_ONLY[permission] == true
			and grants ~= nil
			and table.find(grants, permission) ~= nil
	end
	return false
end

function AdminRules.permissionsFor(role: Role?, grants: { string }?): { string }
	local out = {}
	for _, permission in AdminRules.PERMISSIONS do
		if AdminRules.has(role, permission, grants) then
			table.insert(out, permission)
		end
	end
	return out
end

export type RolesConfig = {
	Owners: { number },
	Admins: { number },
	Moderators: { number },
	ModeratorGrants: { string },
}

--[[
	The staff role of `userId`. `creatorUserId` is the place's creator when
	a user owns it (group-owned places list their owners in Roles.Owners).
	The highest listed role wins.
]]
function AdminRules.roleFor(userId: number, creatorUserId: number?, roles: RolesConfig): Role?
	if
		(creatorUserId ~= nil and creatorUserId > 0 and userId == creatorUserId)
		or table.find(roles.Owners, userId)
	then
		return "Owner"
	elseif table.find(roles.Admins, userId) then
		return "Admin"
	elseif table.find(roles.Moderators, userId) then
		return "Moderator"
	end
	return nil
end

-- Player actions (AdminPlayerAction) and the permission each needs.
AdminRules.ACTIONS = table.freeze({
	"Kick",
	"Ban",
	"SetLevel",
	"AddCurrency",
	"SetVictories",
	"GrantItem",
	"GrantStackable",
	"RemoveItem",
	"ResetQuest",
	-- D-126: test overrides for Max HP / Attack / Defense (session only).
	"SetStat",
})
AdminRules.ACTION_PERMISSION = table.freeze({
	Kick = "moderation.kick",
	Ban = "moderation.ban",
	SetLevel = "player.edit",
	AddCurrency = "player.edit",
	SetVictories = "player.edit",
	GrantItem = "items.grant",
	GrantStackable = "items.grant",
	RemoveItem = "items.remove",
	ResetQuest = "quests.manage",
	SetStat = "player.edit",
})
-- Preset reasons shown to a kicked / banned player (no free text).
AdminRules.REASONS = table.freeze({ "Exploiting", "Harassment", "Inappropriate", "Spamming", "Other" })
AdminRules.REASON_TEXT = table.freeze({
	Exploiting = "Removed by a moderator: exploiting or cheating.",
	Harassment = "Removed by a moderator: harassing other players.",
	Inappropriate = "Removed by a moderator: inappropriate behaviour.",
	Spamming = "Removed by a moderator: spamming.",
	Other = "Removed by a moderator.",
})
-- Ban lengths offered (minutes; 0 = permanent).
AdminRules.BAN_MINUTES = table.freeze({ 60, 1440, 10080, 0 })
AdminRules.MAX_CURRENCY_STEP = 1000000000
AdminRules.MAX_VICTORIES = 10000000

--------------------------------------------------------------------------------
-- Config editing
--------------------------------------------------------------------------------

-- Top-level config sections the panel edits, and the permission for each.
AdminRules.CONFIG_SECTIONS = table.freeze({
	Loot = "config.dropRates",
	Enhancement = "config.enhancement",
	Flags = "config.game",
	PvP = "config.game",
	Quests = "config.game",
	Dungeon = "config.game",
	Party = "config.game",
	Mobs = "config.game",
	Skills = "config.game",
	Combat = "config.game",
	Appearance = "config.game",
	Mall = "config.game",
	Shop = "config.game",
	Exchange = "config.game",
	Durability = "config.game",
	ChainQuest = "config.game",
	Roulette = "config.game",
	Trade = "config.game",
	Auction = "config.game",
	Puzzle = "config.game",
	Progression = "config.game",
})
-- Section order in the panel.
AdminRules.SECTION_ORDER = table.freeze({
	"Flags",
	"Progression",
	"Loot",
	"Enhancement",
	"PvP",
	"Quests",
	"Dungeon",
	"Party",
	"Mobs",
	"Skills",
	"Combat",
	"Appearance",
	"Mall",
	"Shop",
	"Exchange",
	"Durability",
	"ChainQuest",
	"Roulette",
	"Trade",
	"Auction",
	"Puzzle",
})
-- Values that stay code-only even inside an editable section.
AdminRules.LOCKED_PATHS = table.freeze({
	["Flags.ConfigOverrides"] = true,
})
AdminRules.MAX_CHANGES = 40

local function segments(path: string): { string }
	local out = {}
	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(out, segment)
	end
	return out
end

function AdminRules.permissionForPath(path: any): string?
	if type(path) ~= "string" or #path > 96 or AdminRules.LOCKED_PATHS[path] then
		return nil
	end
	local first = string.match(path, "^([%w]+)")
	return if first then AdminRules.CONFIG_SECTIONS[first] else nil
end

export type Entry = {
	path: string,
	kind: "number" | "boolean" | "enum" | "string",
	min: number?,
	max: number?,
	integer: boolean?,
	values: { string }?,
	value: any,
	default: any,
}

local function childValue(container: any, key: any): any
	return if type(container) == "table" then container[key] else nil
end

local function walk(spec: any, value: any, default: any, path: string, out: { Entry })
	local kind = spec.kind
	if kind == "struct" then
		local keys = {}
		for key in spec.fields do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			walk(spec.fields[key], childValue(value, key), childValue(default, key), `{path}.{key}`, out)
		end
	elseif kind == "map" then
		-- Enum-keyed maps list every key; others only the keys present.
		local keys = {}
		if spec.keys.kind == "enum" then
			for _, key in spec.keys.values do
				table.insert(keys, key)
			end
		else
			for key in (if type(value) == "table" then value else {}) :: { [any]: any } do
				table.insert(keys, key)
			end
			table.sort(keys)
		end
		for _, key in keys do
			walk(spec.of, childValue(value, key), childValue(default, key), `{path}.{key}`, out)
		end
	elseif kind == "array" then
		local count = if type(value) == "table" then #value else 0
		for index = 1, count do
			walk(spec.of, value[index], childValue(default, index), `{path}.{index}`, out)
		end
	elseif kind == "number" or kind == "boolean" or kind == "enum" or kind == "string" then
		if AdminRules.LOCKED_PATHS[path] then
			return
		end
		table.insert(out, {
			path = path,
			kind = kind,
			min = spec.min,
			max = spec.max,
			integer = spec.integer,
			values = spec.values,
			value = value,
			default = default,
		})
	end
end

--[[
	Every editable leaf of the editable sections. `spec` is the config
	schema (a struct), `effective` the live config, `defaults` the code
	defaults.
]]
function AdminRules.flatten(spec: any, effective: any, defaults: any): { Entry }
	local out = {}
	for _, section in AdminRules.SECTION_ORDER do
		local child = spec.fields[section]
		if child then
			walk(child, effective[section], defaults[section], section, out)
		end
	end
	return out
end

--[[
	The schema of the leaf at `path` and, when that leaf sits in a list, the
	path of the list (lists are written whole). nil when unknown.
]]
function AdminRules.leafAt(spec: any, path: string): (any, string?)
	local node = spec
	local listPath: string? = nil
	local walked = ""
	for _, segment in segments(path) do
		if node == nil then
			return nil, nil
		end
		if node.kind == "struct" then
			node = node.fields[segment]
		elseif node.kind == "map" then
			if node.keys.kind == "enum" and table.find(node.keys.values, segment) == nil then
				return nil, nil
			end
			node = node.of
		elseif node.kind == "array" then
			local index = tonumber(segment)
			if index == nil or index % 1 ~= 0 or index < 1 or index > node.maxCount then
				return nil, nil
			end
			listPath = walked
			node = node.of
		else
			return nil, nil
		end
		walked = if walked == "" then segment else `{walked}.{segment}`
	end
	if node == nil or node.kind == "struct" or node.kind == "map" or node.kind == "array" then
		return nil, nil
	end
	return node, listPath
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function getPath(root: any, parts: { string }): any
	local node = root
	for _, part in parts do
		if type(node) ~= "table" then
			return nil
		end
		node = node[tonumber(part) or part]
	end
	return node
end

local function setPath(root: { [any]: any }, parts: { string }, value: any)
	local node = root
	for index = 1, #parts - 1 do
		local key = parts[index]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[parts[#parts]] = value
end

local function removePath(root: { [any]: any }, parts: { string })
	local node = root
	local trail: { { any } } = {}
	for index = 1, #parts - 1 do
		local nextNode = node[parts[index]]
		if type(nextNode) ~= "table" then
			return
		end
		table.insert(trail, { node :: any, parts[index] :: any })
		node = nextNode
	end
	node[parts[#parts]] = nil
	-- Drop now-empty tables so the override stays small.
	for index = #trail, 1, -1 do
		local parent, key = trail[index][1], trail[index][2]
		if next(parent[key]) == nil then
			parent[key] = nil
		end
	end
end

export type Change = { Path: string, Number: number?, Bool: boolean?, Text: string?, Reset: boolean? }

--[[
	Applies `changes` to a copy of `overrideValues` (the nested override).
	`effective` supplies whole lists when one element changes. Returns the
	new values, or nil and a reason ("path <p>", "value <p>").
	Permissions are checked by the caller; whole-config validation too.
]]
function AdminRules.applyChanges(
	spec: any,
	overrideValues: any,
	effective: any,
	changes: { Change }
): (any, string?)
	local values = deepCopy(overrideValues or {})
	for _, change in changes do
		local path = change.Path
		local leaf, listPath = AdminRules.leafAt(spec, path)
		if leaf == nil or AdminRules.permissionForPath(path) == nil then
			return nil, `path {path}`
		end
		if change.Reset then
			removePath(values, segments(listPath or path))
			continue
		end
		local value: any = nil
		if leaf.kind == "number" then
			value = change.Number
		elseif leaf.kind == "boolean" then
			value = change.Bool
		else
			value = change.Text
		end
		if value == nil then
			return nil, `value {path}`
		end
		if leaf.kind == "number" then
			if
				value ~= value
				or (leaf.min and value < leaf.min)
				or (leaf.max and value > leaf.max)
				or (leaf.integer and value % 1 ~= 0)
			then
				return nil, `value {path}`
			end
		elseif leaf.kind == "enum" and table.find(leaf.values, value) == nil then
			return nil, `value {path}`
		elseif leaf.kind == "string" and (#value > (leaf.maxLen or 40)) then
			return nil, `value {path}`
		end
		if listPath then
			-- Lists are written whole: start from the live list.
			local listParts = segments(listPath)
			local list = getPath(values, listParts)
			if type(list) ~= "table" then
				list = deepCopy(getPath(effective, listParts)) or {}
				setPath(values, listParts, list)
			end
			list[tonumber(string.match(path, "(%d+)$")) :: number] = value
		else
			setPath(values, segments(path), value)
		end
	end
	return values, nil
end

-- Read a dotted path from a nested table (numeric segments index lists).
function AdminRules.getPath(root: any, path: string): any
	return getPath(root, segments(path))
end

return table.freeze(AdminRules)
