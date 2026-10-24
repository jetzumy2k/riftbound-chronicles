--!strict
--[[
	BudgetAudit — measures a built zone against Logic/WorldBudget (Phase 16,
	PLAN.md D-82). Called once per zone after it is built; logs the use of
	every budget field and warns when a field is over.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldBudget = require(ReplicatedStorage.Shared.Logic.WorldBudget)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local log = Log.new("WorldBudget")

local BudgetAudit = {}

function BudgetAudit.measure(model: Instance): WorldBudget.Counts
	local counts = WorldBudget.empty()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			counts.parts += 1
			if d:IsA("MeshPart") then
				counts.meshParts += 1
			end
		elseif d:IsA("Light") then
			counts.lights += 1
			if d.Shadows then
				counts.shadowLights += 1
			end
		elseif d:IsA("ParticleEmitter") then
			counts.emitters += 1
			counts.emitterRate += d.Rate
		end
	end
	counts.emitterRate = math.floor(counts.emitterRate + 0.5)
	return counts
end

function BudgetAudit.report(name: string, kind: string, model: Instance): WorldBudget.Counts
	local counts = BudgetAudit.measure(model)
	log:Info("%s [%s]: %s", name, kind, WorldBudget.summary(kind, counts))
	local over = WorldBudget.over(kind, counts)
	if #over > 0 then
		log:Warn("%s is over its %s budget: %s", name, kind, table.concat(over, ", "))
	end
	return counts
end

return BudgetAudit
