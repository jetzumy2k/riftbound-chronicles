local load = require("../loader")
local Complexion = load("src/shared/Definitions/Complexion")
local Enums = load("src/shared/Enums")

local function valid(rgb)
	if #rgb ~= 3 then
		return false
	end
	for _, channel in rgb do
		if channel < 0 or channel > 255 or channel % 1 ~= 0 then
			return false
		end
	end
	return true
end

return function(t)
	t.describe("Complexion", function()
		t.it("every colour is valid and ids are unique per kind", function()
			local seen = {}
			for _, skin in Complexion.SKINS do
				t.ok(valid(skin.rgb), `{skin.id} rgb`)
				t.ok(not seen["S" .. skin.id], `{skin.id} unique`)
				seen["S" .. skin.id] = true
			end
			for _, hair in Complexion.HAIRS do
				t.ok(valid(hair.rgb) and valid(hair.tip), `{hair.id} rgb`)
				t.ok(not seen["H" .. hair.id], `{hair.id} unique`)
				seen["H" .. hair.id] = true
			end
		end)
		t.it("realm defaults are human tones, not white (creator review 2026-10-26)", function()
			for _, race in Enums.Race do
				local skin = Complexion.skin(race, Complexion.DEFAULT)
				local hair = Complexion.hair(race, Complexion.DEFAULT)
				t.ok(skin.rgb[3] < 160, `{race} skin is not pale white`)
				t.ok(hair.rgb[1] < 230 and hair.rgb[3] < 200, `{race} hair is not white`)
			end
			t.eq(Complexion.hair("Devil", nil).id, "Black")
		end)
		t.it("only allowlisted ids of the right kind are valid", function()
			t.ok(Complexion.isValid("Skin", "Default"))
			t.ok(Complexion.isValid("Skin", "Deep"))
			t.ok(Complexion.isValid("Hair", "Crimson"))
			t.ok(not Complexion.isValid("Skin", "Crimson"))
			t.ok(not Complexion.isValid("Hair", "Deep"))
			t.ok(not Complexion.isValid("Eyes", "Default"))
			t.ok(not Complexion.isValid("Hair", "rgb(255,255,255)"))
			for _, id in Complexion.SKIN_IDS do
				t.ok(table.find(Complexion.ALL_IDS, id) ~= nil, `{id} in the remote enum`)
			end
			for _, id in Complexion.HAIR_IDS do
				t.ok(table.find(Complexion.ALL_IDS, id) ~= nil, `{id} in the remote enum`)
			end
		end)
		t.it("cycling wraps both ways and an unknown id falls back to the realm", function()
			t.eq(Complexion.cycle("Skin", "Default", 1), Complexion.SKINS[1].id)
			t.eq(Complexion.cycle("Skin", "Default", -1), Complexion.SKINS[#Complexion.SKINS].id)
			t.eq(Complexion.cycle("Hair", Complexion.HAIRS[#Complexion.HAIRS].id, 1), "Default")
			t.eq(Complexion.skin("Angel", "nope").id, Complexion.REALM_DEFAULTS.Angel.skin)
		end)
	end)
end
