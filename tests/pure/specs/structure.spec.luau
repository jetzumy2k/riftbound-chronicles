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
				-- Phase 4 review: one-shot, job enum only, ProfileLoaded + HasRace
				-- states; job decides skill categories, never stats directly.
				SelectJob = true,
			}
			for name, spec in Registry do
				if spec.direction == "ClientToServer" then
					t.ok(allowed[name], `unreviewed client->server remote '{name}'`)
				end
			end
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
