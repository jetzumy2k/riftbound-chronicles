--[[
	Structural checks over the source tree (run from the repository root):
	  - service layering rules from Services/Manifest
	  - client/server/shared boundaries (no secrets replicated)
	  - remotes are only created by NetService
]]

local load = require("../loader")

local fs = require("@lune/fs")

local Manifest = load("src/server/Services/Manifest")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)

local PURE_PERSISTENCE =
	{ "ProfileTemplate", "ProfileValidator", "Migrations", "RewardClaims", "ProfileView" }

local SRC = "src"

local function listFiles(dir: string, out: { string }?): { string }
	local files = out or {}
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			listFiles(path, files)
		elseif string.match(name, "%.luau$") then
			table.insert(files, path)
		end
	end
	return files
end

local function stripComments(source: string): string
	source = string.gsub(source, "%-%-%[(=*)%[.-%]%1%]", "")
	source = string.gsub(source, "%-%-[^\n]*", "")
	return source
end

return function(t)
	t.describe("service manifest", function()
		local layerOf: { [string]: number } = {}
		local orderOf: { [string]: number } = {}
		for index, entry in Manifest do
			layerOf[entry.name] = entry.layer
			orderOf[entry.name] = index
		end

		t.it("every manifest entry has a module and every service module is listed", function()
			for name in layerOf do
				t.ok(fs.isFile(`{SRC}/server/Services/{name}.luau`), `missing module for {name}`)
			end
			for _, name in fs.readDir(`{SRC}/server/Services`) do
				local serviceName = string.match(name, "^(.+)%.luau$")
				if serviceName and serviceName ~= "Manifest" then
					t.ok(layerOf[serviceName] ~= nil, `{serviceName} is not in the manifest`)
				end
			end
		end)

		t.it("services only require same-or-lower layers, earlier in the order", function()
			for name, layer in layerOf do
				local source = stripComments(fs.readFile(`{SRC}/server/Services/{name}.luau`))
				for dependency in string.gmatch(source, "require%(script%.Parent%.([%w_]+)%)") do
					local depLayer = layerOf[dependency]
					t.ok(depLayer ~= nil, `{name} requires unknown service {dependency}`)
					t.ok(
						depLayer <= layer,
						`{name} (L{layer}) requires higher-layer {dependency} (L{depLayer})`
					)
					if depLayer == layer then
						t.ok(
							orderOf[dependency] < orderOf[name],
							`{name} requires {dependency}, which boots later`
						)
					end
				end
			end
		end)
	end)

	t.describe("boundaries", function()
		t.it("shared code never references server-only containers", function()
			for _, path in listFiles(`{SRC}/shared`) do
				local source = stripComments(fs.readFile(path))
				t.ok(
					not string.find(source, "ServerScriptService", 1, true),
					`{path} references ServerScriptService`
				)
				t.ok(not string.find(source, "ServerStorage", 1, true), `{path} references ServerStorage`)
			end
		end)

		t.it("client code never references server-only containers", function()
			for _, path in listFiles(`{SRC}/client`) do
				local source = stripComments(fs.readFile(path))
				t.ok(
					not string.find(source, "ServerScriptService", 1, true),
					`{path} references ServerScriptService`
				)
				t.ok(not string.find(source, "ServerStorage", 1, true), `{path} references ServerStorage`)
			end
		end)

		t.it("server config lives only under src/server (never replicated)", function()
			t.ok(fs.isFile(`{SRC}/server/Config/Defaults.luau`))
			t.ok(not fs.isDir(`{SRC}/shared/Config`), "config must not be in shared")
		end)

		t.it("no signal connection is called like a function (formatter-joined lines)", function()
			-- Regression (2026-10-26): a statement starting with "(" after
			-- ":Connect(fn)" was joined by the formatter into
			-- ":Connect(fn)(...)", which errors at run time and stopped the
			-- HUD from showing HP and EXP.
			for _, path in listFiles(SRC) do
				local text = fs.readFile(path)
				t.ok(string.find(text, "Connect%([%w_%.]+%)%s*%(") == nil, `{path} calls a connection`)
			end
		end)

		t.it("only NetService creates remotes", function()
			for _, path in listFiles(SRC) do
				local source = stripComments(fs.readFile(path))
				local creates = string.find(source, 'Instance.new%("Remote')
					or string.find(source, '"RemoteFunction" else "RemoteEvent"', 1, true)
				if creates then
					t.eq(path, `{SRC}/server/Services/NetService.luau`, `{path} creates remotes`)
				end
			end
		end)

		local function pureFiles(): { string }
			local files = {}
			listFiles(`{SRC}/shared/Logic`, files)
			listFiles(`{SRC}/shared/Util`, files)
			listFiles(`{SRC}/shared/Definitions`, files)
			listFiles(`{SRC}/shared/Layout`, files)
			listFiles(`{SRC}/server/Config`, files)
			for _, name in PURE_PERSISTENCE do
				table.insert(files, `{SRC}/server/Persistence/{name}.luau`)
			end
			table.insert(files, `{SRC}/shared/Enums.luau`)
			table.insert(files, `{SRC}/shared/Constants.luau`)
			table.insert(files, `{SRC}/shared/Types.luau`)
			table.insert(files, `{SRC}/shared/Net/Registry.luau`)
			table.insert(files, `{SRC}/shared/Net/NetSpec.luau`)
			return files
		end

		t.it("pure modules only use ReplicatedStorage (for shared requires)", function()
			for _, path in pureFiles() do
				local source = stripComments(fs.readFile(path))
				for service in string.gmatch(source, 'GetService%("([%w]+)"%)') do
					t.eq(service, "ReplicatedStorage", `{path} uses GetService("{service}")`)
				end
				t.ok(not string.find(source, "Instance.new", 1, true), `{path} creates instances`)
			end
		end)

		t.it("the loader refuses modules that need engine services", function()
			local ok, err = pcall(load, "src/server/Services/RateLimitService")
			t.eq(ok, false)
			t.ok(string.find(tostring(err), "not available to pure modules", 1, true) ~= nil, tostring(err))
		end)

		t.it("every pure module loads outside Roblox (no hidden engine dependencies)", function()
			for _, path in pureFiles() do
				local modulePath = string.gsub(path, "%.luau$", "")
				local ok, err = pcall(load, modulePath)
				t.ok(ok, `{path}: {tostring(err)}`)
			end
		end)
	end)

	t.describe("authority", function()
		t.it("client->server remotes are exactly the reviewed allowlist", function()
			-- Adding a client->server remote is a security review event:
			-- update this list deliberately with SECURITY_MODEL.md.
			local allowed = {
				ClientReady = true,
				-- Phase 3 review: one-shot, enum + preset id only, ProfileLoaded state,
				-- server validates preset/race pairing (SECURITY_MODEL.md T-30).
				SelectRace = true,
				-- D-72 review: enum only, ProfileLoaded, 2 per 10 s; the server maps
				-- it to fixed official head ids (BodyStyle.HEADS), never client ids.
				SetHeadStyle = true,
				-- D-101: two enums (kind, allowlisted id), ProfileLoaded, 4 then
				-- 1 per 2 s; the server checks the id belongs to the kind.
				SetComplexion = true,
				-- Phase 11 review (D-73): quest id enum only, ProfileLoaded + HasJob;
				-- the server checks reach to its own giver, prerequisites, level and
				-- status, and claims rewards once ("Q:<id>"). No progress remote.
				QuestAccept = true,
				QuestTurnIn = true,
				-- Owned title id or nil; display only.
				EquipTitle = true,
				-- D-74 review: HUD positions only (known ids, 0..1), ProfileLoaded,
				-- 3 per 30 s; sanitized again on the server; affects nothing else.
				SetHudLayout = true,
				-- Phase 4 review: one-shot, job enum only, ProfileLoaded + HasRace
				-- states; job decides skill categories, never stats directly.
				SelectJob = true,
				-- Phase 6 review: intent only (optional target Model); server
				-- validates cooldown, hostility, safe zones, range and LOS.
				BasicAttack = true,
				-- Animation pass review: enum-only intent; the server sets the
				-- speed (validator-safe) and drains Focus for sprint.
				SetMovementMode = true,
				-- Phase 9 review: no arguments; the server looks up the caller's
				-- own rally/run, so nobody can remove another player.
				DungeonLeave = true,
				-- Party review (D-39): Player targets / boolean only; the server
				-- checks leadership, race, size, pending invite and expiry.
				PartyInvite = true,
				PartyRespond = true,
				PartyLeave = true,
				PartyKick = true,
				-- D-48 unions: leaders only, same realm, size and invite checks.
				UnionInvite = true,
				UnionRespond = true,
				UnionLeave = true,
				UnionKick = true,
				-- Phase 5 review: skill id enum + optional target Model hint;
				-- the server checks loadout, ownership, job, level, cooldown,
				-- Focus, stun, hostility / ally rules, range and LOS, and
				-- computes every effect (SECURITY_MODEL T-02/T-03/T-04).
				SkillCast = true,
				-- Phase 5 review: ≤ 6 regular (D-75) + 1 special skill ids (enum);
				-- validated against learned skills, job and slot type.
				SetLoadout = true,
				-- Phase 5 rework (D-45): one skill id (enum); the server checks
				-- job, level, prerequisite, free points and max rank.
				LearnSkill = true,
				-- Phase 5 rework (D-45): no arguments; only in a safe zone and
				-- out of combat; refunds points derived from the level.
				ResetSkills = true,
				-- Phase 7 review (D-64, SECURITY_MODEL T-09 / T-10): item guids
				-- are looked up in the caller's own profile only; slot / boolean
				-- / count / consumable enums otherwise. No client field enters an
				-- item; the server checks job, race weapon family, level, slot,
				-- locks, equipped state, combat state, cooldowns and caps.
				EquipItem = true,
				UnequipItem = true,
				SalvageItems = true,
				LockItem = true,
				CombineFragments = true,
				UseConsumable = true,
				-- No arguments; refused (and security-logged) outside Studio.
				StudioTestGear = true,
				-- Phase 8 review (D-66, SECURITY_MODEL T-11): own item guid +
				-- boolean; the server reads the level from the profile, checks
				-- the +10 cap and stones, consumes one stone, rolls and applies
				-- synchronously (no yield, so requests can't overlap).
				EnhanceItem = true,
				-- Phase 17 review (D-77, SECURITY_MODEL §6, T-19 / T-20): staff
				-- only. Each declares a permission that NetService checks from
				-- the server's Roles on every call (asserted below); handlers
				-- re-check per action / config path, refuse acting on staff of
				-- equal or higher rank, validate every value and audit it.
				AdminPlayers = true,
				AdminInspect = true,
				AdminPlayerAction = true,
				AdminConfigGet = true,
				AdminConfigSet = true,
				AdminBoss = true,
				AdminAudit = true,
				AdminSystemReset = true,
				AdminStaff = true,
				AdminEvents = true,
				SpendAttributes = true,
				ResetAttributes = true,
				BuyMallItem = true,
				-- D-115: the player's own character slots (server validates the slot,
				-- combat state and the typed delete confirmation).
				CharacterSlots = true,
				-- D-116: Race Conversion Rune (rune, combat, realm and the
				-- typed confirmation checked on the server).
				ConvertRace = true,
				-- D-117: Merchant / Exchanger (reach, prices, funds and bag
				-- room checked on the server).
				NpcShop = true,
				-- D-119: the Warden's chain (state and claims on the server).
				ChainQuest = true,
			}
			for name, spec in Registry do
				if spec.direction == "ClientToServer" then
					t.ok(allowed[name], `unreviewed client->server remote '{name}'`)
				end
			end
		end)

		t.it("every admin remote is permission-gated", function()
			local count = 0
			for name, spec in Registry do
				if string.sub(name, 1, 5) == "Admin" and spec.direction == "ClientToServer" then
					count += 1
					t.ok(type(spec.permission) == "string", `{name} has no permission`)
				elseif spec.direction == "ClientToServer" then
					t.ok(spec.permission == nil, `{name}: a permission on a player remote`)
				end
			end
			t.eq(count, 10)
		end)

		t.it("progression services register no remote handlers", function()
			for _, name in
				{
					"LevelService",
					"StatsService",
					"PlayerDataService",
					"SafeZoneService",
					"WorldService",
					"TravelService",
				}
			do
				local source = stripComments(fs.readFile(`{SRC}/server/Services/{name}.luau`))
				t.ok(
					not string.find(source, "NetService:Handle(", 1, true),
					`{name} must not accept client calls`
				)
			end
		end)

		t.it("profile data is only persisted through PersistenceAdapter", function()
			for _, path in listFiles(SRC) do
				local source = stripComments(fs.readFile(path))
				if
					string.find(source, "ProfileStore", 1, true)
					and not string.find(path, "PersistenceAdapter", 1, true)
				then
					t.ok(false, `{path} references ProfileStore directly`)
				end
			end
		end)
	end)
end
