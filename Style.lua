local _, Merlin = ...

local ROUND_DOWN = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
local PRESERVE_ASSET = Enum.CustomAuraButtonDispelTypeTextureStyle
	and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
local DISPEL_ICON_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle
	and Enum.CustomAuraButtonDispelTypeTextureStyle.Icon
local DURATION_PROP_REMAINING = Enum.DurationTextBindingProperty
	and Enum.DurationTextBindingProperty.RemainingDuration

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

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

local smartFormatter, smartDecFormatter
local compactFormatter, compactDecFormatter
local durationColorCurve
local curveSig = ""

local masqueGroups = {}
local masqueSkins = {}
local masqueSkinByHost = {}
local masqueSkinsByGroup = {}
local styledButtons = {}

-- Duration formatters & expire color curve (native FOREVER objects)

local function BuildSmartFormatter(withDecimals)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and ROUND_DOWN) then
		return nil
	end
	local rules = {}
	if withDecimals then
		rules[#rules + 1] = { threshold = 0, step = 0.1, rounding = ROUND_DOWN, format = "%.1f" }
		rules[#rules + 1] = { threshold = 10, step = 1, rounding = ROUND_DOWN, format = "%d" }
	else
		rules[#rules + 1] = { threshold = 0, step = 1, rounding = ROUND_DOWN, format = "%d" }
	end
	rules[#rules + 1] = {
		threshold = SECONDS_PER_MIN,
		format = "%d:%02d",
		components = {
			{ div = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN },
			{ mod = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN },
		},
	}
	rules[#rules + 1] = {
		threshold = 5 * SECONDS_PER_MIN,
		format = "%dm",
		components = { { div = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN } },
	}
	rules[#rules + 1] = {
		threshold = SECONDS_PER_HOUR,
		format = "%dh",
		components = { { div = SECONDS_PER_HOUR, step = 1, rounding = ROUND_DOWN } },
	}
	rules[#rules + 1] = {
		threshold = SECONDS_PER_DAY,
		format = "%dd",
		components = { { div = SECONDS_PER_DAY, step = 1, rounding = ROUND_DOWN } },
	}
	local formatter = C_StringUtil.CreateNumericRuleFormatter()
	formatter:SetBreakpoints(rules)
	return formatter
end

local function BuildCompactFormatter(withDecimals)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and ROUND_DOWN) then
		return nil
	end
	local rules = {}
	if withDecimals then
		rules[#rules + 1] = { threshold = 0, step = 0.1, rounding = ROUND_DOWN, format = "%.1fs" }
		rules[#rules + 1] = { threshold = 10, step = 1, rounding = ROUND_DOWN, format = "%ds" }
	else
		rules[#rules + 1] = { threshold = 0, step = 1, rounding = ROUND_DOWN, format = "%ds" }
	end
	rules[#rules + 1] = {
		threshold = SECONDS_PER_MIN,
		format = "%dm",
		components = { { div = SECONDS_PER_MIN, step = 1, rounding = ROUND_DOWN } },
	}
	rules[#rules + 1] = {
		threshold = SECONDS_PER_HOUR,
		format = "%dh",
		components = { { div = SECONDS_PER_HOUR, step = 1, rounding = ROUND_DOWN } },
	}
	rules[#rules + 1] = {
		threshold = SECONDS_PER_DAY,
		format = "%dd",
		components = { { div = SECONDS_PER_DAY, step = 1, rounding = ROUND_DOWN } },
	}
	local formatter = C_StringUtil.CreateNumericRuleFormatter()
	formatter:SetBreakpoints(rules)
	return formatter
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
		curve:AddPoint(db.urgentThreshold + 1, CreateColor(w[1], w[2], w[3], 1))
		curve:AddPoint(warnAt + 1, CreateColor(1.0, 1.0, 1.0, 1))
		durationColorCurve = curve
	end
	return durationColorCurve, curveSig
end

local function BuildDurationOptions(cfg)
	local opts = {}
	if cfg.durationFormat == "SMART" then
		local fmt = cfg.showDecimals and smartDecFormatter or smartFormatter
		if fmt then
			opts.textFormatter = fmt
		end
	elseif cfg.durationFormat == "COMPACT" then
		local fmt = cfg.showDecimals and compactDecFormatter or compactFormatter
		if fmt then
			opts.textFormatter = fmt
		end
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
			if targeted and targeted.group == group and targeted.registered then
				if not targeted.applying then
					targeted.dirty = true
					Merlin.RequestRefresh()
				end
				return
			end
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

		if group.RegisterCallback then
			group:RegisterCallback(function()
				local dirty
				for _, skin in ipairs(masqueSkinsByGroup[group]) do
					skin.dirty = true
					dirty = true
				end
				if dirty then
					Merlin.RequestRefresh()
				end
			end)
		end
	end
	return masqueGroups[groupName]
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
			group:AddButton(skin.host, {
				Icon = skin.icon,
				Cooldown = skin.cooldown,
				Count = false,
				Duration = false,
			}, "Aura", true)
			skin.registered = true
		end
		if group.SetFrameSize then
			group:SetFrameSize(width, height, skin.host, false, true)
		end
		if wasRegistered then
			group:ReSkin(skin.host)
		end
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
	end
end

-- Crisp N-pixel 4-strip border (used when Masque is absent or disabled)

local function CreateBorderEdges(parent, frameLevel, r, g, b, a)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	holder:SetFrameLevel(frameLevel)

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
	return holder
end

local function UpdateBorderVisuals(holder, color)
	if not holder or not holder.edges then
		return
	end
	local sizePx = Merlin.db and Merlin.db.borderSize or 1
	if sizePx <= 0 then
		holder:Hide()
		return
	end
	holder:Show()
	local px = Merlin.GetPixelSize(holder) * sizePx
	holder.edges[1]:SetHeight(px)
	holder.edges[2]:SetHeight(px)
	holder.edges[3]:SetWidth(px)
	holder.edges[4]:SetWidth(px)
	if color then
		for _, edge in ipairs(holder.edges) do
			edge:SetVertexColor(color[1], color[2], color[3], 1)
		end
	end
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

local function ApplyButtonDisplay(entry, cfg)
	local db = Merlin.db
	local font = Merlin.GetFontPath()
	local outline = db.fontOutline

	if entry.duration and Merlin.CanAccessObject(entry.duration) then
		entry.duration:SetFont(font, cfg.durationFontSize, outline)
		Merlin.PositionDurationText(entry.duration, entry.button, cfg)
		entry.duration:SetAlpha(cfg.showDuration and 1 or 0)
		if not cfg.colorDurationByTime then
			entry.duration:SetTextColor(1, 1, 1, 1)
		end
	end
	if entry.count and Merlin.CanAccessObject(entry.count) then
		entry.count:SetFont(font, cfg.countFontSize, outline)
		Merlin.PositionCountText(entry.count, entry.button, cfg)
		entry.count:SetAlpha(cfg.showCount and 1 or 0)
	end
	if entry.cooldown and Merlin.CanAccessObject(entry.cooldown) then
		entry.cooldown:SetDrawSwipe(cfg.showCooldownSwipe)
		entry.cooldown:SetReverse(cfg.reverseCooldownSwipe)
	end
	if entry.dispelHost and Merlin.CanAccessObject(entry.dispelHost) then
		entry.dispelHost:SetShown(cfg.showDispelIcon == true)
	end

	if entry.kind == "debuff" and PRESERVE_ASSET and entry.border and not InCombatLockdown()
		and Merlin.CanAccessObject(entry.button)
	then
		local dMap, dSig = EnsureDispelColorMap()
		if entry.dispelSig ~= dSig then
			entry.dispelSig = dSig
			local dispelOptions = {
				style = PRESERVE_ASSET,
				showWhenHarmful = true,
				showWhenHelpful = false,
				showWithoutDispelType = true,
				customDispelColorMap = dMap,
			}
			for _, edge in ipairs(entry.border.edges) do
				entry.button:AddDispelTypeTexture(edge, dispelOptions)
			end
		end
	end

	local _, cSig = EnsureDurationColorCurve()
	local sig = cfg.durationFormat .. ":" .. tostring(cfg.showDecimals)
		.. ":" .. tostring(cfg.colorDurationByTime) .. ":" .. cSig
	if entry.durationSig ~= sig and not InCombatLockdown()
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
	elseif kind == "enchant_detached" then
		return Merlin.GetEnchantStyleConfig()
	end
	return Merlin.db.buffs
end

function Merlin.InitializeAuraButton(kind, button)
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
	Merlin.ApplyIconTexCoord(icon, width, height)

	local skin
	if masqueGroup then
		skin = {
			host = host,
			button = button,
			group = masqueGroup,
			icon = icon,
			cooldown = cooldown,
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
		then
			ApplyMasqueSkin(skin, width, height)
		end
	end

	-- Adopt icon & cooldown natively AFTER Masque registration
	button:SetDurationCooldown(cooldown)
	button:SetIcon(icon)

	local borderLevel = cooldown:GetFrameLevel() + 1
	local borderHolder
	local dispelHost
	local dispelSig
	if kind == "debuff" then
		borderHolder = CreateBorderEdges(host, borderLevel, 1, 1, 1, 1)
		UpdateBorderVisuals(borderHolder)
		if PRESERVE_ASSET then
			local dMap, dSig = EnsureDispelColorMap()
			dispelSig = dSig
			local dispelOptions = {
				style = PRESERVE_ASSET,
				showWhenHarmful = true,
				showWhenHelpful = false,
				showWithoutDispelType = true,
				customDispelColorMap = dMap,
			}
			for _, edge in ipairs(borderHolder.edges) do
				button:AddDispelTypeTexture(edge, dispelOptions)
			end
		end
		if DISPEL_ICON_STYLE then
			dispelHost = CreateFrame("Frame", nil, button)
			dispelHost:SetAllPoints(button)
			dispelHost:SetFrameLevel(borderLevel + 2)
			local badge = dispelHost:CreateTexture(nil, "OVERLAY", nil, 2)
			badge:SetSize(14, 14)
			badge:SetPoint("CENTER", button, "TOPLEFT", 2, -2)
			button:AddDispelTypeTexture(badge, {
				style = DISPEL_ICON_STYLE,
				showWhenHarmful = true,
				showWhenHelpful = false,
			})
			dispelHost:SetShown(cfg.showDispelIcon == true)
		end
	elseif not skin then
		local c = GetStaticBorderColor(kind)
		borderHolder = CreateBorderEdges(host, borderLevel, c[1], c[2], c[3], 1)
		UpdateBorderVisuals(borderHolder, c)
	end

	local textParent = CreateFrame("Frame", nil, button)
	textParent:SetAllPoints(button)
	textParent:SetFrameLevel(borderLevel + 1)

	local count = textParent:CreateFontString(nil, "OVERLAY")
	count:SetFont(Merlin.GetFontPath(), cfg.countFontSize, db.fontOutline)
	count:SetWordWrap(false)
	count:SetTextColor(1, 0.92, 0.3, 1)
	Merlin.PositionCountText(count, button, cfg)
	button:SetApplicationCount(count)

	local duration = textParent:CreateFontString(nil, "OVERLAY")
	duration:SetFont(Merlin.GetFontPath(), cfg.durationFontSize, db.fontOutline)
	duration:SetWordWrap(false)
	Merlin.PositionDurationText(duration, button, cfg)
	button:SetDurationText(duration, BuildDurationOptions(cfg))

	local _, cSig = EnsureDurationColorCurve()
	local entry = {
		button = button,
		host = host,
		icon = icon,
		kind = kind,
		skin = skin,
		border = borderHolder,
		dispelHost = dispelHost,
		dispelSig = dispelSig,
		cooldown = cooldown,
		count = count,
		duration = duration,
		durationSig = cfg.durationFormat .. ":" .. tostring(cfg.showDecimals)
			.. ":" .. tostring(cfg.colorDurationByTime) .. ":" .. cSig,
	}
	styledButtons[#styledButtons + 1] = entry
	ApplyButtonDisplay(entry, cfg)
end

function Merlin.MarkMasqueDirty()
	for _, skin in ipairs(masqueSkins) do
		skin.dirty = true
	end
end

function Merlin.RefreshStyles()
	local db = Merlin.db
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
			Merlin.ApplyIconTexCoord(entry.icon, width, height)
		end
		if entry.border then
			local staticColor = (entry.kind ~= "debuff") and GetStaticBorderColor(entry.kind) or nil
			UpdateBorderVisuals(entry.border, staticColor)
		end
		if entry.skin then
			if width ~= entry.skin.width or height ~= entry.skin.height then
				entry.skin.dirty = true
			end
			if entry.skin.dirty and not InCombatLockdown()
				and Merlin.CanAccessObject(entry.button)
				and Merlin.CanAccessObject(entry.host)
				and Merlin.CanAccessObject(entry.skin.icon)
				and Merlin.CanAccessObject(entry.skin.cooldown)
			then
				ApplyMasqueSkin(entry.skin, width, height)
			end
		end
		ApplyButtonDisplay(entry, cfg)
	end
end

function Merlin.InitStyle()
	smartFormatter = BuildSmartFormatter(false)
	smartDecFormatter = BuildSmartFormatter(true)
	compactFormatter = BuildCompactFormatter(false)
	compactDecFormatter = BuildCompactFormatter(true)
	EnsureDurationColorCurve()
	Merlin.RegisterRefresh(Merlin.RefreshStyles)
end
