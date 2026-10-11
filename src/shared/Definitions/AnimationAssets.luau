--!strict
--[[
	AnimationAssets — published Roblox animation ids for AnimationClips
	(PLAN.md D-36).

	Roblox only plays animations owned by the experience's owner. Until a
	clip is published, the client builds it from AnimationClips and registers
	it for play-testing in Studio. Before release the creator publishes each
	clip once (docs/ASSET_GUIDE.md, "Publishing animations") and pastes the
	ids here, keyed by asset name ("Warrior_Attack1", "Warrior_Attack1_Upper").

	Pure module.
]]

return table.freeze({} :: { [string]: string })
