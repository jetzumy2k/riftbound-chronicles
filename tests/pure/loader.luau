--[[
	Roblox-style module loader for Lune.

	Lets pure game modules keep normal Roblox requires
	(`require(script.Parent.X)`, `game:GetService("ReplicatedStorage").Shared...`)
	so luau-lsp type-checks them, while still running under Lune.

	It emulates just enough of the DataModel from the Rojo project layout:
	  ReplicatedStorage.Shared       -> src/shared
	  ServerScriptService.Server     -> src/server

	Only ReplicatedStorage and ServerScriptService exist. A module that touches any
	other service (Players, DataStoreService, ...) fails to load here; that is the
	point: such modules are not pure and must be tested in Studio.

	    local load = require("../loader")
	    local XPTable = load("src/shared/Logic/XPTable")
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ROOTS = {
	{ service = "ReplicatedStorage", name = "Shared", path = "src/shared" },
	{ service = "ServerScriptService", name = "Server", path = "src/server" },
}

-- Lune's fs calls yield, and metamethods cannot yield, so the source tree is
-- indexed into memory once, up front.
local files: { [string]: boolean } = {}
local dirs: { [string]: boolean } = {}
local function indexTree(dir: string)
	dirs[dir] = true
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			indexTree(path)
		else
			files[path] = true
		end
	end
end
for _, root in ROOTS do
	indexTree(root.path)
end

type Node = {
	name: string,
	path: string?, -- filesystem path without extension (nil for game/services)
	parent: any,
	children: { [string]: any }?,
}

local nodeMeta = {}
local cache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

local function newNode(name: string, path: string?, parent: any, children: { [string]: any }?): any
	return setmetatable(
		{ __node = { name = name, path = path, parent = parent, children = children } },
		nodeMeta
	)
end

local function info(proxy: any): Node
	return rawget(proxy, "__node")
end

local function findChild(proxy: any, childName: string): any
	local node = info(proxy)
	if node.children then
		return node.children[childName]
	end
	if node.path == nil then
		return nil
	end
	local base = `{node.path}/{childName}`
	if files[`{base}.luau`] or dirs[base] then
		local cacheKey = `node:{base}`
		local existing = cache[cacheKey]
		if existing == nil then
			existing = newNode(childName, base, proxy, nil)
			cache[cacheKey] = existing
		end
		return existing
	end
	return nil
end

nodeMeta.__index = function(proxy, key)
	local node = info(proxy)
	if key == "Parent" then
		return node.parent
	elseif key == "Name" then
		return node.name
	elseif key == "FindFirstChild" or key == "WaitForChild" then
		return function(self, childName)
			return findChild(self, childName)
		end
	elseif key == "GetService" then
		return function(self, serviceName)
			local service = info(self).children and info(self).children[serviceName]
			if service == nil then
				error(`[loader] service '{serviceName}' is not available to pure modules`, 2)
			end
			return service
		end
	end
	local child = findChild(proxy, key)
	if child == nil then
		error(`[loader] {key} is not a valid member of {node.name}`, 2)
	end
	return child
end

nodeMeta.__tostring = function(proxy)
	return info(proxy).name
end

-- Build game -> services -> roots.
local services: { [string]: any } = {}
local game = newNode("game", nil, nil, services)
for _, root in ROOTS do
	local service = services[root.service]
	if service == nil then
		service = newNode(root.service, nil, game, {})
		services[root.service] = service
	end
	info(service).children[root.name] = newNode(root.name, root.path, service, nil)
end

local requireModule

local function moduleFile(proxy: any): string
	local path = info(proxy).path
	if path == nil then
		error(`[loader] {info(proxy).name} is not a ModuleScript`, 3)
	end
	if files[`{path}.luau`] then
		return `{path}.luau`
	elseif files[`{path}/init.luau`] then
		return `{path}/init.luau`
	end
	error(`[loader] {path} is not a ModuleScript`, 3)
end

function requireModule(proxy: any): any
	if type(proxy) == "string" then
		error("[loader] string requires are not used by game modules", 2)
	end
	local file = moduleFile(proxy)
	local cached = cache[file]
	if cached ~= nil then
		return cached
	end
	if loading[file] then
		error(`[loader] circular require of {file}`, 2)
	end
	loading[file] = true
	local chunk = luau.load(luau.compile(fs.readFile(file)), {
		debugName = file,
		environment = {
			script = proxy,
			game = game,
			require = requireModule,
		},
	})
	local result = chunk()
	loading[file] = nil
	if result == nil then
		error(`[loader] {file} did not return a value`, 2)
	end
	cache[file] = result
	return result
end

-- Resolves "src/shared/Logic/XPTable" to its DataModel node and requires it.
local function load(fsPath: string): any
	for _, root in ROOTS do
		if string.sub(fsPath, 1, #root.path) == root.path then
			local proxy = info(services[root.service]).children[root.name]
			local rest = string.sub(fsPath, #root.path + 2)
			for segment in string.gmatch(rest, "[^/]+") do
				proxy = findChild(proxy, segment)
				if proxy == nil then
					error(`[loader] {fsPath} not found`, 2)
				end
			end
			return requireModule(proxy)
		end
	end
	error(`[loader] {fsPath} is outside the mapped roots`, 2)
end

return load
