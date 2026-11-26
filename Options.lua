local _, Merlin = ...
local UI, T = Merlin.UI, Merlin.UI.T

UI.Configure({
	isRestricted = Merlin.IsRestricted,
	guardWrites = true,
	getPriestAccent = function()
		return Merlin.db and Merlin.db.colors and Merlin.db.colors.priestAccent
	end,
})

local CreateButton, CreateGlyph = UI.button, UI.Glyph
local Text, Fill, OpenMenu = UI.text, UI.fill, UI.OpenMenu
local CreateArmedButton, ApplyAccentColor = UI.armedButton, UI.ApplyAccent
local WIDTH, HEIGHT = 544, 550
local NAV_W, NAV_COLLAPSED = 104, 40
local PAD = 12
local COL_GAP = 16
local COL_W = math.floor((WIDTH - NAV_W - PAD * 2 - COL_GAP) / 2)
local PREVIEW_H = 70
local WHITE = "Interface\\Buttons\\WHITE8X8"

local shell
local pageRefreshFns = {}
local buildingPageKey
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function RegisterRefreshFn(fn)
	local list = pageRefreshFns[buildingPageKey]
	if not list then
		list = {}
		pageRefreshFns[buildingPageKey] = list
	end
	list[#list + 1] = fn
end

local function RefreshPage(key)
	local list = key and pageRefreshFns[key]
	if not (list) then
		return
	end
	for _, fn in ipairs(list) do
		fn()
	end
end

local function SafeSetFont(fs, font, size, outline)
	if not fs:SetFont(font, size, outline) then
		fs:SetFont(DEFAULT_FONT, size, outline)
	end
end

local colorRefreshPending = false
local function QueueColorRefresh()
	if colorRefreshPending then
		return
	end
	colorRefreshPending = true
	C_Timer.After(0.06, function()
		colorRefreshPending = false
		Merlin.RequestRefresh()
	end)
end

local function ShowStatus(message)
	shell:Status(message)
end

local function ApplyWindowOpacity()
	shell:ApplyOpacity()
end

local function PlaceRow(row, y, advance)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	RegisterRefreshFn(row.Refresh)
	return y - advance
end

local function RequestingSetter(set, skipRefresh)
	return function(value)
		set(value)
		if not skipRefresh then
			Merlin.RequestRefresh()
		end
	end
end

local function CreateSection(parent, y, label, onReset)
	local row = UI.heading(parent, label, {
		onReset = onReset and function()
			onReset()
			Merlin.RequestRefresh()
			RefreshPage(shell.activePage)
			ShowStatus(label .. " reset to defaults.")
		end,
	})
	return PlaceRow(row, y, 22)
end

local function CreateCheckRow(parent, y, label, get, set, disabled)
	return PlaceRow(UI.checkRow(parent, label, get, RequestingSetter(set), { disabled = disabled }), y, 23)
end

local function CreateCheckPairRow(parent, y, labelA, getA, setA, labelB, getB, setB, splitX, disabledA, disabledB)
	local row = UI.checkPairRow(parent, labelA, getA, RequestingSetter(setA), labelB, getB, RequestingSetter(setB), {
		split = (splitX or 112) / COL_W, disabledA = disabledA, disabledB = disabledB,
	})
	return PlaceRow(row, y, 23)
end

local function CreatePairRow(parent, y, label, min, max, getX, setX, getY, setY, disabled)
	local row = UI.pairRow(parent, label, min, max, getX, RequestingSetter(setX), getY, RequestingSetter(setY), {
		disabled = disabled, step = 1,
	})
	return PlaceRow(row, y, 24)
end

local function CreateSliderRow(parent, y, label, min, max, step, get, set, format, opts)
	if type(format) == "table" then
		opts, format = format, nil
	end
	opts = opts or {}
	local check = opts.check and { get = opts.check.get, set = RequestingSetter(opts.check.set, opts.noRefresh) }
	local row = UI.slider(parent, label, min, max, step, get, RequestingSetter(set, opts.noRefresh), format, COL_W, {
		editable = true, isPercent = opts.isPercent, disabled = opts.disabledFn, check = check, tip = opts.tip,
	})
	return PlaceRow(UI.compact(row), y, 24)
end

local function CreateChoiceRow(parent, y, label, options, get, set, opts)
	opts = type(opts) == "number" and { ctrlW = opts } or opts or {}
	local row = UI.choice(parent, label, options, get, RequestingSetter(set, opts.noRefresh),
		COL_W, nil, nil, { disabled = opts.disabledFn })
	if opts.ctrlW then
		row.labelWidth = COL_W - opts.ctrlW - 4
	end
	return PlaceRow(UI.compact(row), y, 24)
end

local function CreateColorRow(parent, y, label, get, set)
	local row = UI.colorRow(parent, label, get, function(r, g, b)
		if not UI.WritesBlocked() then
			set(r, g, b)
			QueueColorRefresh()
		end
	end, { withAlpha = false, height = 21, tip = "Click to set color." })
	return PlaceRow(row, y, 22)
end

-- Option tables

local ORIENTATION_OPTS = {
	{ label = "Horizontal", store = "HORIZONTAL" },
	{ label = "Vertical", store = "VERTICAL" },
}
local GROWTH_X_OPTS = {
	{ label = "Left", store = "LEFT" },
	{ label = "Right", store = "RIGHT" },
}
local GROWTH_Y_OPTS = {
	{ label = "Down", store = "DOWN" },
	{ label = "Up", store = "UP" },
}
local SORT_METHOD_OPTS = {
	{ label = "Default", store = "DEFAULT" },
	{ label = "Duration", store = "EXPIRATION" },
	{ label = "Name", store = "NAME" },
	{ label = "Index", store = "INDEX" },
}
local SORT_DIR_OPTS = {
	{ label = "Normal", store = "NORMAL" },
	{ label = "Reverse", store = "REVERSE" },
}
local ENCHANT_PLACE_OPTS = {
	{ label = "Before", store = "BEFORE" },
	{ label = "After", store = "AFTER" },
}
local DURATION_FMT_OPTS = {
	{
		label = "Smart",
		store = "SMART",
		tip = "2h  |  12m  |  4:15  |  28\nm:ss under 5m, bare seconds under 1m.",
	},
	{
		label = "Compact",
		store = "COMPACT",
		tip = "2h  |  12m  |  28s\nSingle unit with s suffix, no m:ss.",
	},
	{
		label = "Detailed",
		store = "DETAILED",
		tip = "1h 59m  |  12m  |  4:15  |  28\nHours and minutes over 1h (Raven / Bufflehead style).",
	},
	{
		label = "Clock",
		store = "CLOCK",
		tip = "1:59  |  12:30  |  4:15  |  28\nH:MM over 1h, M:SS under 1h.",
	},
	{
		label = "Decimal",
		store = "DECIMAL",
		tip = "2.0h  |  1.5h  |  12m  |  4:15  |  28\nTenths of an hour over 1h.",
	},
	{
		label = "Blizzard",
		store = "BLIZZARD",
		tip = "2 h  |  12 m  |  28 s\nStock Blizzard client timer formatting.",
	},
}
local DURATION_ROUND_OPTS = {
	{
		label = "Nearest",
		store = "NEAREST",
		tip = "OmniCC / NDui style.\n2h (1h30m-2h) -> 1h (59m30s-1h29m) -> 59m..1m -> 59..1",
	},
	{
		label = "Ceiling (90m)",
		store = "CEIL90",
		tip = "Ellesmere / BuffFrame style.\n2h (1h30m-2h) -> 90m..2m -> 89..1 (no 1h band)",
	},
	{
		label = "Round up",
		store = "UP",
		tip = "Standard ceiling at 60m / 60s.\n2h (1h01m-2h) -> 60m..1m -> 60..1",
	},
}
local DURATION_ANCHOR_OPTS = {
	{ label = "Below", store = "BELOW" },
	{ label = "In bottom", store = "BOTTOM" },
	{ label = "Center", store = "CENTER" },
	{ label = "In top", store = "TOP" },
	{ label = "Above", store = "ABOVE" },
}
local COUNT_ANCHOR_OPTS = {
	{ label = "Top right", store = "TOPRIGHT" },
	{ label = "Bot right", store = "BOTTOMRIGHT" },
	{ label = "Top left", store = "TOPLEFT" },
	{ label = "Bot left", store = "BOTTOMLEFT" },
	{ label = "Center", store = "CENTER" },
}
local DISPEL_ICON_STYLE_OPTS = {
	{ label = "Diamond", store = "DIAMOND", tip = "Small diamond tinted with your dispel colors." },
	{ label = "Blizzard", store = "BLIZZARD", tip = "Blizzard's dispel type icons." },
}

local CORNER_OPTS = {
	{ label = "Top left", store = "TOPLEFT" },
	{ label = "Top right", store = "TOPRIGHT" },
	{ label = "Bot left", store = "BOTTOMLEFT" },
	{ label = "Bot right", store = "BOTTOMRIGHT" },
}

local OUTLINE_OPTS = {
	{ label = "None", store = "" },
	{ label = "Outline", store = "OUTLINE" },
	{ label = "Thick", store = "THICKOUTLINE" },
}
local TOOLTIP_ANCHOR_OPTS = {
	{ label = "Bottom left", store = "ANCHOR_BOTTOMLEFT" },
	{ label = "Top left", store = "ANCHOR_TOPLEFT" },
	{ label = "Bottom right", store = "ANCHOR_BOTTOMRIGHT" },
	{ label = "Cursor", store = "ANCHOR_CURSOR" },
}
local ANCHOR_OPTS_BUFF = {
	{ label = "Screen", store = "SCREEN" },
	{ label = "Minimap", store = "MINIMAP" },
}
local ANCHOR_OPTS_OTHER = {
	{ label = "Screen", store = "SCREEN" },
	{ label = "Minimap", store = "MINIMAP" },
	{ label = "Buffs", store = "BUFFS" },
}
local ENCHANT_SLOT_OPTS = {
	{ label = "Main Hand", store = "mh" },
	{ label = "Off Hand", store = "oh" },
	{ label = "Ranged", store = "ranged" },
}
local selectedEnchantSlot = "mh"

local function ApplyAnchorPreset(cfgKey, newAnchor)
	local cfg = Merlin.db[cfgKey]
	if cfg.anchorTo == newAnchor then
		return
	end
	cfg.anchorTo = newAnchor
	if newAnchor == "MINIMAP" then
		cfg.x = -12
		cfg.y = 0
		if cfg.slots then
			cfg.slots.mh.x, cfg.slots.mh.y = -12, 0
			cfg.slots.oh.x, cfg.slots.oh.y = -72, 0
			cfg.slots.ranged.x, cfg.slots.ranged.y = -132, 0
		end
	elseif newAnchor == "BUFFS" then
		cfg.x = 0
		cfg.y = -16
		if cfg.slots then
			cfg.slots.mh.x, cfg.slots.mh.y = 0, -16
			cfg.slots.oh.x, cfg.slots.oh.y = -60, -16
			cfg.slots.ranged.x, cfg.slots.ranged.y = -120, -16
		end
	else
		local def = Merlin.defaults[cfgKey]
		cfg.x = def.x
		cfg.y = def.y
		if cfg.slots and def.slots then
			for slotKey, slotDef in pairs(def.slots) do
				cfg.slots[slotKey].x = slotDef.x
				cfg.slots[slotKey].y = slotDef.y
			end
		end
	end
	RefreshPage(cfgKey)
end

-- Live preview strip inside each group page

local function Sample(icon, texts, tier, borderKey, stacks, dur, rem, isEnchant, dec)
	return {
		icon = "Interface\\Icons\\" .. icon,
		texts = texts,
		tier = tier,
		borderKey = borderKey,
		stacks = stacks,
		dur = dur,
		rem = rem,
		isEnchant = isEnchant,
		dec = dec,
	}
end

local function DurTexts(smart, compact, detailed, clock, decimal, blizz)
	return {
		SMART = smart,
		COMPACT = compact,
		DETAILED = detailed or smart,
		CLOCK = clock or smart,
		DECIMAL = decimal or smart,
		BLIZZARD = blizz,
	}
end

local PREVIEW_ITEMS = {
	buffs = {
		Sample("Spell_Holy_WordFortitude", DurTexts("2h", "2h", "1h 59m", "1:59", "2.0h", "2 h"), "normal", "buffBorder", nil, 60, 45),
		Sample("Spell_Nature_Regeneration", DurTexts("28", "28s", "28", "28", "28", "28 s"), "warn", "buffBorder", nil, 60, 28),
		Sample("Spell_Holy_PowerWordShield", DurTexts("4", "4s", "4", "4", "4", "4 s"), "urgent", "buffBorder", nil, 30, 4, false, true),
		Sample("Spell_Arcane_Arcane01", DurTexts("4:15", "4m", "4:15", "4:15", "4:15", "4 m"), "normal", "buffBorder", "3", 60, 36),
		Sample("Spell_Nature_Swiftness", nil, nil, "buffBorder"),
		Sample("Ability_Poisons", DurTexts("24m", "24m", "24m", "24:00", "24m", "24 m"), "normal", "enchantBorder", "45", 60, 48, true),
	},
	debuffs = {
		Sample("Ability_Gouge", DurTexts("18", "18s", "18", "18", "18", "18 s"), "warn", "dispelNone", "2", 30, 18),
		Sample("Spell_Shadow_ShadowWordPain", DurTexts("4", "4s", "4", "4", "4", "4 s"), "urgent", "dispelMagic", nil, 30, 4, false, true),
		Sample("Spell_Shadow_CurseOfSargeras", DurTexts("1:45", "2m", "1:45", "1:45", "1:45", "2 m"), "normal", "dispelCurse", nil, 60, 42),
		Sample("Ability_Creature_Poison_02", DurTexts("12", "12s", "12", "12", "12", "12 s"), "warn", "dispelPoison", "5", 30, 12),
		Sample("Spell_Nature_NullifyDisease", DurTexts("2m", "2m", "2m", "2:00", "2m", "2 m"), "normal", "dispelDisease", nil, 60, 40),
		Sample("Ability_Warrior_Riposte", DurTexts("8", "8s", "8", "8", "8", "8 s"), "warn", "dispelBleed", "3", 30, 8),
	},
	externals = {
		Sample("Spell_Holy_SealOfProtection", DurTexts("8", "8s", "8", "8", "8", "8 s"), "warn", "externalBorder", nil, 12, 8),
		Sample("Spell_Nature_StoneClawTotem", DurTexts("3", "3s", "3", "3", "3", "3 s"), "urgent", "externalBorder", nil, 12, 3, false, true),
		Sample("Spell_Holy_DivineIntervention", DurTexts("12", "12s", "12", "12", "12", "12 s"), "warn", "externalBorder", "2", 20, 12),
	},
	enchants = {
		Sample("Ability_Poisons", DurTexts("28m", "28m", "28m", "28:00", "28m", "28 m"), "normal", "enchantBorder", "45", 60, 48),
		Sample("Ability_Rogue_DualWeild", DurTexts("12m", "12m", "12m", "12:00", "12m", "12 m"), "normal", "enchantBorder", "20", 60, 24),
		Sample("INV_Ammo_Arrow_02", DurTexts("4", "4s", "4", "4", "4", "4 s"), "urgent", "enchantBorder", nil, 30, 4, false, true),
	},
}

local function CreatePreviewIcon(parent)
	local f = CreateFrame("Frame", nil, parent)
	local icon = f:CreateTexture(nil, "BORDER")
	icon:SetAllPoints()
	f.icon = icon

	local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetHideCountdownNumbers(true)
	f.cooldown = cd

	-- Same border renderer as live icons (texture, size, inset, opacity)
	local border = Merlin.CreateIconBorder(f, cd:GetFrameLevel() + 1, 1, 1, 1, 1)
	f.borderFrame = border

	local textHost = CreateFrame("Frame", nil, f)
	textHost:SetAllPoints()
	textHost:SetFrameLevel(border:GetFrameLevel() + 1)

	f.duration = textHost:CreateFontString(nil, "OVERLAY")
	f.duration:SetWordWrap(false)

	f.count = textHost:CreateFontString(nil, "OVERLAY")
	f.count:SetWordWrap(false)
	f.count:SetTextColor(1, 0.92, 0.3, 1)

	local badge = textHost:CreateTexture(nil, "OVERLAY", nil, 2)
	badge:SetSize(7, 7)
	badge:SetTexture(WHITE)
	badge:SetRotation(math.rad(45))
	badge:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
	badge:Hide()
	f.dispelBadge = badge

	return f
end

local function CreatePreviewStrip(parent, cfgKey)
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetPoint("TOPLEFT", PAD, -34)
	strip:SetPoint("TOPRIGHT", -PAD, -34)
	strip:SetHeight(PREVIEW_H)
	Fill(strip, T.band)

	local slots = {}
	local active = {}
	local items = PREVIEW_ITEMS[cfgKey] or {}
	for i = 1, #items do
		slots[i] = CreatePreviewIcon(strip)
	end

	local function Refresh()
		local cfg = (cfgKey == "enchants") and Merlin.GetEnchantStyleConfig() or Merlin.db[cfgKey]
		local db = Merlin.db
		local font = Merlin.GetFontPath(cfg.fontName)
		local outline = cfg.fontOutline
		local px = Merlin.GetPixelSize(strip)
		local size = math.min(cfg.size, 36)
		local stripW = WIDTH - NAV_W - PAD * 2

		for i = #active, 1, -1 do
			active[i] = nil
		end
		local enchantItem
		for _, item in ipairs(items) do
			if item.isEnchant then
				if db.enchants.showWeaponEnchants and not db.enchants.detachEnchants then
					enchantItem = item
				end
			else
				active[#active + 1] = item
			end
		end
		if enchantItem then
			if db.enchants.enchantPlacement == "BEFORE" then
				table.insert(active, 1, enchantItem)
			else
				active[#active + 1] = enchantItem
			end
		end

		local n = #active
		local maxGap = n > 1 and math.floor((stripW - 16 - n * size) / (n - 1)) or 0
		local gap = math.max(2, math.min(cfg.spacingX, maxGap))
		local totalW = n * size + math.max(0, n - 1) * gap
		local startX = math.floor((stripW - totalW) / 2)
		local yOff = (cfg.durationAnchor == "BELOW") and 6 or (cfg.durationAnchor == "ABOVE" and -6 or 0)
		local now = GetTime()
		local uCol = db.colors.timerUrgent
		local wCol = db.colors.timerWarn

		for i = 1, #slots do
			local slot = slots[i]
			local data = active[i]
			if data then
				slot:SetSize(size, size)
				slot:ClearAllPoints()
				slot:SetPoint("LEFT", strip, "LEFT", startX + (i - 1) * (size + gap), yOff)
				slot.icon:SetTexture(data.icon)
				Merlin.ApplyIconTexCoord(slot.icon)

				local bCol = type(data.borderKey) == "string" and db.colors[data.borderKey] or data.borderKey
				Merlin.UpdateIconBorder(slot.borderFrame, bCol, px, size, size)

				local dispelType = type(data.borderKey) == "string" and data.borderKey:match("^dispel(%u%l+)$")
				local atlas = dispelType and Merlin.DISPEL_ATLAS and Merlin.DISPEL_ATLAS[dispelType]
				if cfgKey == "debuffs" and cfg.showDispelIcon and i > 1 then
					local badge = slot.dispelBadge
					-- Scale with the preview icon (capped at 36px) like the live badge.
					local scale = size / cfg.size
					local badgeCfg = {
						dispelIconAnchor = cfg.dispelIconAnchor,
						dispelIconSize = math.max(4, math.floor(cfg.dispelIconSize * scale + 0.5)),
					}
					if cfg.dispelIconStyle == "BLIZZARD" and atlas then
						badge:SetRotation(0)
						badge:SetAtlas(atlas)
						badge:SetVertexColor(1, 1, 1, 1)
					else
						badgeCfg.dispelIconSize = math.max(4, math.floor(badgeCfg.dispelIconSize / 2 + 0.5))
						badge:SetTexture(WHITE)
						badge:SetTexCoord(0, 1, 0, 1)
						badge:SetRotation(math.rad(45))
						badge:SetVertexColor(bCol[1], bCol[2], bCol[3], 1)
					end
					Merlin.PositionDispelBadge(badge, slot, badgeCfg)
					badge:Show()
				else
					slot.dispelBadge:Hide()
				end

				if cfg.showCooldownSwipe and data.dur and data.rem then
					slot.cooldown:SetDrawSwipe(true)
					slot.cooldown:SetReverse(cfg.reverseCooldownSwipe)
					slot.cooldown:SetCooldown(now - (data.dur - data.rem), data.dur)
					if slot.cooldown.Pause then
						slot.cooldown:Pause()
					end
					slot.cooldown:Show()
				else
					slot.cooldown:Clear()
					slot.cooldown:Hide()
				end

				if cfg.showDuration and data.texts then
					local txt = data.texts[cfg.durationFormat] or data.texts.SMART
					if data.dec and cfg.showDecimals and cfg.durationFormat ~= "BLIZZARD" then
						txt = (cfg.durationFormat == "COMPACT") and (data.texts.SMART .. ".2s")
							or (data.texts.SMART .. ".2")
					end
					SafeSetFont(slot.duration, font, cfg.durationFontSize, outline)
					Merlin.PositionDurationText(slot.duration, slot, cfg)
					slot.duration:SetText(txt)
					if cfg.colorDurationByTime then
						if data.tier == "urgent" then
							slot.duration:SetTextColor(uCol[1], uCol[2], uCol[3], 1)
						elseif data.tier == "warn" then
							slot.duration:SetTextColor(wCol[1], wCol[2], wCol[3], 1)
						else
							slot.duration:SetTextColor(1.0, 1.0, 1.0, 1)
						end
					else
						slot.duration:SetTextColor(1.0, 1.0, 1.0, 1)
					end
					slot.duration:Show()
				else
					slot.duration:Hide()
				end

				if cfg.showCount and data.stacks then
					SafeSetFont(slot.count, font, cfg.countFontSize, outline)
					Merlin.PositionCountText(slot.count, slot, cfg)
					slot.count:SetText(data.stacks)
					slot.count:Show()
				else
					slot.count:Hide()
				end

				slot:Show()
			else
				slot:Hide()
			end
		end
	end

	RegisterRefreshFn(Refresh)
	return strip
end

-- Single 2-column group page: Preview strip + Left (Layout & Position) + Right (Display & Text)

local function BuildGroupPage(main, cfgKey, titleText, isBuff)
	buildingPageKey = cfgKey
	local page = CreateFrame("Frame", nil, main)
	page:SetAllPoints(main)
	page:Hide()

	local isEnchants = (cfgKey == "enchants")
	local enchOff = isEnchants and function()
		return not Merlin.db.enchants.showWeaponEnchants
	end or nil
	local styleOff = isEnchants and function()
		return not Merlin.db.enchants.showWeaponEnchants or Merlin.db.enchants.followBuffsStyle
	end or nil
	local detachedOff = isEnchants and function()
		return not Merlin.db.enchants.showWeaponEnchants or not Merlin.db.enchants.detachEnchants
	end or nil
	local groupedOff = isEnchants and function()
		return not Merlin.db.enchants.showWeaponEnchants
			or not Merlin.db.enchants.detachEnchants
			or not Merlin.db.enchants.grouped
	end or nil
	local soloOff = isEnchants and function()
		return not Merlin.db.enchants.showWeaponEnchants
			or not Merlin.db.enchants.detachEnchants
			or Merlin.db.enchants.grouped
	end or nil
	local attachedOff = isEnchants and function()
		return not Merlin.db.enchants.showWeaponEnchants or Merlin.db.enchants.detachEnchants
	end or nil
	local spacingOff = isEnchants and function()
		return styleOff() or (Merlin.db.enchants.detachEnchants and not Merlin.db.enchants.grouped)
	end or nil

	local header = Text(page, titleText, "GameFontHighlightLarge", T.text)
	header:SetPoint("TOPLEFT", PAD, -11)

	CreatePreviewStrip(page, cfgKey)

	local topY = -(34 + PREVIEW_H + 10)
	local leftCol = CreateFrame("Frame", nil, page)
	leftCol:SetPoint("TOPLEFT", PAD, topY)
	leftCol:SetPoint("BOTTOMLEFT", PAD, PAD)
	leftCol:SetWidth(COL_W)

	local divider = Fill(page, T.band)
	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", math.floor(COL_GAP / 2), 0)
	divider:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", math.floor(COL_GAP / 2), 6)
	divider:SetWidth(1)

	local rightCol = CreateFrame("Frame", nil, page)
	rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", COL_GAP, 0)
	rightCol:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	-- Left column: Layout & Position
	local function ResetKeys(keys)
		local dst = Merlin.db[cfgKey]
		local def = Merlin.defaults[cfgKey]
		for _, k in ipairs(keys) do
			if def[k] ~= nil then
				dst[k] = def[k]
			end
		end
	end

	local ly = 0
	ly = CreateSection(leftCol, ly, "Layout", function()
		ResetKeys({
			"size", "perRow", "maxIcons", "spacingX", "spacingY",
			"orientation", "growthX", "growthY", "sortMethod", "sortDirection",
		})
	end)
	if cfgKey == "enchants" then
		ly = CreateCheckRow(leftCol, ly, "Show enchants",
			function() return Merlin.db.enchants.showWeaponEnchants end,
			function(v)
				Merlin.db.enchants.showWeaponEnchants = v
				RefreshPage("enchants")
			end
		)
		ly = CreateCheckRow(leftCol, ly, "Detach from Buffs",
			function() return Merlin.db.enchants.detachEnchants end,
			function(v)
				Merlin.db.enchants.detachEnchants = v
				if v then
					Merlin.db.enchants.showWeaponEnchants = true
				end
				RefreshPage("enchants")
			end,
			enchOff
		)
		ly = CreateCheckRow(leftCol, ly, "Group slots",
			function() return Merlin.db.enchants.grouped end,
			function(v)
				Merlin.db.enchants.grouped = v
				RefreshPage("enchants")
			end,
			detachedOff
		)
	else
		ly = CreateCheckRow(leftCol, ly, "Enable " .. titleText:lower(),
			function() return Merlin.db[cfgKey].enabled end,
			function(v) Merlin.db[cfgKey].enabled = v end
		)
	end
	ly = CreateSliderRow(leftCol, ly, "Icon size", 18, 64, 1,
		function() return Merlin.db[cfgKey].size end,
		function(v) Merlin.db[cfgKey].size = v end,
		{ disabledFn = styleOff }
	)
	if cfgKey ~= "enchants" then
		ly = CreateSliderRow(leftCol, ly, "Per row", 1, 32, 1,
			function() return Merlin.db[cfgKey].perRow end,
			function(v) Merlin.db[cfgKey].perRow = v end
		)
		ly = CreateSliderRow(leftCol, ly, "Max icons", 1, 40, 1,
			function() return Merlin.db[cfgKey].maxIcons end,
			function(v) Merlin.db[cfgKey].maxIcons = v end
		)
	else
		ly = CreateSliderRow(leftCol, ly, "Per row", 1, 3, 1,
			function() return Merlin.db[cfgKey].perRow end,
			function(v) Merlin.db[cfgKey].perRow = v end,
			{ disabledFn = groupedOff }
		)
	end
	ly = CreateSliderRow(leftCol, ly, "Spacing X", 0, 32, 1,
		function() return Merlin.db[cfgKey].spacingX end,
		function(v) Merlin.db[cfgKey].spacingX = v end,
		{ disabledFn = spacingOff }
	)
	ly = CreateSliderRow(leftCol, ly, "Spacing Y", 0, 32, 1,
		function() return Merlin.db[cfgKey].spacingY end,
		function(v) Merlin.db[cfgKey].spacingY = v end,
		{ disabledFn = spacingOff }
	)
	ly = CreateChoiceRow(leftCol, ly, "Axis", ORIENTATION_OPTS,
		function() return Merlin.db[cfgKey].orientation end,
		function(v) Merlin.db[cfgKey].orientation = v end,
		{ disabledFn = groupedOff }
	)
	ly = CreateChoiceRow(leftCol, ly, "Grow X", GROWTH_X_OPTS,
		function() return Merlin.db[cfgKey].growthX end,
		function(v) Merlin.db[cfgKey].growthX = v end,
		{ disabledFn = groupedOff }
	)
	ly = CreateChoiceRow(leftCol, ly, "Grow Y", GROWTH_Y_OPTS,
		function() return Merlin.db[cfgKey].growthY end,
		function(v) Merlin.db[cfgKey].growthY = v end,
		{ disabledFn = groupedOff }
	)
	if cfgKey ~= "enchants" then
		ly = CreateChoiceRow(leftCol, ly, "Sort by", SORT_METHOD_OPTS,
			function() return Merlin.db[cfgKey].sortMethod end,
			function(v) Merlin.db[cfgKey].sortMethod = v end
		)
		ly = CreateChoiceRow(leftCol, ly, "Sort dir", SORT_DIR_OPTS,
			function() return Merlin.db[cfgKey].sortDirection end,
			function(v) Merlin.db[cfgKey].sortDirection = v end
		)
	end

	ly = ly - 6
	ly = CreateSection(leftCol, ly, "Position")
	ly = CreateChoiceRow(leftCol, ly, "Anchor", isBuff and ANCHOR_OPTS_BUFF or ANCHOR_OPTS_OTHER,
		function() return Merlin.db[cfgKey].anchorTo end,
		function(v) ApplyAnchorPreset(cfgKey, v) end,
		{ disabledFn = detachedOff }
	)
	if cfgKey == "enchants" then
		ly = CreateChoiceRow(leftCol, ly, "Slot", ENCHANT_SLOT_OPTS,
			function() return selectedEnchantSlot end,
			function(v)
				selectedEnchantSlot = v
				RefreshPage("enchants")
			end,
			{ noRefresh = true, disabledFn = soloOff }
		)
		CreatePairRow(leftCol, ly, "X / Y", -5000, 5000,
			function()
				local c = Merlin.db.enchants
				return c.grouped and c.x or c.slots[selectedEnchantSlot].x
			end,
			function(v)
				local c = Merlin.db.enchants
				if c.grouped then c.x = v else c.slots[selectedEnchantSlot].x = v end
			end,
			function()
				local c = Merlin.db.enchants
				return c.grouped and c.y or c.slots[selectedEnchantSlot].y
			end,
			function(v)
				local c = Merlin.db.enchants
				if c.grouped then c.y = v else c.slots[selectedEnchantSlot].y = v end
			end,
			detachedOff
		)
	else
		CreatePairRow(leftCol, ly, "X / Y", -5000, 5000,
			function() return Merlin.db[cfgKey].x end,
			function(v) Merlin.db[cfgKey].x = v end,
			function() return Merlin.db[cfgKey].y end,
			function(v) Merlin.db[cfgKey].y = v end
		)
	end

	-- Right column: Text (font + timer) + Stacks & cooldown (+ Dispel badge / Enchant behavior)
	local ry = 0
	ry = CreateSection(rightCol, ry, "Text", function()
		ResetKeys({
			"fontName", "fontOutline",
			"showDuration", "colorDurationByTime", "showDecimals",
			"durationFormat", "durationFontSize", "durationAnchor",
			"durationOffsetX", "durationOffsetY",
		})
	end)
	ry = CreateChoiceRow(rightCol, ry, "Font", Merlin.GetFontOptions,
		function() return Merlin.db[cfgKey].fontName end,
		function(v) Merlin.db[cfgKey].fontName = v end,
		{ ctrlW = COL_W - 56, disabledFn = styleOff }
	)
	ry = CreateChoiceRow(rightCol, ry, "Outline", OUTLINE_OPTS,
		function() return Merlin.db[cfgKey].fontOutline end,
		function(v) Merlin.db[cfgKey].fontOutline = v end,
		{ disabledFn = styleOff }
	)
	ry = CreateSliderRow(rightCol, ry, "Duration", 8, 24, 1,
		function() return Merlin.db[cfgKey].durationFontSize end,
		function(v) Merlin.db[cfgKey].durationFontSize = v end,
		{
			disabledFn = styleOff,
			tip = "Duration text size",
			check = {
				get = function() return Merlin.db[cfgKey].showDuration end,
				set = function(v) Merlin.db[cfgKey].showDuration = v end,
			},
		}
	)
	ry = CreateCheckPairRow(rightCol, ry,
		"Color by time",
		function() return Merlin.db[cfgKey].colorDurationByTime end,
		function(v) Merlin.db[cfgKey].colorDurationByTime = v end,
		"Decimals",
		function() return Merlin.db[cfgKey].showDecimals end,
		function(v) Merlin.db[cfgKey].showDecimals = v end,
		112, styleOff, styleOff
	)
	ry = CreateChoiceRow(rightCol, ry, "Format", DURATION_FMT_OPTS,
		function() return Merlin.db[cfgKey].durationFormat end,
		function(v) Merlin.db[cfgKey].durationFormat = v end,
		{ disabledFn = styleOff }
	)
	ry = CreateChoiceRow(rightCol, ry, "Position", DURATION_ANCHOR_OPTS,
		function() return Merlin.db[cfgKey].durationAnchor end,
		function(v) Merlin.db[cfgKey].durationAnchor = v end,
		{ disabledFn = styleOff }
	)
	ry = CreatePairRow(rightCol, ry, "Offset X/Y", -32, 32,
		function() return Merlin.db[cfgKey].durationOffsetX end,
		function(v) Merlin.db[cfgKey].durationOffsetX = v end,
		function() return Merlin.db[cfgKey].durationOffsetY end,
		function(v) Merlin.db[cfgKey].durationOffsetY = v end,
		styleOff
	)

	ry = ry - 6
	ry = CreateSection(rightCol, ry, "Stacks & cooldown", function()
		ResetKeys({
			"showCount", "countFontSize", "countAnchor",
			"countOffsetX", "countOffsetY",
			"showCooldownSwipe", "reverseCooldownSwipe",
		})
		if cfgKey == "debuffs" then
			ResetKeys({ "showDispelIcon", "dispelIconStyle", "dispelIconAnchor", "dispelIconSize" })
		end
	end)
	ry = CreateSliderRow(rightCol, ry, "Stacks", 8, 24, 1,
		function() return Merlin.db[cfgKey].countFontSize end,
		function(v) Merlin.db[cfgKey].countFontSize = v end,
		{
			disabledFn = styleOff,
			tip = "Stack text size",
			check = {
				get = function() return Merlin.db[cfgKey].showCount end,
				set = function(v) Merlin.db[cfgKey].showCount = v end,
			},
		}
	)
	ry = CreateChoiceRow(rightCol, ry, "Stack pos", COUNT_ANCHOR_OPTS,
		function() return Merlin.db[cfgKey].countAnchor end,
		function(v) Merlin.db[cfgKey].countAnchor = v end,
		{ disabledFn = styleOff }
	)
	ry = CreatePairRow(rightCol, ry, "Offset X/Y", -32, 32,
		function() return Merlin.db[cfgKey].countOffsetX end,
		function(v) Merlin.db[cfgKey].countOffsetX = v end,
		function() return Merlin.db[cfgKey].countOffsetY end,
		function(v) Merlin.db[cfgKey].countOffsetY = v end,
		styleOff
	)
	ry = CreateCheckPairRow(rightCol, ry,
		"CD swipe",
		function() return Merlin.db[cfgKey].showCooldownSwipe end,
		function(v) Merlin.db[cfgKey].showCooldownSwipe = v end,
		"Reverse",
		function() return Merlin.db[cfgKey].reverseCooldownSwipe end,
		function(v) Merlin.db[cfgKey].reverseCooldownSwipe = v end,
		112, styleOff, styleOff
	)

	if cfgKey == "debuffs" then
		local function badgeOff()
			return not Merlin.db.debuffs.showDispelIcon
		end
		ry = CreateSliderRow(rightCol, ry, "Dispel icon", 8, 32, 1,
			function() return Merlin.db.debuffs.dispelIconSize end,
			function(v) Merlin.db.debuffs.dispelIconSize = v end,
			{
				disabledFn = styleOff,
				tip = "Dispel icon size",
				check = {
					get = function() return Merlin.db.debuffs.showDispelIcon end,
					set = function(v) Merlin.db.debuffs.showDispelIcon = v end,
				},
			}
		)
		ry = CreateChoiceRow(rightCol, ry, "Icon style", DISPEL_ICON_STYLE_OPTS,
			function() return Merlin.db.debuffs.dispelIconStyle end,
			function(v) Merlin.db.debuffs.dispelIconStyle = v end,
			{ disabledFn = badgeOff }
		)
		CreateChoiceRow(rightCol, ry, "Icon corner", CORNER_OPTS,
			function() return Merlin.db.debuffs.dispelIconAnchor end,
			function(v) Merlin.db.debuffs.dispelIconAnchor = v end,
			{ disabledFn = badgeOff }
		)
	elseif cfgKey == "enchants" then
		ry = ry - 6
		ry = CreateSection(rightCol, ry, "Behavior")
		ry = CreateCheckPairRow(rightCol, ry,
			"Follow Buffs",
			function() return Merlin.db.enchants.followBuffsStyle end,
			function(v)
				Merlin.db.enchants.followBuffsStyle = v
				RefreshPage("enchants")
			end,
			"Enchant icon",
			function() return Merlin.db.enchants.useEnchantIcon end,
			function(v)
				Merlin.db.enchants.useEnchantIcon = v
				if Merlin.RefreshEnchantIcons then
					Merlin.RefreshEnchantIcons()
				end
			end,
			104, enchOff, enchOff
		)
		CreateChoiceRow(rightCol, ry, "In Buffs", ENCHANT_PLACE_OPTS,
			function() return Merlin.db.enchants.enchantPlacement end,
			function(v) Merlin.db.enchants.enchantPlacement = v end,
			{ disabledFn = attachedOff }
		)
	end

	-- Footer row: Reset position (left) aligned with Profile selector + Copy Default (right)
	local resetOne = CreateArmedButton(leftCol, "Reset position", 132, function()
		Merlin.ResetGroupPosition(cfgKey)
		ShowStatus(titleText .. " position reset.")
	end)
	resetOne:SetPoint("BOTTOMLEFT", 0, 2)

	local profileBtn = CreateButton(rightCol, "Profile: Default", 132, 24, false)
	profileBtn:SetPoint("BOTTOMRIGHT", 0, 2)
	profileBtn.label:ClearAllPoints()
	profileBtn.label:SetPoint("LEFT", 6, 0)
	profileBtn.label:SetPoint("RIGHT", -16, 0)
	profileBtn.label:SetJustifyH("LEFT")
	profileBtn.label:SetWordWrap(false)
	local profileCaret = CreateGlyph(profileBtn, "chevron", 11)
	profileCaret:SetPoint("RIGHT", -5, 0)
	profileCaret:Draw("chevron", T.muted)
	profileCaret.texture:SetRotation(math.pi)

	local copyBtn = CreateButton(rightCol, "Copy", 54, 24, false)
	copyBtn:SetPoint("RIGHT", profileBtn, "LEFT", -4, 0)
	copyBtn:SetScript("OnEnter", function(self)
		self.hover = true
		self.Paint()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Copy from Default", 1, 1, 1)
		GameTooltip:AddLine("Copy Default settings into this profile.", 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	copyBtn:SetScript("OnLeave", function(self)
		self.hover = nil
		self.Paint()
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	copyBtn:SetScript("OnClick", function()
		if Merlin.IsRestricted() then
			return
		end
		Merlin.CopyGroupFromDefault(cfgKey)
		ShowStatus(titleText .. " copied from Default.")
	end)

	local function GetProfileOptions()
		local _, classLabel = Merlin.GetPlayerClassInfo()
		local _, roleLabel = Merlin.GetPlayerRoleInfo()
		return {
			{ label = "Default", store = "DEFAULT" },
			{ label = "Role (" .. roleLabel .. ")", store = "ROLE" },
			{ label = "Class (" .. classLabel .. ")", store = "CLASS" },
		}
	end

	local function RefreshProfile()
		local sc = Merlin.GetGroupScope(cfgKey)
		if sc == "CLASS" then
			local _, classLabel = Merlin.GetPlayerClassInfo()
			profileBtn:SetWidth(142)
			profileBtn:SetLabel("Class: " .. classLabel)
			profileBtn:SetTextColor(T.accent)
			copyBtn:Show()
		elseif sc == "ROLE" then
			local _, roleLabel = Merlin.GetPlayerRoleInfo()
			profileBtn:SetWidth(142)
			profileBtn:SetLabel("Role: " .. roleLabel)
			profileBtn:SetTextColor(T.accent)
			copyBtn:Show()
		else
			profileBtn:SetWidth(132)
			profileBtn:SetLabel("Profile: Default")
			profileBtn:SetTextColor(T.text)
			copyBtn:Hide()
		end
	end

	profileBtn:SetScript("OnClick", function()
		if Merlin.IsRestricted() then
			return
		end
		OpenMenu(profileBtn, GetProfileOptions(), Merlin.GetGroupScope(cfgKey), function(store)
			Merlin.SetGroupScope(cfgKey, store)
			if store == "CLASS" then
				local _, classLabel = Merlin.GetPlayerClassInfo()
				ShowStatus(titleText .. " saved to Class (" .. classLabel .. ").")
			elseif store == "ROLE" then
				local _, roleLabel = Merlin.GetPlayerRoleInfo()
				ShowStatus(titleText .. " saved to Role (" .. roleLabel .. ").")
			else
				ShowStatus(titleText .. " using Default profile (overrides preserved).")
			end
		end, true)
	end)
	RegisterRefreshFn(RefreshProfile)

	buildingPageKey = nil
	return page
end

local ioTarget = "FULL"

local function GetIOTargetLabel(target)
	if target == "CLASS" then
		local _, classLabel = Merlin.GetPlayerClassInfo()
		return "Class (" .. classLabel .. ")"
	elseif target == "ROLE" then
		local _, roleLabel = Merlin.GetPlayerRoleInfo()
		return "Role (" .. roleLabel .. ")"
	elseif target == "DEFAULT" then
		return "Default"
	end
	return "Full profile"
end

local function GetIOTargetOptions()
	local _, classLabel = Merlin.GetPlayerClassInfo()
	local _, roleLabel = Merlin.GetPlayerRoleInfo()
	return {
		{ label = "Full profile", store = "FULL" },
		{ label = "Default", store = "DEFAULT" },
		{ label = "Role (" .. roleLabel .. ")", store = "ROLE" },
		{ label = "Class (" .. classLabel .. ")", store = "CLASS" },
	}
end

local function OpenIODialog(mode, target)
	local label = GetIOTargetLabel(target)
	if mode == "EXPORT" then
		local value, err = Merlin.ExportProfile(target)
		if not value then
			ShowStatus(err or "Export failed.")
			return
		end
		UI.ioDialog(shell.window, {
			mode = "export", title = "Export — " .. label,
			hint = "Press Ctrl+C to copy this string.", text = value,
		})
	else
		UI.ioDialog(shell.window, {
			mode = "import", title = "Import — " .. label,
			hint = "Paste a !MERLIN1! string (replaces " .. label .. ").",
			onSubmit = function(value)
				local ok, err = Merlin.ImportProfile(value, target)
				if ok then
					ShowStatus("Imported into " .. label .. ".")
				end
				return ok, err
			end,
		})
	end
end

-- Global Settings page (2-column)

local function BuildSettingsPage(main)
	buildingPageKey = "settings"
	local page = CreateFrame("Frame", nil, main)
	page:SetAllPoints(main)
	page:Hide()

	local header = Text(page, "Settings", "GameFontHighlightLarge", T.text)
	header:SetPoint("TOPLEFT", PAD, -11)

	local leftCol = CreateFrame("Frame", nil, page)
	leftCol:SetPoint("TOPLEFT", PAD, -36)
	leftCol:SetPoint("BOTTOMLEFT", PAD, PAD)
	leftCol:SetWidth(COL_W)

	local divider = Fill(page, T.band)
	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", math.floor(COL_GAP / 2), 0)
	divider:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", math.floor(COL_GAP / 2), 6)
	divider:SetWidth(1)

	local rightCol = CreateFrame("Frame", nil, page)
	rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", COL_GAP, 0)
	rightCol:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	-- Left column: Dispel colors, Window, Appearance, Behavior
	local function ResetColors(keys)
		for _, k in ipairs(keys) do
			local d = Merlin.defaults.colors[k]
			Merlin.db.colors[k] = { d[1], d[2], d[3] }
		end
	end

	local ly = 0
	ly = CreateSection(leftCol, ly, "Dispel colors", function()
		ResetColors({
			"dispelNone", "dispelMagic", "dispelCurse",
			"dispelDisease", "dispelPoison", "dispelBleed",
		})
	end)
	ly = CreateColorRow(leftCol, ly, "Physical / None",
		function() return Merlin.db.colors.dispelNone end,
		function(r, g, b) Merlin.db.colors.dispelNone = { r, g, b } end
	)
	ly = CreateColorRow(leftCol, ly, "Magic",
		function() return Merlin.db.colors.dispelMagic end,
		function(r, g, b) Merlin.db.colors.dispelMagic = { r, g, b } end
	)
	ly = CreateColorRow(leftCol, ly, "Curse",
		function() return Merlin.db.colors.dispelCurse end,
		function(r, g, b) Merlin.db.colors.dispelCurse = { r, g, b } end
	)
	ly = CreateColorRow(leftCol, ly, "Disease",
		function() return Merlin.db.colors.dispelDisease end,
		function(r, g, b) Merlin.db.colors.dispelDisease = { r, g, b } end
	)
	ly = CreateColorRow(leftCol, ly, "Poison",
		function() return Merlin.db.colors.dispelPoison end,
		function(r, g, b) Merlin.db.colors.dispelPoison = { r, g, b } end
	)
	ly = CreateColorRow(leftCol, ly, "Bleed",
		function() return Merlin.db.colors.dispelBleed end,
		function(r, g, b) Merlin.db.colors.dispelBleed = { r, g, b } end
	)

	ly = ly - 6
	ly = CreateSection(leftCol, ly, "Appearance", function()
		local def = Merlin.defaults
		Merlin.db.windowOpacity = def.windowOpacity
		Merlin.db.iconZoom = def.iconZoom
		ApplyWindowOpacity()
	end)
	ly = CreateSliderRow(leftCol, ly, "Window alpha", 0.5, 1.0, 0.02,
		function() return Merlin.db.windowOpacity end,
		function(v)
			Merlin.db.windowOpacity = v
			ApplyWindowOpacity()
		end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end,
		{ isPercent = true, noRefresh = true }
	)
	ly = CreateSliderRow(leftCol, ly, "Icon zoom", 0.0, 0.15, 0.01,
		function() return Merlin.db.iconZoom end,
		function(v) Merlin.db.iconZoom = v end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end,
		{ isPercent = true }
	)
	local hasMasque = LibStub and LibStub("Masque", true) ~= nil
	ly = CreateCheckRow(leftCol, ly, "Use Masque",
		function() return Merlin.db.useMasque end,
		function(v)
			Merlin.db.useMasque = v
			ShowStatus("Reload (/reload) to apply Masque change.")
		end,
		function() return not hasMasque end
	)

	ly = ly - 8
	ly = CreateSection(leftCol, ly, "Behavior", function()
		local def = Merlin.defaults
		Merlin.db.tooltipAnchor = def.tooltipAnchor
		Merlin.db.hideTooltipInCombat = def.hideTooltipInCombat
		Merlin.db.allowCancel = def.allowCancel
		Merlin.db.oocAlpha = def.oocAlpha
	end)
	ly = CreateChoiceRow(leftCol, ly, "Tooltip", TOOLTIP_ANCHOR_OPTS,
		function() return Merlin.db.tooltipAnchor end,
		function(v) Merlin.db.tooltipAnchor = v end
	)
	ly = CreateCheckRow(leftCol, ly, "Hide tooltip in combat",
		function() return Merlin.db.hideTooltipInCombat end,
		function(v) Merlin.db.hideTooltipInCombat = v end
	)
	ly = CreateCheckRow(leftCol, ly, "Right-click cancel",
		function() return Merlin.db.allowCancel end,
		function(v) Merlin.db.allowCancel = v end
	)
	ly = CreateSliderRow(leftCol, ly, "OOC alpha", 0.0, 1.0, 0.05,
		function() return Merlin.db.oocAlpha end,
		function(v) Merlin.db.oocAlpha = v end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end,
		{ isPercent = true }
	)

	ly = ly - 8
	ly = CreateSection(leftCol, ly, "Timers", function()
		Merlin.db.durationRounding = Merlin.defaults.durationRounding
		Merlin.db.warnThreshold = Merlin.defaults.warnThreshold
		Merlin.db.urgentThreshold = Merlin.defaults.urgentThreshold
	end)
	ly = CreateChoiceRow(leftCol, ly, "Rounding", DURATION_ROUND_OPTS,
		function() return Merlin.db.durationRounding end,
		function(v) Merlin.db.durationRounding = v end
	)
	ly = CreateSliderRow(leftCol, ly, "Warn (s)", 5, 60, 1,
		function() return Merlin.db.warnThreshold end,
		function(v) Merlin.db.warnThreshold = v end
	)
	CreateSliderRow(leftCol, ly, "Urgent (s)", 1, 15, 1,
		function() return Merlin.db.urgentThreshold end,
		function(v) Merlin.db.urgentThreshold = v end
	)

	-- Right column: Colors, Thresholds, Movement
	local ry = 0
	ry = CreateSection(rightCol, ry, "Colors", function()
		ResetColors({
			"buffBorder", "enchantBorder", "externalBorder",
			"timerWarn", "timerUrgent",
		})
	end)
	ry = CreateColorRow(rightCol, ry, "Buff border",
		function() return Merlin.db.colors.buffBorder end,
		function(r, g, b) Merlin.db.colors.buffBorder = { r, g, b } end
	)
	ry = CreateColorRow(rightCol, ry, "Enchant border",
		function() return Merlin.db.colors.enchantBorder end,
		function(r, g, b) Merlin.db.colors.enchantBorder = { r, g, b } end
	)
	ry = CreateColorRow(rightCol, ry, "External border",
		function() return Merlin.db.colors.externalBorder end,
		function(r, g, b) Merlin.db.colors.externalBorder = { r, g, b } end
	)
	ry = CreateColorRow(rightCol, ry, "Timer warn",
		function() return Merlin.db.colors.timerWarn end,
		function(r, g, b) Merlin.db.colors.timerWarn = { r, g, b } end
	)
	ry = CreateColorRow(rightCol, ry, "Timer urgent",
		function() return Merlin.db.colors.timerUrgent end,
		function(r, g, b) Merlin.db.colors.timerUrgent = { r, g, b } end
	)

	-- Icon border (all groups). Masque skins draw their own borders.
	local function MasqueOwnsBorders()
		return hasMasque and Merlin.db.useMasque
	end
	local function BorderOff()
		return MasqueOwnsBorders() or Merlin.db.borderSize <= 0
	end
	ry = ry - 8
	ry = CreateSection(rightCol, ry, "Border", function()
		local def = Merlin.defaults
		Merlin.db.borderTexture = def.borderTexture
		Merlin.db.borderSize = def.borderSize
		Merlin.db.borderInset = def.borderInset
		Merlin.db.borderAlpha = def.borderAlpha
	end)
	ry = CreateChoiceRow(rightCol, ry, "Texture", Merlin.GetBorderOptions,
		function() return Merlin.db.borderTexture end,
		function(v)
			-- Art borders need room to read; pixel strips stay thin.
			local wasSolid = not Merlin.GetBorderTexturePath(Merlin.db.borderTexture)
			Merlin.db.borderTexture = v
			local isSolid = not Merlin.GetBorderTexturePath(v)
			if wasSolid and not isSolid and Merlin.db.borderSize <= 3 then
				Merlin.db.borderSize = 12
			elseif isSolid and not wasSolid and Merlin.db.borderSize > 3 then
				Merlin.db.borderSize = Merlin.defaults.borderSize
			end
		end,
		{ ctrlW = COL_W - 56, disabledFn = MasqueOwnsBorders }
	)
	ry = CreateSliderRow(rightCol, ry, "Size", 0, Merlin.BORDER_SIZE_MAX, 1,
		function() return Merlin.db.borderSize end,
		function(v) Merlin.db.borderSize = v end,
		function(v) return v == 0 and "Off" or ("%dpx"):format(v) end,
		{ disabledFn = MasqueOwnsBorders }
	)
	ry = CreateSliderRow(rightCol, ry, "Inset", -8, 8, 1,
		function() return Merlin.db.borderInset end,
		function(v) Merlin.db.borderInset = v end,
		function(v) return v > 0 and ("+%d"):format(v) or tostring(v) end,
		{ disabledFn = BorderOff, tip = "Positive moves the border inward, negative outward" }
	)
	ry = CreateSliderRow(rightCol, ry, "Opacity", 0.0, 1.0, 0.05,
		function() return Merlin.db.borderAlpha end,
		function(v) Merlin.db.borderAlpha = v end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end,
		{ isPercent = true, disabledFn = BorderOff }
	)

	if Merlin.IsPriest() then
		ry = ry - 6
		local priestSep = Fill(rightCol, T.control)
		priestSep:ClearAllPoints()
		priestSep:SetPoint("TOPLEFT", 0, ry)
		priestSep:SetPoint("TOPRIGHT", 0, ry)
		priestSep:SetHeight(1)
		ry = ry - 8
		ry = CreateColorRow(rightCol, ry, "Priest accent",
			function() return Merlin.db.colors.priestAccent end,
			function(r, g, b)
				Merlin.db.colors.priestAccent = { r, g, b }
				ApplyAccentColor()
			end
		)
	end

	ry = ry - 10
	ry = CreateSection(rightCol, ry, "Profiles & reset")
	local resetPosBtn = CreateArmedButton(rightCol, "Reset all positions", COL_W, function()
		Merlin.ResetPositions()
		ShowStatus("All positions reset to defaults.")
	end)
	resetPosBtn:SetPoint("TOPLEFT", 0, ry)
	ry = ry - 26

	local clearOverridesBtn = CreateArmedButton(rightCol, "Clear class/role overrides", COL_W, function()
		Merlin.ClearCurrentOverrides()
		ShowStatus("Class & role overrides cleared.")
	end)
	clearOverridesBtn:SetPoint("TOPLEFT", 0, ry)
	ry = ry - 26

	local resetProfileBtn = CreateArmedButton(rightCol, "Reset entire profile", COL_W, function()
		Merlin.ResetProfile()
		ShowStatus("Profile reset to defaults.")
	end)
	resetProfileBtn:SetPoint("TOPLEFT", 0, ry)
	ry = ry - 32

	ry = CreateSection(rightCol, ry, "Import / Export")
	ry = CreateChoiceRow(rightCol, ry, "Target", GetIOTargetOptions,
		function() return ioTarget end,
		function(v) ioTarget = v end,
		{ noRefresh = true }
	)
	ry = ry - 4
	local halfBtnW = math.floor((COL_W - 5) / 2)
	local exportBtn = CreateButton(rightCol, "Export", halfBtnW, 22, false)
	exportBtn:SetPoint("TOPLEFT", 0, ry)
	exportBtn:SetScript("OnClick", function()
		OpenIODialog("EXPORT", ioTarget)
	end)
	local importBtn = CreateButton(rightCol, "Import", COL_W - halfBtnW - 5, 22, false)
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 5, 0)
	importBtn:SetScript("OnClick", function()
		OpenIODialog("IMPORT", ioTarget)
	end)

	buildingPageKey = nil
	return page
end

local groups = {
	{ key = "buffs", label = "Buffs" },
	{ key = "debuffs", label = "Debuffs" },
	{ key = "externals", label = "Externals" },
	{ key = "enchants", label = "Enchants" },
}

local lockNav
local function BuildSidebar(nav, host)
	local label = host:AddNavLabel(Text(nav, "Groups", "GameFontHighlightSmall", T.faint))
	label:SetPoint("TOPLEFT", 10, -14)

	local function AddItem(key, title)
		local button = host:CreateNavButton(nav, {
			label = title, glyph = key, height = 32, hasCount = false,
			onClick = function() host:Show(key) end,
		})
		button.page = key
		return button
	end
	for i, group in ipairs(groups) do
		AddItem(group.key, group.label):SetPoint("TOPLEFT", 4, -34 - (i - 1) * 34)
	end

	local settings = AddItem("settings", "Settings")
	settings:SetPoint("BOTTOMLEFT", 4, 10)
	lockNav = host:CreateNavButton(nav, {
		label = "Locked", glyph = "locked", height = 32, hasCount = false,
		tip = function() return Merlin.db.locked and "Locked" or "Unlocked" end,
		desc = function() return Merlin.db.locked and "Unlock aura movers." or "Lock aura movers." end,
		onClick = function()
			if UI.WritesBlocked() then return end
			Merlin.db.locked = not Merlin.db.locked
			Merlin.RequestRefresh()
			host:Refresh()
		end,
	})
	lockNav:SetPoint("BOTTOMLEFT", settings, "TOPLEFT", 0, 2)
	local divider = Fill(nav, T.control)
	divider:ClearAllPoints()
	divider:SetPoint("BOTTOMLEFT", lockNav, "TOPLEFT", 8, 4)
	divider:SetPoint("BOTTOMRIGHT", lockNav, "TOPRIGHT", -8, 4)
	divider:SetHeight(1)

	local toggle = host:CreateNavButton(nav, {
		label = "Toggle sidebar", glyph = "collapse", height = 32, hasCount = false,
		tip = function() return Merlin.db.navCollapsed and "Expand sidebar" or "Collapse sidebar" end,
		onClick = function() host:ToggleSidebar() end,
	})
	toggle:SetPoint("BOTTOMLEFT", lockNav, "TOPLEFT", 0, 9)
	host:SetCollapseButton(toggle)
end

shell = UI.CreateShell({
	name = "MerlinOptionsFrame",
	width = WIDTH,
	height = HEIGHT,
	dragMode = "window",
	wordmark = { style = "diamonds", text = "Merlin" },
	toastPlacement = "below",
	toastTextColor = T.accent,
	getOpacity = function() return Merlin.db.windowOpacity or 0.94 end,
	closeInCombat = true,
	closeOnRestricted = true,
	defaultPage = "buffs",
	sidebar = {
		width = NAV_W,
		collapsedWidth = NAV_COLLAPSED,
		collapseMode = "resize",
		getCollapsed = function() return Merlin.db.navCollapsed end,
		setCollapsed = function(value) Merlin.db.navCollapsed = value end,
		build = BuildSidebar,
	},
	onRefresh = function(host)
		lockNav.fullLabel = Merlin.db.locked and "Locked" or "Unlocked"
		lockNav.glyphKey = Merlin.db.locked and "locked" or "unlocked"
		for _, button in ipairs(host.navButtons) do
			if button.page then
				button:SetActive(button.page == host.activePage)
			end
		end
	end,
})

local function Page(frame, key)
	return { frame = frame, Refresh = function() RefreshPage(key) end }
end

for _, group in ipairs(groups) do
	shell:RegisterPage(group.key, function(parent)
		return Page(BuildGroupPage(parent, group.key, group.label, group.key == "buffs"), group.key)
	end)
end
shell:RegisterPage("settings", function(parent)
	return Page(BuildSettingsPage(parent), "settings")
end)

function Merlin.RefreshOptions()
	if shell:IsShown() then
		ApplyWindowOpacity()
		ApplyAccentColor()
		shell:Refresh()
	end
end

function Merlin.CloseOptions()
	shell:Hide()
end

function Merlin.ToggleOptions()
	if Merlin.IsRestricted() then
		Merlin.Print("Options are unavailable during combat or restricted content.")
		return
	end
	ApplyAccentColor()
	shell:Toggle()
end

Merlin.RegisterRefresh(Merlin.RefreshOptions)
