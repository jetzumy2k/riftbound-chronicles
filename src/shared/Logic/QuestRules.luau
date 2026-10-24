--!strict
--[[
	QuestRules — pure quest logic (PLAN.md Phase 11, D-73; DATA_MODEL §2.2).

	Quest state in the profile (QuestState[questId]):
	  Status      "Active" | "ReadyToTurnIn" | "Completed"
	  Objectives  objective id -> count (0..target)
	  Found       interactable id -> true (Interact objectives count each
	              target once)
	  AcceptedAt, CompletedAt (os.time)

	Steps are done in order: an event only advances the first unfinished
	objective (QuestDefinitions). Every function here is deterministic and
	engine-free, so QuestService stays a thin layer of hooks and the rules
	are tested offline.
]]

local QuestDefinitions = require(script.Parent.Parent.Definitions.QuestDefinitions)
local XPTable = require(script.Parent.XPTable)

type Quest = QuestDefinitions.Quest
type Objective = QuestDefinitions.Objective

export type Progress = {
	Status: string,
	Objectives: { [string]: number },
	Found: { [string]: boolean },
	AcceptedAt: number,
	CompletedAt: number?,
}

export type State = { [string]: Progress }

-- What happened in the world (built by QuestService from server events).
export type Event = {
	type: string,
	enemy: string?,
	owner: string?,
	zone: string?,
	target: string?,
	objective: string?,
}

local QuestRules = {}

QuestRules.STATUSES = table.freeze({ "Active", "ReadyToTurnIn", "Completed" })
QuestRules.OBJECTIVE_TYPES =
	table.freeze({ "Visit", "EnterZone", "Kill", "Interact", "ReturnSafely", "ParticipatePvP" })
QuestRules.ITEM_KINDS = table.freeze({ "weapon", "armor", "gear", "necklace", "earrings" })

function QuestRules.status(state: State, questId: string): string?
	local progress = state[questId]
	return if progress then progress.Status else nil
end

function QuestRules.isCompleted(state: State, questId: string): boolean
	return QuestRules.status(state, questId) == "Completed"
end

--[[
	Whether a character may accept `questId`. Reasons: "unknown",
	"accepted" (active, ready or done), "prerequisite", "level".
]]
function QuestRules.canAccept(state: State, questId: string, level: number): (boolean, string?)
	local quest = QuestDefinitions.get(questId)
	if quest == nil then
		return false, "unknown"
	end
	if state[questId] ~= nil then
		return false, "accepted"
	end
	for _, required in quest.prerequisites do
		if not QuestRules.isCompleted(state, required) then
			return false, "prerequisite"
		end
	end
	if level < quest.level then
		return false, "level"
	end
	return true, nil
end

function QuestRules.newProgress(quest: Quest, now: number): Progress
	local objectives = {}
	for _, objective in quest.objectives do
		objectives[objective.id] = 0
	end
	return { Status = "Active", Objectives = objectives, Found = {}, AcceptedAt = now }
end

-- The first unfinished objective (nil once every step is done).
function QuestRules.current(quest: Quest, progress: Progress): (Objective?, number?)
	for index, objective in quest.objectives do
		if (progress.Objectives[objective.id] or 0) < objective.target then
			return objective, index
		end
	end
	return nil, nil
end

-- Whether `event` counts for `objective`.
function QuestRules.matches(objective: Objective, event: Event, progress: Progress): boolean
	if objective.type ~= event.type then
		return false
	end
	local kind = objective.type
	if kind == "Kill" then
		local enemies = objective.enemies or {}
		return event.enemy ~= nil
			and table.find(enemies, event.enemy) ~= nil
			and (objective.owner == nil or objective.owner == event.owner)
	elseif kind == "EnterZone" or kind == "ReturnSafely" then
		return event.zone ~= nil and event.zone == objective.zone
	elseif kind == "Interact" then
		local targets = objective.targets or {}
		return event.target ~= nil
			and table.find(targets, event.target) ~= nil
			and not progress.Found[event.target]
	elseif kind == "Visit" then
		return event.objective == objective.id
	elseif kind == "ParticipatePvP" then
		return true
	end
	return false
end

--[[
	Applies `event` to an active quest: the current objective goes up by
	one if the event counts for it. Returns true if anything changed. When
	the last objective fills, the quest becomes "ReadyToTurnIn".
]]
function QuestRules.advance(quest: Quest, progress: Progress, event: Event): boolean
	if progress.Status ~= "Active" then
		return false
	end
	local objective = QuestRules.current(quest, progress)
	if objective == nil or not QuestRules.matches(objective, event, progress) then
		return false
	end
	if objective.type == "Interact" and event.target then
		progress.Found[event.target] = true
	end
	progress.Objectives[objective.id] =
		math.min(objective.target, (progress.Objectives[objective.id] or 0) + 1)
	if QuestRules.current(quest, progress) == nil then
		progress.Status = "ReadyToTurnIn"
	end
	return true
end

-- Quests a character could be offered now, in story order, and the next
-- one still waiting on a level (for the giver's "come back at level N").
function QuestRules.offers(state: State, level: number): ({ Quest }, Quest?)
	local open, later = {}, nil
	for _, quest in QuestDefinitions.List do
		local ok, reason = QuestRules.canAccept(state, quest.id, level)
		if ok then
			table.insert(open, quest)
		elseif reason == "level" and later == nil then
			later = quest
		end
	end
	return open, later
end

-- EXP for completing `quest` (a share of its level's EXP-to-next).
function QuestRules.xpFor(quest: Quest): number
	return math.floor(XPTable.toNext(quest.level) * quest.rewards.xpShare + 0.5)
end

-- Picks a rarity from weights (sum 100) with `roll` in [0, 1).
function QuestRules.rollRarity(weights: { [string]: number }, roll: number): string
	local names = {}
	for name in weights do
		table.insert(names, name)
	end
	table.sort(names)
	local at = roll * 100
	local last = names[1]
	for _, name in names do
		at -= weights[name]
		last = name
		if at < 0 then
			return name
		end
	end
	return last
end

function QuestRules.hasFlag(data: { [string]: any }, flag: string): boolean
	local flags = data.StoryFlags
	return type(flags) == "table" and flags[flag] == true
end

-- A feature a quest unlocks (D-73): open with the flag, or when the gates
-- are off (Studio unless Quests.GatesInStudio).
function QuestRules.unlocked(data: { [string]: any }, flag: string, gated: boolean): boolean
	return not gated or QuestRules.hasFlag(data, flag)
end

--[[
	Repairs a loaded QuestState in place (DATA_MODEL §3: unknown quests
	dropped, counts clamped). Returns notes.
]]
function QuestRules.repair(state: any): { string }
	local notes = {}
	for questId, progress in state do
		local quest = QuestDefinitions.get(questId)
		if
			quest == nil
			or type(progress) ~= "table"
			or not table.find(QuestRules.STATUSES, progress.Status)
		then
			table.insert(notes, `QuestState: dropped '{tostring(questId)}'`)
			state[questId] = nil
			continue
		end
		local objectives = if type(progress.Objectives) == "table" then progress.Objectives else {}
		local fixed = {}
		for _, objective in quest.objectives do
			local value = objectives[objective.id]
			local count = if type(value) == "number" and value == value then math.floor(value) else 0
			fixed[objective.id] = math.clamp(count, 0, objective.target)
		end
		progress.Objectives = fixed
		local found = {}
		if type(progress.Found) == "table" then
			for target, value in progress.Found do
				if value == true and QuestDefinitions.Interactables[target] then
					found[target] = true
				end
			end
		end
		progress.Found = found
		if type(progress.AcceptedAt) ~= "number" then
			progress.AcceptedAt = 0
		end
		if progress.CompletedAt ~= nil and type(progress.CompletedAt) ~= "number" then
			progress.CompletedAt = nil
		end
		-- Steps and status agree (a definition change can add a step).
		if progress.Status ~= "Completed" then
			local done = QuestRules.current(quest, progress) == nil
			local status = if done then "ReadyToTurnIn" else "Active"
			if status ~= progress.Status then
				table.insert(notes, `QuestState: {questId} {progress.Status} -> {status}`)
				progress.Status = status
			end
		end
	end
	return notes
end

--[[
	Checks the definitions (run by the tests). `enemyExists` and
	`stackableExists` look ids up in the other definition modules.
]]
function QuestRules.validateDefinitions(
	enemyExists: (string) -> boolean,
	stackableExists: (string) -> boolean
): { string }
	local errors = {}
	local function fail(message: string)
		table.insert(errors, message)
	end
	local seen = {}
	for index, quest in QuestDefinitions.List do
		if seen[quest.id] then
			fail(`{quest.id}: duplicate id`)
		end
		seen[quest.id] = true
		if quest.order ~= index then
			fail(`{quest.id}: order {quest.order} at position {index}`)
		end
		for _, required in quest.prerequisites do
			if not seen[required] or required == quest.id then
				fail(`{quest.id}: prerequisite {required} must be an earlier quest`)
			end
		end
		if #quest.objectives == 0 then
			fail(`{quest.id}: no objectives`)
		end
		local objectiveIds = {}
		for _, objective in quest.objectives do
			if objectiveIds[objective.id] then
				fail(`{quest.id}.{objective.id}: duplicate objective`)
			end
			objectiveIds[objective.id] = true
			if not table.find(QuestRules.OBJECTIVE_TYPES, objective.type) then
				fail(`{quest.id}.{objective.id}: unknown type {objective.type}`)
			end
			if objective.target < 1 or objective.target % 1 ~= 0 then
				fail(`{quest.id}.{objective.id}: bad target`)
			end
			if objective.type == "Kill" then
				if objective.enemies == nil or #objective.enemies == 0 then
					fail(`{quest.id}.{objective.id}: no enemies`)
				end
				for _, enemy in (objective.enemies or {}) :: { string } do
					if not enemyExists(enemy) then
						fail(`{quest.id}.{objective.id}: unknown enemy {enemy}`)
					end
				end
			elseif objective.type == "Interact" then
				local targets: { string } = objective.targets or {}
				if #targets ~= objective.target then
					fail(`{quest.id}.{objective.id}: target must equal the number of targets`)
				end
				for _, target in targets do
					if QuestDefinitions.Interactables[target] == nil then
						fail(`{quest.id}.{objective.id}: unknown interactable {target}`)
					end
				end
			elseif objective.type == "Visit" then
				if objective.place == nil then
					fail(`{quest.id}.{objective.id}: Visit needs a place`)
				end
			elseif objective.type == "EnterZone" or objective.type == "ReturnSafely" then
				if objective.zone == nil then
					fail(`{quest.id}.{objective.id}: needs a zone`)
				end
			end
		end
		local rewards = quest.rewards
		if rewards.xpShare < 0 or rewards.xpShare > 2 then
			fail(`{quest.id}: xpShare out of range`)
		end
		for _, item in (rewards.items or {}) :: { QuestDefinitions.ItemReward } do
			if not table.find(QuestRules.ITEM_KINDS, item.kind) then
				fail(`{quest.id}: unknown item kind {item.kind}`)
			end
			local sum = 0
			for _, weight in item.rarity do
				sum += weight
			end
			if sum ~= 100 then
				fail(`{quest.id}: rarity weights sum to {sum}`)
			end
		end
		for id in (rewards.stackables or {}) :: { [string]: number } do
			if not stackableExists(id) then
				fail(`{quest.id}: unknown stackable {id}`)
			end
		end
		for _, title in (rewards.titles or {}) :: { string } do
			if QuestDefinitions.Titles[title] == nil then
				fail(`{quest.id}: unknown title {title}`)
			end
		end
		for _, cosmetic in (rewards.cosmetics or {}) :: { string } do
			if QuestDefinitions.Cosmetics[cosmetic] == nil then
				fail(`{quest.id}: unknown cosmetic {cosmetic}`)
			end
		end
		for _, flag in (rewards.flags or {}) :: { string } do
			if not table.find(QuestDefinitions.FLAGS, flag) then
				fail(`{quest.id}: unknown flag {flag}`)
			end
		end
	end
	return errors
end

return table.freeze(QuestRules)
