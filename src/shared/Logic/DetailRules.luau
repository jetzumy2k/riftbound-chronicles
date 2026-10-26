--!strict
--[[
	DetailRules — distance-based detail for the Part-built characters
	(Phase 23, PLAN.md D-102). Each anime character is ~250-300 small
	parts (D-100); far away most of them are a pixel or less, so each
	client hides the small ones on other characters by distance
	(CharacterDetailController). The player's own character always keeps
	full detail.

	Every outfit part carries a detail class (attribute RC_Lod, set by the
	builder from its size; HeadBuilder pins the eyes, brows and mouth to 0):
	  0  always shown (body shapes, armour plates, hair volume, eyes)
	  1  fine: under FINE_SIZE studs (gems, trims, eye shines, hair tips)
	  2  medium: under MEDIUM_SIZE studs (small plates, feathers, clumps)
	Levels: 0 full (near), 1 hides class 1 and switches off particles and
	lights, 2 also hides class 2 (far). A margin stops flicker at the
	borders. Pure module, unit-tested (tests/pure/specs/detail_rules.spec).
]]

local DetailRules = {}

DetailRules.FINE_SIZE = 0.35
DetailRules.MEDIUM_SIZE = 0.8
-- Camera distance (studs) where detail drops, and the margin back.
DetailRules.NEAR = 55
DetailRules.FAR = 120
DetailRules.MARGIN = 8

-- The detail class of a part from its largest dimension.
function DetailRules.classOf(largest: number): number
	if largest < DetailRules.FINE_SIZE then
		return 1
	elseif largest < DetailRules.MEDIUM_SIZE then
		return 2
	end
	return 0
end

-- The level for a camera distance, given the current level (hysteresis:
-- a level is left only MARGIN studs past its border).
function DetailRules.level(distance: number, previous: number?): number
	local current = previous or 0
	local m = DetailRules.MARGIN
	if current == 0 then
		if distance > DetailRules.FAR then
			return 2
		end
		return if distance > DetailRules.NEAR then 1 else 0
	elseif current == 1 then
		if distance > DetailRules.FAR then
			return 2
		end
		return if distance < DetailRules.NEAR - m then 0 else 1
	end
	if distance >= DetailRules.FAR - m then
		return 2
	end
	return if distance < DetailRules.NEAR - m then 0 else 1
end

-- Whether a part of `class` is hidden at `level`.
function DetailRules.hidden(class: number, level: number): boolean
	return class > 0 and class <= level
end

-- Particles and lights run only at full detail.
function DetailRules.effectsOn(level: number): boolean
	return level == 0
end

return DetailRules
