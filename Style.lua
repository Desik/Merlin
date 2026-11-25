local _, Merlin = ...

local ROUND_NEAREST = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Nearest
local ROUND_UP = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
local ROUND_DOWN = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
local PRESERVE_ASSET = Enum.CustomAuraButtonDispelTypeTextureStyle
	and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
local DISPEL_ICON_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle
	and Enum.CustomAuraButtonDispelTypeTextureStyle.Icon
local DISPEL_ASSET_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle
	and Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset
local DURATION_PROP_REMAINING = Enum.DurationTextBindingProperty
	and Enum.DurationTextBindingProperty.RemainingDuration

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DISPEL_ICON_OPTS = DISPEL_ICON_STYLE and {
	style = DISPEL_ICON_STYLE,
	showWhenHarmful = true,
	showWhenHelpful = false,
} or nil

-- Blizzard dispel-type icons (icons_64x64_* atlases; present in the Forever
-- atlas list, Ketho BlizzardInterfaceResources forever e230342a). Drawn by the
-- native CustomAsset style; a white color map keeps the art untinted.
local DISPEL_ATLAS = {
	Magic = "icons_64x64_magic",
	Curse = "icons_64x64_curse",
	Disease = "icons_64x64_disease",
	Poison = "icons_64x64_poison",
	Bleed = "icons_64x64_bleed",
	Enrage = "icons_64x64_enrage",
}
Merlin.DISPEL_ATLAS = DISPEL_ATLAS

local DISPEL_ATLAS_OPTS
if DISPEL_ASSET_STYLE and CreateColor then
	local assets, colors = {}, { None = CreateColor(1, 1, 1, 1) }
	for dispelType, atlas in pairs(DISPEL_ATLAS) do
		assets[dispelType] = { asset = atlas, useAtlasSize = false }
		colors[dispelType] = CreateColor(1, 1, 1, 1)
	end
	DISPEL_ATLAS_OPTS = {
		style = DISPEL_ASSET_STYLE,
		showWhenHarmful = true,
		showWhenHelpful = false,
		customDispelAssetMap = assets,
		customDispelColorMap = colors,
	}
end

local function GetDispelIconOptions(cfg)
	if cfg.dispelIconStyle == "BLIZZARD" and DISPEL_ATLAS_OPTS then
		return DISPEL_ATLAS_OPTS, "blizzard"
	end
	return DISPEL_ICON_OPTS, "diamond"
end

-- Badge centred on the chosen icon corner, nudged 2px inward.
local function PositionDispelBadge(badge, button, cfg)
	local corner = cfg.dispelIconAnchor or "TOPLEFT"
	local x = corner:find("LEFT") and 2 or -2
	local y = corner:find("TOP") and -2 or 2
	local size = cfg.dispelIconSize or 14
	badge:SetSize(size, size)
	badge:ClearAllPoints()
	badge:SetPoint("CENTER", button, corner, x, y)
end
Merlin.PositionDispelBadge = PositionDispelBadge

local function SafeSetFont(fs, path, size, outline)
	if not fs:SetFont(path, size, outline) then
		fs:SetFont(DEFAULT_FONT, size, outline)
	end
end

-- Custom dispel type color map (ColorMixin values expected by CustomAuraButton).
local cachedDispelColors
local cachedDispelSig = ""

local function EnsureDispelColorMap()
	local cols = Merlin.db and Merlin.db.colors or Merlin.defaults.colors
	local n = cols.dispelNone
	local m = cols.dispelMagic
	local cu = cols.dispelCurse
	local d = cols.dispelDisease
	local p = cols.dispelPoison
	local b = cols.dispelBleed
	local sig = ("%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f"):format(
		n[1], n[2], n[3], m[1], m[2], m[3], cu[1], cu[2], cu[3],
		d[1], d[2], d[3], p[1], p[2], p[3], b[1], b[2], b[3]
	)
	if sig ~= cachedDispelSig or not cachedDispelColors then
		cachedDispelSig = sig
		cachedDispelColors = {
			None = CreateColor(n[1], n[2], n[3], 1),
			Magic = CreateColor(m[1], m[2], m[3], 1),
			Curse = CreateColor(cu[1], cu[2], cu[3], 1),
			Disease = CreateColor(d[1], d[2], d[3], 1),
			Poison = CreateColor(p[1], p[2], p[3], 1),
			Bleed = CreateColor(b[1], b[2], b[3], 1),
		}
	end
	return cachedDispelColors, cachedDispelSig
end

local DURATION_ANCHORS = {
	BELOW = { point = "TOP", relPoint = "BOTTOM" },
	BOTTOM = { point = "BOTTOM", relPoint = "BOTTOM" },
	CENTER = { point = "CENTER", relPoint = "CENTER" },
	TOP = { point = "TOP", relPoint = "TOP" },
	ABOVE = { point = "BOTTOM", relPoint = "TOP" },
}

local COUNT_ANCHORS = {
	TOPRIGHT = { point = "TOPRIGHT", relPoint = "TOPRIGHT", justify = "RIGHT" },
	BOTTOMRIGHT = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", justify = "RIGHT" },
	TOPLEFT = { point = "TOPLEFT", relPoint = "TOPLEFT", justify = "LEFT" },
	BOTTOMLEFT = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", justify = "LEFT" },
	CENTER = { point = "CENTER", relPoint = "CENTER", justify = "CENTER" },
}

local durationFormatters = {}
local durationColorCurve
local curveSig = ""

local masqueGroups = {}
local masqueSkins = {}
local masqueSkinByHost = {}
local masqueSkinsByGroup = {}
local styledButtons = {}

-- Duration formatters & expire color curve (native Forever objects)

local function BuildDurationFormatter(formatKey, withDecimals, roundingMode)
	if formatKey == "BLIZZARD" then
		return nil
	end
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
		and ROUND_NEAREST and ROUND_UP and ROUND_DOWN)
	then
		return nil
	end

	local isNearest = (roundingMode == "NEAREST")
	local isCeil90 = (roundingMode == "CEIL90")
	local roundMode = isNearest and ROUND_NEAREST or ROUND_UP
	local secSuffix = (formatKey == "COMPACT") and "s" or ""

	local rules = {}
	if withDecimals then
		rules[#rules + 1] = {
			threshold = 0,
			step = 0.1,
			min = 0.1,
			rounding = ROUND_UP,
			format = "%.1f" .. secSuffix,
		}
		rules[#rules + 1] = {
			threshold = 10,
			step = 1,
			rounding = roundMode,
			format = "%d" .. secSuffix,
		}
	else
		rules[#rules + 1] = {
			threshold = 0,
			step = 1,
			min = 1,
			rounding = roundMode,
			format = "%d" .. secSuffix,
		}
	end

	local mSecAt = isNearest and 59.5 or SECONDS_PER_MIN
	local min5At = isNearest and (5 * SECONDS_PER_MIN - 0.5) or (5 * SECONDS_PER_MIN)
	local hourAt = isNearest and (SECONDS_PER_HOUR - 30) or SECONDS_PER_HOUR
	local dayAt = isNearest and (SECONDS_PER_DAY - 1800) or SECONDS_PER_DAY

	if formatKey == "COMPACT" then
		local minAt = isCeil90 and 90 or mSecAt
		local cHourAt = isCeil90 and (90 * SECONDS_PER_MIN) or hourAt
		local cDayAt = isCeil90 and (36 * SECONDS_PER_HOUR) or dayAt
		rules[#rules + 1] = {
			threshold = minAt,
			step = SECONDS_PER_MIN,
			rounding = roundMode,
			format = "%dm",
			components = { { div = SECONDS_PER_MIN, step = 1, rounding = roundMode } },
		}
		rules[#rules + 1] = {
			threshold = cHourAt,
			step = SECONDS_PER_HOUR,
			rounding = roundMode,
			format = "%dh",
			components = { { div = SECONDS_PER_HOUR, step = 1, rounding = roundMode } },
		}
		rules[#rules + 1] = {
			threshold = cDayAt,
			step = SECONDS_PER_DAY,
			rounding = roundMode,
			format = "%dd",
			components = { { div = SECONDS_PER_DAY, step = 1, rounding = roundMode } },
		}
	elseif formatKey == "CLOCK" then
		local clockHourAt = isNearest and (SECONDS_PER_HOUR - 0.5) or SECONDS_PER_HOUR
		local clockDayAt = isNearest and (SECONDS_PER_DAY - 30) or SECONDS_PER_DAY
		rules[#rules + 1] = {
			threshold = mSecAt,
			step = 1,
			rounding = roundMode,
			format = "%d:%02d",
			components = {
				{ div = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN },
				{ mod = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN },
			},
		}
		rules[#rules + 1] = {
			threshold = clockHourAt,
			step = SECONDS_PER_MIN,
			rounding = roundMode,
			format = "%d:%02d",
			components = {
				{ div = SECONDS_PER_HOUR, step = 1, rounding = ROUND_DOWN },
				{ div = SECONDS_PER_MIN, mod = 60, step = 1, rounding = ROUND_DOWN },
			},
		}
		rules[#rules + 1] = {
			threshold = clockDayAt,
			step = SECONDS_PER_DAY,
			rounding = roundMode,
			format = "%dd",
			components = { { div = SECONDS_PER_DAY, step = 1, rounding = roundMode } },
		}
	else
		-- SMART, DETAILED, DECIMAL all show m:ss under 5m and %dm from 5m to 1h
		rules[#rules + 1] = {
			threshold = mSecAt,
			step = 1,
			rounding = roundMode,
			format = "%d:%02d",
			components = {
				{ div = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN },
				{ mod = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN },
			},
		}
		rules[#rules + 1] = {
			threshold = min5At,
			step = SECONDS_PER_MIN,
			rounding = roundMode,
			format = "%dm",
			components = { { div = SECONDS_PER_MIN, step = 1, rounding = roundMode } },
		}
		if formatKey == "DETAILED" then
			local detDayAt = isNearest and (SECONDS_PER_DAY - 30) or SECONDS_PER_DAY
			local twoDayAt = isNearest and (2 * SECONDS_PER_DAY - 1800) or (2 * SECONDS_PER_DAY)
			rules[#rules + 1] = {
				threshold = hourAt,
				step = SECONDS_PER_MIN,
				rounding = roundMode,
				format = "%dh %dm",
				components = {
					{ div = SECONDS_PER_HOUR, step = 1, rounding = ROUND_DOWN },
					{ div = SECONDS_PER_MIN, mod = 60, step = 1, rounding = ROUND_DOWN },
				},
			}
			rules[#rules + 1] = {
				threshold = detDayAt,
				step = SECONDS_PER_HOUR,
				rounding = roundMode,
				format = "%dd %dh",
				components = {
					{ div = SECONDS_PER_DAY, step = 1, rounding = ROUND_DOWN },
					{ div = SECONDS_PER_HOUR, mod = 24, step = 1, rounding = ROUND_DOWN },
				},
			}
			rules[#rules + 1] = {
				threshold = twoDayAt,
				step = SECONDS_PER_DAY,
				rounding = roundMode,
				format = "%dd",
				components = { { div = SECONDS_PER_DAY, step = 1, rounding = roundMode } },
			}
		elseif formatKey == "DECIMAL" then
			rules[#rules + 1] = {
				threshold = hourAt,
				step = 360,
				rounding = roundMode,
				format = "%.1fh",
				components = { { div = SECONDS_PER_HOUR } },
			}
			rules[#rules + 1] = {
				threshold = dayAt,
				step = SECONDS_PER_DAY,
				rounding = roundMode,
				format = "%dd",
				components = { { div = SECONDS_PER_DAY, step = 1, rounding = roundMode } },
			}
		else
			local sHourAt = isCeil90 and (90 * SECONDS_PER_MIN) or hourAt
			local sDayAt = isCeil90 and (36 * SECONDS_PER_HOUR) or dayAt
			rules[#rules + 1] = {
				threshold = sHourAt,
				step = SECONDS_PER_HOUR,
				rounding = roundMode,
				format = "%dh",
				components = { { div = SECONDS_PER_HOUR, step = 1, rounding = roundMode } },
			}
			rules[#rules + 1] = {
				threshold = sDayAt,
				step = SECONDS_PER_DAY,
				rounding = roundMode,
				format = "%dd",
				components = { { div = SECONDS_PER_DAY, step = 1, rounding = roundMode } },
			}
		end
	end

	local formatter = C_StringUtil.CreateNumericRuleFormatter()
	local ok = pcall(formatter.SetBreakpoints, formatter, rules)
	if not ok then
		return nil
	end
	return formatter
end

local function GetDurationFormatter(formatKey, withDecimals, roundingMode)
	if formatKey == "BLIZZARD" then
		return nil
	end
	local key = formatKey .. ":" .. tostring(withDecimals == true) .. ":" .. (roundingMode or "NEAREST")
	if durationFormatters[key] == nil then
		durationFormatters[key] = BuildDurationFormatter(formatKey, withDecimals, roundingMode) or false
	end
	return durationFormatters[key] or nil
end

local function EnsureDurationColorCurve()
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum.LuaCurveType) then
		return nil, ""
	end
	local db = Merlin.db
	local w = db.colors.timerWarn
	local u = db.colors.timerUrgent
	local warnAt = math.max(db.urgentThreshold + 1, db.warnThreshold)
	local sig = ("%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d|%d"):format(
		u[1], u[2], u[3], w[1], w[2], w[3], db.urgentThreshold, warnAt
	)
	if sig ~= curveSig or not durationColorCurve then
		curveSig = sig
		local curve = C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Step)
		curve:AddPoint(0, CreateColor(u[1], u[2], u[3], 1))
		curve:AddPoint(db.urgentThreshold, CreateColor(w[1], w[2], w[3], 1))
		curve:AddPoint(warnAt, CreateColor(1.0, 1.0, 1.0, 1))
		durationColorCurve = curve
	end
	return durationColorCurve, curveSig
end

local function BuildDurationOptions(cfg)
	local opts = {}
	local rounding = Merlin.db and Merlin.db.durationRounding or "NEAREST"
	local fmt = GetDurationFormatter(cfg.durationFormat, cfg.showDecimals, rounding)
	if fmt then
		opts.textFormatter = fmt
	end
	local curve = EnsureDurationColorCurve()
	if cfg.colorDurationByTime and curve and DURATION_PROP_REMAINING then
		opts.textColor = {
			curve = curve,
			property = DURATION_PROP_REMAINING,
		}
	end
	return opts
end

-- Shared anchor & crop helpers (also used by Containers.lua & Options.lua)

function Merlin.PositionDurationText(fs, relativeTo, cfg)
	local a = DURATION_ANCHORS[cfg.durationAnchor] or DURATION_ANCHORS.BELOW
	fs:ClearAllPoints()
	fs:SetPoint(a.point, relativeTo, a.relPoint, cfg.durationOffsetX, cfg.durationOffsetY)
	fs:SetJustifyH("CENTER")
end

function Merlin.PositionCountText(fs, relativeTo, cfg)
	local a = COUNT_ANCHORS[cfg.countAnchor] or COUNT_ANCHORS.TOPRIGHT
	fs:ClearAllPoints()
	fs:SetPoint(a.point, relativeTo, a.relPoint, cfg.countOffsetX, cfg.countOffsetY)
	fs:SetJustifyH(a.justify)
end

function Merlin.ApplyIconTexCoord(texture)
	local zoom = Merlin.db and Merlin.db.iconZoom or 0.08
	texture:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
end

-- Optional Masque integration

local function GetMasqueGroup(groupName)
	if not (Merlin.db and Merlin.db.useMasque and LibStub) then
		return nil
	end
	local Masque = LibStub("Masque", true)
	if not Masque then
		return nil
	end
	if not masqueGroups[groupName] then
		local group = Masque:Group("Merlin", groupName)
		masqueGroups[groupName] = group
		masqueSkinsByGroup[group] = {}

		hooksecurefunc(group, "ReSkin", function(_, target)
			local targeted = target and masqueSkinByHost[target]
			if targeted and targeted.group == group then
				if not targeted.applying then
					if targeted.registered and not targeted.blocked then
						targeted.needsPostSync = true
					else
						targeted.dirty = true
					end
					Merlin.RequestRefresh()
				end
				return
			end
			local changed
			for _, skin in ipairs(masqueSkinsByGroup[group]) do
				if not skin.applying then
					if skin.registered and not skin.blocked then
						skin.needsPostSync = true
					else
						skin.dirty = true
					end
					changed = true
				end
			end
			if changed then
				Merlin.RequestRefresh()
			end
		end)

		if group.RegisterCallback then
			group:RegisterCallback(function()
				local dirty
				for _, skin in ipairs(masqueSkinsByGroup[group]) do
					if not skin.applying then
						skin.dirty = true
						dirty = true
					end
				end
				if dirty then
					Merlin.RequestRefresh()
				end
			end)
		end
	end
	return masqueGroups[groupName]
end

local function GetStaticBorderColor(kind)
	local c = Merlin.db.colors
	if kind == "enchant" or kind == "enchant_detached" then
		return c.enchantBorder
	elseif kind == "external" then
		return c.externalBorder
	end
	return c.buffBorder
end

local function ApplyMasqueBorderColor(skin)
	if not (skin and skin.border and skin.kind ~= "debuff" and Merlin.CanAccessObject(skin.border)) then
		return
	end
	local c = GetStaticBorderColor(skin.kind)
	skin.border:SetVertexColor(c[1], c[2], c[3], 1)
	skin.border:Show()
end

local function GetMasqueButtonType(kind)
	if kind == "debuff" then
		return "Debuff"
	elseif kind == "enchant" or kind == "enchant_detached" then
		return "Enchant"
	elseif kind == "buff" then
		return "Buff"
	end
	return "Aura"
end

local function ApplyMasqueSkin(skin, width, height)
	skin.width, skin.height = width, height
	skin.applying = true
	local ok, err = pcall(function()
		local group = skin.group
		if not group then
			return
		end
		if group.db and (group.db.Disabled or group.Queued) then
			skin.blocked = true
			return
		end
		skin.host:SetSize(width, height)
		local wasRegistered = skin.registered
		if not wasRegistered then
			local regions = {
				Icon = skin.icon,
				Cooldown = skin.cooldown,
				Count = false,
				Duration = false,
			}
			if skin.border then
				if skin.kind == "debuff" then
					regions.DebuffBorder = skin.border
				elseif skin.kind == "enchant" or skin.kind == "enchant_detached" then
					regions.EnchantBorder = skin.border
				else
					regions.Border = skin.border
				end
			end
			group:AddButton(skin.host, regions, GetMasqueButtonType(skin.kind), true)
			skin.registered = true
		end
		if group.SetFrameSize then
			group:SetFrameSize(width, height, skin.host, false, true)
		end
		if wasRegistered then
			group:ReSkin(skin.host)
		end
		ApplyMasqueBorderColor(skin)
		skin.blocked = nil
	end)
	skin.applying = nil
	if not ok then
		skin.blocked = true
		if not skin.reportedError then
			skin.reportedError = true
			geterrorhandler()(err)
		end
		return
	end
	if not skin.blocked then
		skin.dirty = false
		skin.needsPostSync = false
	end
end

-- Icon border (used when Masque is absent or disabled): crisp N-pixel strips
-- for "Solid", or an 8-piece LibSharedMedia border built from Merlin-owned
-- textures. No BackdropTemplate, so no size scripts run on frames parented to
-- the native aura button; geometry is recomputed on every style refresh.

-- Edge-file strip layout from Blizzard_SharedXML/Backdrop.lua textureUVs
-- (Gethe wow-ui-source bd2470ae, Forever 1.60.1 build 70009): eight 1/8-wide
-- cells (left, right, top, bottom, TL, TR, BL, BR), V inset by 1/16.
local EDGE_V0, EDGE_V1 = 0.0625, 0.9375
local EDGE_CELLS = {
	TL = { 0.5078125, 0.6171875 },
	TR = { 0.6328125, 0.7421875 },
	BL = { 0.7578125, 0.8671875 },
	BR = { 0.8828125, 0.9921875 },
	L = { 0.0078125, 0.1171875 },
	R = { 0.1328125, 0.2421875 },
	T = { 0.2578125, 0.3671875 },
	B = { 0.3828125, 0.4921875 },
}
local CORNER_KEYS = { "TL", "TR", "BL", "BR" }
local SIDE_KEYS = { "T", "B", "L", "R" }

local function CreateBorderEdges(parent, frameLevel, r, g, b, a)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	holder:SetFrameLevel(frameLevel)
	holder.target = parent

	local top = holder:CreateTexture(nil, "OVERLAY", nil, 1)
	local bottom = holder:CreateTexture(nil, "OVERLAY", nil, 1)
	local left = holder:CreateTexture(nil, "OVERLAY", nil, 1)
	local right = holder:CreateTexture(nil, "OVERLAY", nil, 1)

	top:SetPoint("TOPLEFT", holder, "TOPLEFT")
	top:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
	bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")
	left:SetPoint("TOPLEFT", holder, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
	right:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")

	local edges = { top, bottom, left, right }
	for _, edge in ipairs(edges) do
		edge:SetTexture(WHITE_TEXTURE)
		edge:SetVertexColor(r, g, b, a or 1)
	end
	holder.edges = edges

	local P = {}
	local pieceList = {}
	for _, list in ipairs({ CORNER_KEYS, SIDE_KEYS }) do
		for _, key in ipairs(list) do
			local piece = holder:CreateTexture(nil, "OVERLAY", nil, 1)
			piece:SetVertexColor(r, g, b, a or 1)
			piece:Hide()
			P[key] = piece
			pieceList[#pieceList + 1] = piece
		end
	end
	P.TL:SetPoint("TOPLEFT", holder, "TOPLEFT")
	P.TR:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
	P.BL:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
	P.BR:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")
	P.T:SetPoint("TOPLEFT", P.TL, "TOPRIGHT")
	P.T:SetPoint("TOPRIGHT", P.TR, "TOPLEFT")
	P.B:SetPoint("BOTTOMLEFT", P.BL, "BOTTOMRIGHT")
	P.B:SetPoint("BOTTOMRIGHT", P.BR, "BOTTOMLEFT")
	P.L:SetPoint("TOPLEFT", P.TL, "BOTTOMLEFT")
	P.L:SetPoint("BOTTOMLEFT", P.BL, "TOPLEFT")
	P.R:SetPoint("TOPRIGHT", P.TR, "BOTTOMRIGHT")
	P.R:SetPoint("BOTTOMRIGHT", P.BR, "TOPRIGHT")
	holder.pieces = P
	holder.pieceList = pieceList

	holder.active = edges
	holder.activeKey = "solid"
	return holder
end

local function LayoutTexturedBorder(holder, path, edge, innerW, innerH)
	local P = holder.pieces
	if holder.texPath ~= path then
		for _, piece in ipairs(holder.pieceList) do
			piece:SetTexture(path, "REPEAT", "REPEAT")
		end
		holder.texPath = path
	end
	for _, key in ipairs(CORNER_KEYS) do
		local c = EDGE_CELLS[key]
		P[key]:SetSize(edge, edge)
		P[key]:SetTexCoord(c[1], c[2], EDGE_V0, EDGE_V1)
		P[key]:Show()
	end
	P.T:SetHeight(edge)
	P.B:SetHeight(edge)
	P.L:SetWidth(edge)
	P.R:SetWidth(edge)
	-- Side cells tile along V; horizontal sides use the cells rotated.
	local repX = EDGE_V0 + math.max(0.01, (innerW - 2 * edge) / edge)
	local repY = EDGE_V0 + math.max(0.01, (innerH - 2 * edge) / edge)
	local c = EDGE_CELLS.L
	P.L:SetTexCoord(c[1], EDGE_V0, c[1], repY, c[2], EDGE_V0, c[2], repY)
	c = EDGE_CELLS.R
	P.R:SetTexCoord(c[1], EDGE_V0, c[1], repY, c[2], EDGE_V0, c[2], repY)
	c = EDGE_CELLS.T
	P.T:SetTexCoord(c[1], repX, c[2], repX, c[1], EDGE_V0, c[2], EDGE_V0)
	c = EDGE_CELLS.B
	P.B:SetTexCoord(c[1], repX, c[2], repX, c[1], EDGE_V0, c[2], EDGE_V0)
	local showSides = innerW > 2 * edge and innerH > 2 * edge
	for _, key in ipairs(SIDE_KEYS) do
		P[key]:SetShown(showSides)
	end
end

-- color: static RGB, or nil to leave vertex colors to native dispel coloring.
-- width/height: size of the bordered region (icon) in UI units.
local function UpdateBorderVisuals(holder, color, pixelSize, width, height)
	if not (holder and holder.edges and Merlin.CanAccessObject(holder)) then
		return
	end
	local db = Merlin.db
	local sizePx = db and db.borderSize or 1
	if sizePx <= 0 then
		holder:Hide()
		return
	end
	local px = pixelSize or Merlin.GetPixelSize(UIParent)
	local inset = (db and db.borderInset or 0) * px
	local target = holder.target
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", target, "TOPLEFT", inset, -inset)
	holder:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -inset, inset)
	holder:SetAlpha(db and db.borderAlpha or 1)
	holder:Show()

	local edge = px * sizePx
	local path = db and Merlin.GetBorderTexturePath(db.borderTexture)
	if path then
		for _, e in ipairs(holder.edges) do
			e:Hide()
		end
		local w = (width or target:GetWidth() or 0) - 2 * inset
		local h = (height or target:GetHeight() or 0) - 2 * inset
		LayoutTexturedBorder(holder, path, edge, w, h)
		holder.active = holder.pieceList
		holder.activeKey = path
	else
		for _, piece in ipairs(holder.pieceList) do
			piece:Hide()
		end
		holder.edges[1]:SetHeight(edge)
		holder.edges[2]:SetHeight(edge)
		holder.edges[3]:SetWidth(edge)
		holder.edges[4]:SetWidth(edge)
		for _, e in ipairs(holder.edges) do
			e:Show()
		end
		holder.active = holder.edges
		holder.activeKey = "solid"
	end
	if color then
		for _, tex in ipairs(holder.active) do
			tex:SetVertexColor(color[1], color[2], color[3], 1)
		end
	end
end

-- Shared with the options preview so it renders the same border.
Merlin.CreateIconBorder = CreateBorderEdges
Merlin.UpdateIconBorder = UpdateBorderVisuals

-- Weapon enchant icon resolution (shows enchant spell/item art instead of weapon texture)

local WEAPON_SLOTS = Enum.WeaponSlot and {
	mh = Enum.WeaponSlot.MainHand,
	oh = Enum.WeaponSlot.OffHand,
	ranged = Enum.WeaponSlot.Ranged,
} or {}

local ENCHANT_ART = {
	-- Wizard & Mana Oils
	[2623] = { item = 20744 }, [2626] = { item = 20746 }, [2627] = { item = 20750 },
	[2628] = { item = 20749 }, [2685] = { item = 23123 },
	[2624] = { item = 20745 }, [2625] = { item = 20747 }, [2629] = { item = 20748 },
	-- Warlock Spellstone & Firestone
	[3597] = { item = 5522 }, [3615] = { item = 5522 }, [3616] = { item = 5522 },
	[3617] = { item = 5522 }, [3618] = { item = 5522 }, [3619] = { item = 5522 },
	[3598] = { item = 1254 }, [3609] = { item = 1254 }, [3610] = { item = 1254 },
	[3611] = { item = 1254 }, [3612] = { item = 1254 }, [3613] = { item = 1254 }, [3614] = { item = 1254 },
	-- Sharpening Stones
	[40] = { item = 2862 }, [13] = { item = 2863 }, [14] = { item = 2871 },
	[483] = { item = 7964 }, [1643] = { item = 12404 }, [2506] = { item = 18262 }, [2684] = { item = 23122 },
	-- Weightstones
	[19] = { item = 3239 }, [20] = { item = 3240 }, [21] = { item = 3241 },
	[484] = { item = 7965 }, [1703] = { item = 12643 },
	-- Shaman Imbues
	[29] = { spell = 8017 }, [6] = { spell = 8017 }, [1] = { spell = 8017 },
	[503] = { spell = 8017 }, [1663] = { spell = 8017 }, [683] = { spell = 8017 }, [1664] = { spell = 8017 },
	[5] = { spell = 8024 }, [4] = { spell = 8024 }, [3] = { spell = 8024 },
	[523] = { spell = 8024 }, [1665] = { spell = 8024 }, [1666] = { spell = 8024 },
	[2] = { spell = 8033 }, [12] = { spell = 8033 }, [524] = { spell = 8033 },
	[1667] = { spell = 8033 }, [1668] = { spell = 8033 },
	[283] = { spell = 8232 }, [284] = { spell = 8232 }, [525] = { spell = 8232 }, [1669] = { spell = 8232 },
	-- Rogue Poisons
	[323] = { item = 6947 }, [324] = { item = 6947 }, [325] = { item = 6947 },
	[623] = { item = 6947 }, [624] = { item = 6947 }, [625] = { item = 6947 },
	[7] = { item = 2892 }, [8] = { item = 2892 }, [626] = { item = 2892 },
	[627] = { item = 2892 }, [2630] = { item = 2892 },
	[22] = { item = 3775 }, [603] = { item = 3775 },
	[35] = { item = 5237 }, [23] = { item = 5237 }, [643] = { item = 5237 },
	[703] = { item = 10918 }, [704] = { item = 10918 }, [705] = { item = 10918 }, [706] = { item = 10918 },
}

local activeEnchantArt = {}

local function SafeValue(val)
	if val == nil then
		return nil
	end
	if issecretvalue and issecretvalue(val) then
		return nil
	end
	if canaccessvalue and not canaccessvalue(val) then
		return nil
	end
	return val
end

local function ResolveEnchantIcon(enchantID, enchantIconID)
	if enchantIconID and enchantIconID ~= 0 then
		return enchantIconID
	end
	local ref = enchantID and ENCHANT_ART[enchantID]
	if ref then
		if ref.spell and C_Spell and C_Spell.GetSpellTexture then
			local tex = SafeValue(C_Spell.GetSpellTexture(ref.spell))
			if tex then
				return tex
			end
		elseif ref.item and C_Item and C_Item.GetItemIconByID then
			local tex = SafeValue(C_Item.GetItemIconByID(ref.item))
			if tex then
				return tex
			end
		end
	end
	return nil
end

local function QueryEnchantArt(slotKey)
	local ws = WEAPON_SLOTS[slotKey]
	if not (ws and C_Item and C_Item.GetWeaponEnchantInfo and Enum.ItemEnchantType) then
		return activeEnchantArt[slotKey]
	end
	local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
	if not ok or not SafeValue(list) or type(list) ~= "table" then
		return activeEnchantArt[slotKey]
	end
	local uncertain = false
	for _, info in pairs(list) do
		if not SafeValue(info) or type(info) ~= "table" then
			uncertain = true
		else
			local etype = SafeValue(info.enchantType)
			local present = SafeValue(info.hasEnchant)
			if etype == nil or present == nil then
				uncertain = true
			elseif present and (etype == Enum.ItemEnchantType.Temporary or etype == Enum.ItemEnchantType.Imbue) then
				local art = ResolveEnchantIcon(SafeValue(info.enchantID), SafeValue(info.enchantIconID))
				activeEnchantArt[slotKey] = art
				return art
			end
		end
	end
	if not uncertain then
		activeEnchantArt[slotKey] = nil
	end
	return activeEnchantArt[slotKey]
end

-- Number of item-enchantment buttons the native container shows: it asks
-- C_PaperDollInfo.GetTemporaryEnchantmentInfo per slot (temporary enchants only;
-- permanent enchants never get a button). A secret result still means "present".
function Merlin.GetActiveEnchantCount()
	local slotMap = AuraContainerItemEnchantmentToInventorySlot
	local query = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
	if not (slotMap and query) then
		return 0
	end
	local n = 0
	for _, invSlot in pairs(slotMap) do
		local ok, info = pcall(query, invSlot)
		if ok and ((issecretvalue and issecretvalue(info)) or info ~= nil) then
			n = n + 1
		end
	end
	return n
end

local function IsEnchantModeActive(mode)
	local db = Merlin.db
	if not (db and db.enchants and db.enchants.showWeaponEnchants) then
		return false
	end
	if mode == "attached" then
		return db.buffs.enabled and not db.enchants.detachEnchants
	elseif mode == "grouped" then
		return db.enchants.detachEnchants and db.enchants.grouped
	elseif mode == "solo" then
		return db.enchants.detachEnchants and not db.enchants.grouped
	end
	return false
end

local function SyncEnchantTexCoord(entry)
	if entry.skin and not Merlin.IsRestricted() and Merlin.CanAccessObject(entry.icon) then
		local ulx, uly, llx, lly, urx, ury, lrx, lry = entry.icon:GetTexCoord()
		if ulx and lry then
			entry.enchantIcon:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
			return
		end
	end
	Merlin.ApplyIconTexCoord(entry.enchantIcon)
end

local function ApplyEnchantIcon(entry)
	if not (entry.enchantOverlay and entry.enchantIcon and entry.enchantSlot) then
		return
	end
	if not Merlin.CanAccessObject(entry.enchantOverlay) or not Merlin.CanAccessObject(entry.enchantIcon) then
		return
	end
	if Merlin.CanAccessObject(entry.button) then
		local shown = entry.button:IsShown()
		if (not canaccessvalue or canaccessvalue(shown)) and shown == false then
			entry.enchantOverlay:Hide()
			return
		end
	end
	local useEnchant = Merlin.db and Merlin.db.enchants and Merlin.db.enchants.useEnchantIcon
	local art = (useEnchant and IsEnchantModeActive(entry.enchantMode)) and activeEnchantArt[entry.enchantSlot] or nil
	if art then
		entry.enchantIcon:SetTexture(art)
		SyncEnchantTexCoord(entry)
		local alpha = Merlin.GetCurrentCombatAlpha and Merlin.GetCurrentCombatAlpha() or 1
		entry.enchantOverlay:SetAlpha(alpha)
		entry.enchantOverlay:Show()
	else
		entry.enchantOverlay:Hide()
	end
end

function Merlin.SetEnchantOverlayAlpha(alpha)
	for _, entry in ipairs(styledButtons) do
		if entry.enchantOverlay and Merlin.CanAccessObject(entry.enchantOverlay) then
			entry.enchantOverlay:SetAlpha(alpha)
		end
	end
end

function Merlin.RefreshEnchantIcons()
	local enchCfg = Merlin.db and Merlin.db.enchants
	if not (enchCfg and enchCfg.showWeaponEnchants and enchCfg.useEnchantIcon) then
		for _, entry in ipairs(styledButtons) do
			if entry.enchantOverlay and Merlin.CanAccessObject(entry.enchantOverlay) then
				entry.enchantOverlay:Hide()
			end
		end
		return
	end
	for slotKey in pairs(WEAPON_SLOTS) do
		QueryEnchantArt(slotKey)
	end
	for _, entry in ipairs(styledButtons) do
		if entry.enchantOverlay then
			ApplyEnchantIcon(entry)
		end
	end
end

local function SyncDebuffDispelTextures(entry, cfg)
	local masqueBorder = entry.skin and entry.skin.border or nil
	if not (entry.kind == "debuff" and PRESERVE_ASSET and (masqueBorder or entry.border)) then
		return
	end
	local dMap, dSig = EnsureDispelColorMap()
	local badgeOpts, badgeKey = GetDispelIconOptions(cfg)
	dSig = dSig .. "|" .. badgeKey
	local sig = masqueBorder
		and (dSig .. "|masque")
		or (dSig .. "|" .. tostring(entry.border.activeKey) .. "|" .. tostring(Merlin.db.borderSize)
			.. "|" .. tostring(cfg.size))
	if entry.dispelSig == sig then
		return
	end
	if Merlin.IsRestricted() or not Merlin.CanAccessObject(entry.button) then
		return
	end
	if masqueBorder and not Merlin.CanAccessObject(masqueBorder) then
		return
	end
	if entry.dispelRegistered then
		if not entry.button.ClearDispelTypeTextures then
			return
		end
		local cleared = pcall(entry.button.ClearDispelTypeTextures, entry.button)
		if not cleared then
			return
		end
		entry.dispelRegistered = false
		entry.dispelSig = nil
	end
	local dispelOptions = {
		style = PRESERVE_ASSET,
		showWhenHarmful = true,
		showWhenHelpful = false,
		showWithoutDispelType = true,
		customDispelColorMap = dMap,
	}
	local added = true
	if masqueBorder then
		if not pcall(entry.button.AddDispelTypeTexture, entry.button, masqueBorder, dispelOptions) then
			added = false
		end
	else
		for _, tex in ipairs(entry.border.active) do
			if not pcall(entry.button.AddDispelTypeTexture, entry.button, tex, dispelOptions) then
				added = false
				break
			end
		end
	end
	if added and entry.dispelBadge and badgeOpts then
		if not pcall(entry.button.AddDispelTypeTexture, entry.button, entry.dispelBadge, badgeOpts) then
			added = false
		end
	end
	if added then
		entry.dispelRegistered = true
		entry.dispelSig = sig
	else
		if entry.button.ClearDispelTypeTextures then
			pcall(entry.button.ClearDispelTypeTextures, entry.button)
		end
		entry.dispelRegistered = false
		entry.dispelSig = nil
	end
end

local function ApplyButtonDisplay(entry, cfg)
	local db = Merlin.db
	local font = Merlin.GetFontPath(cfg.fontName)
	local outline = cfg.fontOutline

	if entry.duration and Merlin.CanAccessObject(entry.duration) then
		SafeSetFont(entry.duration, font, cfg.durationFontSize, outline)
		Merlin.PositionDurationText(entry.duration, entry.button, cfg)
		entry.duration:SetAlpha(cfg.showDuration and 1 or 0)
		if not cfg.colorDurationByTime then
			entry.duration:SetTextColor(1, 1, 1, 1)
		end
	end
	if entry.count and Merlin.CanAccessObject(entry.count) then
		SafeSetFont(entry.count, font, cfg.countFontSize, outline)
		Merlin.PositionCountText(entry.count, entry.button, cfg)
		entry.count:SetAlpha(cfg.showCount and 1 or 0)
	end
	if entry.cooldown and Merlin.CanAccessObject(entry.cooldown) then
		entry.cooldown:SetDrawSwipe(cfg.showCooldownSwipe)
		entry.cooldown:SetReverse(cfg.reverseCooldownSwipe)
	end
	if entry.dispelHost and Merlin.CanAccessObject(entry.dispelHost) then
		entry.dispelHost:SetShown(cfg.showDispelIcon == true)
		if entry.dispelBadge and Merlin.CanAccessObject(entry.dispelBadge) then
			PositionDispelBadge(entry.dispelBadge, entry.button, cfg)
		end
	end

	SyncDebuffDispelTextures(entry, cfg)

	local _, cSig = EnsureDurationColorCurve()
	local sig = cfg.durationFormat .. ":" .. tostring(cfg.showDecimals)
		.. ":" .. tostring(db.durationRounding)
		.. ":" .. tostring(cfg.colorDurationByTime) .. ":" .. cSig
	if entry.durationSig ~= sig and not Merlin.IsRestricted()
		and Merlin.CanAccessObject(entry.button) and Merlin.CanAccessObject(entry.duration)
	then
		entry.durationSig = sig
		entry.button:SetDurationText(entry.duration, BuildDurationOptions(cfg))
	end
end

-- Public initializer passed to CustomAuraContainer's initializeFrame callback.
-- kind: "buff" | "debuff" | "enchant" | "enchant_detached" | "external"
local function GetGroupConfig(kind)
	if kind == "debuff" then
		return Merlin.db.debuffs
	elseif kind == "external" then
		return Merlin.db.externals
	elseif kind == "enchant" or kind == "enchant_detached" then
		return Merlin.GetEnchantStyleConfig()
	end
	return Merlin.db.buffs
end

function Merlin.InitializeAuraButton(kind, button, enchantSlot, enchantMode)
	local db = Merlin.db
	local cfg = GetGroupConfig(kind)
	local width, height = Merlin.GetIconDimensions(cfg)

	button:SetSize(width, height)
	button:EnableMouse(true)
	button:SetTooltipAnchorPoint(db.tooltipAnchor, 0, -2)
	button:SetHideTooltipInCombat(db.hideTooltipInCombat)

	if kind == "buff" or kind == "enchant" or kind == "enchant_detached" then
		button:SetCancelAuraButtons(db.allowCancel and "RightButtonUp" or nil)
	end

	local masqueGroupName = (kind == "debuff") and "Debuffs"
		or (kind == "external" and "External Defensives"
			or ((kind == "enchant" or kind == "enchant_detached") and "Weapon Enchants" or "Buffs"))
	local masqueGroup = GetMasqueGroup(masqueGroupName)

	local host = CreateFrame("Frame", nil, button)
	host:SetSize(width, height)
	host:SetPoint("CENTER", button, "CENTER")

	local cooldown = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
	cooldown:SetAllPoints(host)
	cooldown:SetReverse(cfg.reverseCooldownSwipe)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	cooldown:SetDrawSwipe(cfg.showCooldownSwipe)

	local icon = host:CreateTexture(nil, "BORDER")
	icon:SetAllPoints(host)
	Merlin.ApplyIconTexCoord(icon)

	local skin
	if masqueGroup and not (masqueGroup.db and masqueGroup.db.Disabled) then
		local masqueBorder
		if kind == "debuff" or kind == "enchant" or kind == "enchant_detached" or kind == "external" then
			masqueBorder = host:CreateTexture(nil, "OVERLAY")
			masqueBorder:SetAllPoints(host)
		end
		skin = {
			host = host,
			button = button,
			group = masqueGroup,
			icon = icon,
			cooldown = cooldown,
			border = masqueBorder,
			kind = kind,
			width = width,
			height = height,
			dirty = true,
		}
		host.GetSize = function()
			return skin.width, skin.height
		end
		masqueSkins[#masqueSkins + 1] = skin
		masqueSkinByHost[host] = skin
		local groupList = masqueSkinsByGroup[masqueGroup]
		groupList[#groupList + 1] = skin

		if Merlin.CanAccessObject(button) and Merlin.CanAccessObject(host)
			and Merlin.CanAccessObject(icon) and Merlin.CanAccessObject(cooldown)
			and (not masqueBorder or Merlin.CanAccessObject(masqueBorder))
		then
			ApplyMasqueSkin(skin, width, height)
		end
	end

	-- Addon-owned overlay on UIParent anchored to icon BEFORE native adoption,
	-- so updating the enchant texture never touches restricted CustomAuraButton descendants.
	local enchantOverlay, enchantIcon
	if (kind == "enchant" or kind == "enchant_detached") and enchantSlot then
		enchantOverlay = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
		enchantOverlay:SetFrameStrata(button:GetFrameStrata() or "LOW")
		enchantOverlay:SetFrameLevel(host:GetFrameLevel() + 1)
		enchantOverlay:SetAllPoints(icon)
		enchantOverlay:EnableMouse(false)
		enchantIcon = enchantOverlay:CreateTexture(nil, "ARTWORK")
		enchantIcon:SetAllPoints(enchantOverlay)
		if skin and Merlin.CanAccessObject(icon) then
			local ulx, uly, llx, lly, urx, ury, lrx, lry = icon:GetTexCoord()
			if ulx and lry then
				enchantIcon:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
			else
				Merlin.ApplyIconTexCoord(enchantIcon)
			end
		else
			Merlin.ApplyIconTexCoord(enchantIcon)
		end
		enchantOverlay:Hide()
		cooldown:SetFrameLevel(host:GetFrameLevel() + 2)
	end

	-- Adopt icon & cooldown natively AFTER Masque registration
	button:SetDurationCooldown(cooldown)
	button:SetIcon(icon)

	local borderLevel = cooldown:GetFrameLevel() + 1
	local borderHolder
	local dispelHost
	local dispelBadge
	if kind == "debuff" then
		if not skin then
			borderHolder = CreateBorderEdges(host, borderLevel, 1, 1, 1, 1)
			UpdateBorderVisuals(borderHolder, nil, nil, width, height)
		end
		if DISPEL_ICON_STYLE then
			dispelHost = CreateFrame("Frame", nil, button)
			dispelHost:SetAllPoints(button)
			dispelHost:SetFrameLevel(borderLevel + 2)
			dispelBadge = dispelHost:CreateTexture(nil, "OVERLAY", nil, 2)
			PositionDispelBadge(dispelBadge, button, cfg)
			dispelHost:SetShown(cfg.showDispelIcon == true)
		end
	elseif not skin then
		local c = GetStaticBorderColor(kind)
		borderHolder = CreateBorderEdges(host, borderLevel, c[1], c[2], c[3], 1)
		UpdateBorderVisuals(borderHolder, c, nil, width, height)
	end

	local textParent = CreateFrame("Frame", nil, button)
	textParent:SetAllPoints(button)
	textParent:SetFrameLevel(borderLevel + 1)

	local font = Merlin.GetFontPath(cfg.fontName)
	local count = textParent:CreateFontString(nil, "OVERLAY")
	SafeSetFont(count, font, cfg.countFontSize, cfg.fontOutline)
	count:SetWordWrap(false)
	count:SetTextColor(1, 0.92, 0.3, 1)
	button:SetApplicationCount(count)

	local duration = textParent:CreateFontString(nil, "OVERLAY")
	SafeSetFont(duration, font, cfg.durationFontSize, cfg.fontOutline)
	duration:SetWordWrap(false)

	local entry = {
		button = button,
		host = host,
		icon = icon,
		enchantOverlay = enchantOverlay,
		enchantIcon = enchantIcon,
		enchantSlot = enchantSlot,
		enchantMode = enchantMode,
		kind = kind,
		skin = skin,
		border = borderHolder,
		dispelHost = dispelHost,
		dispelBadge = dispelBadge,
		dispelRegistered = false,
		dispelSig = nil,
		cooldown = cooldown,
		count = count,
		duration = duration,
		durationSig = nil,
	}
	styledButtons[#styledButtons + 1] = entry
	if enchantSlot then
		if db.enchants.showWeaponEnchants and db.enchants.useEnchantIcon then
			QueryEnchantArt(enchantSlot)
		end
		ApplyEnchantIcon(entry)
	end
	ApplyButtonDisplay(entry, cfg)
end

function Merlin.MarkMasqueDirty()
	for _, skin in ipairs(masqueSkins) do
		skin.dirty = true
	end
end

function Merlin.RefreshStyles()
	local db = Merlin.db
	local px = Merlin.GetPixelSize(UIParent)
	for _, entry in ipairs(styledButtons) do
		local cfg = GetGroupConfig(entry.kind)
		local width, height = Merlin.GetIconDimensions(cfg)

		if Merlin.CanAccessObject(entry.button) then
			entry.button:SetSize(width, height)
			entry.button:SetTooltipAnchorPoint(db.tooltipAnchor, 0, -2)
			entry.button:SetHideTooltipInCombat(db.hideTooltipInCombat)
			if entry.kind == "buff" or entry.kind == "enchant" or entry.kind == "enchant_detached" then
				entry.button:SetCancelAuraButtons(db.allowCancel and "RightButtonUp" or nil)
			end
		end
		if Merlin.CanAccessObject(entry.host) then
			entry.host:SetSize(width, height)
		end
		if not entry.skin and entry.icon and Merlin.CanAccessObject(entry.icon) then
			Merlin.ApplyIconTexCoord(entry.icon)
		end
		if entry.border then
			local staticColor = (entry.kind ~= "debuff") and GetStaticBorderColor(entry.kind) or nil
			UpdateBorderVisuals(entry.border, staticColor, px, width, height)
		end
		if entry.skin then
			if width ~= entry.skin.width or height ~= entry.skin.height then
				entry.skin.dirty = true
			end
			if entry.skin.dirty and not Merlin.IsRestricted()
				and Merlin.CanAccessObject(entry.button)
				and Merlin.CanAccessObject(entry.host)
				and Merlin.CanAccessObject(entry.skin.icon)
				and Merlin.CanAccessObject(entry.skin.cooldown)
				and (not entry.skin.border or Merlin.CanAccessObject(entry.skin.border))
			then
				ApplyMasqueSkin(entry.skin, width, height)
				if entry.kind == "debuff" and not entry.skin.blocked then
					entry.dispelSig = nil
				end
			elseif entry.skin.needsPostSync then
				entry.skin.needsPostSync = false
				if entry.kind == "debuff" then
					entry.dispelSig = nil
				else
					ApplyMasqueBorderColor(entry.skin)
				end
			else
				ApplyMasqueBorderColor(entry.skin)
			end
		end
		ApplyButtonDisplay(entry, cfg)
		if entry.enchantOverlay then
			ApplyEnchantIcon(entry)
		end
	end
end

function Merlin.InitStyle()
	EnsureDurationColorCurve()
	Merlin.RegisterRefresh(Merlin.RefreshStyles)
end
