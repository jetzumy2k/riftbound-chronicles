--!strict
--[[
	ComplexionPicker — two buttons that pick the anime look's skin tone and
	hair colour (PLAN.md D-101): "Skin" and "Hair", each with a colour dot
	and the colour's name. Tap (or click) = the next colour, right-click =
	the previous; the list starts with the realm's default. 44 px tall
	(touch target).

	Taps show the colour at once and are sent as one request after a short
	pause (SetComplexion: an allowlisted id; the server checks it and
	rebuilds the look), so cycling through colours doesn't flood the
	server. Display only otherwise.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Complexion = require(Shared.Definitions.Complexion)
local NetClient = require(Shared.Net.Client)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Tooltip = require(script.Parent.Tooltip)

local ComplexionPicker = {}

ComplexionPicker.HEIGHT = 44
local SEND_DELAY = 0.6

type State = { Race: string?, SkinTone: string, HairColor: string }

--[[
	Builds the picker into `parent` (`width` scale + offset, 44 tall). `getState`
	returns the player's data; `changed` fires when it changes; `race`
	(optional) is the realm to show defaults for (the realm screen's
	selection), else the player's realm.
]]
function ComplexionPicker.build(
	parent: Instance,
	width: UDim,
	zIndex: number,
	getState: () -> State,
	changed: any,
	race: (() -> string?)?
): Frame
	local frame = Kit.new("Frame", {
		Name = "ComplexionPicker",
		BackgroundTransparency = 1,
		Size = UDim2.new(width.Scale, width.Offset, 0, ComplexionPicker.HEIGHT),
		ZIndex = zIndex,
		Parent = parent,
	})
	Kit.list(frame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	local pending: { [string]: string } = {}
	local tokens: { [string]: number } = {}
	local painters: { () -> () } = {}

	local function realm(): string?
		return (race and race()) or getState().Race
	end

	for index, kind in Complexion.KINDS do
		local field = if kind == "Skin" then "SkinTone" else "HairColor"
		local function current(): string
			return pending[kind] or (getState() :: any)[field] or Complexion.DEFAULT
		end
		local button = Kit.new("TextButton", {
			Name = kind,
			LayoutOrder = index,
			Size = UDim2.new(0.5, -3, 1, 0),
			BackgroundColor3 = Theme.Colors.GlassRaised,
			BackgroundTransparency = 0.15,
			Text = "",
			AutoButtonColor = true,
			ZIndex = zIndex + 1,
			Parent = frame,
		})
		Kit.corner(button, 10)
		local dot = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
			Parent = button,
		})
		Kit.corner(dot, 11)
		Kit.new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.4, Parent = dot })
		local label = Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -40, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			TextWrapped = true,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.Text,
			ZIndex = zIndex + 2,
			Parent = button,
		})
		local function paint()
			local id = current()
			local rgb, name
			if kind == "Skin" then
				local skin = Complexion.skin(realm(), id)
				rgb, name = skin.rgb, skin.name
			else
				local hair = Complexion.hair(realm(), id)
				rgb, name = hair.rgb, hair.name
			end
			dot.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
			label.Text = if id == Complexion.DEFAULT then `{kind}: default` else `{kind}: {name}`
		end
		table.insert(painters, paint)
		local function step(by: number)
			local id = Complexion.cycle(kind, current(), by)
			pending[kind] = id
			paint()
			local token = (tokens[kind] or 0) + 1
			tokens[kind] = token
			task.delay(SEND_DELAY, function()
				if tokens[kind] ~= token then
					return
				end
				if (getState() :: any)[field] ~= id then
					NetClient.fire("SetComplexion", kind, id)
				end
				-- Keep showing it until the server's snapshot arrives.
				task.delay(2, function()
					if tokens[kind] == token then
						pending[kind] = nil
						paint()
					end
				end)
			end)
		end
		button.Activated:Connect(function()
			step(1)
		end)
		button.MouseButton2Click:Connect(function()
			step(-1)
		end)
		Tooltip.attach(button, function()
			return `{kind} colour`, "Tap for the next colour (right-click: previous)."
		end, "hold")
	end

	local function paintAll()
		for _, paint in painters do
			paint()
		end
	end
	paintAll()
	local connection = changed:Connect(paintAll)
	frame.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return frame
end

return ComplexionPicker
