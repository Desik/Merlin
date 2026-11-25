local _, Merlin = ...

local SORT_METHOD_MAP = {
	DEFAULT = AuraContainerSortMethod and AuraContainerSortMethod.Default or 0,
	EXPIRATION = AuraContainerSortMethod and AuraContainerSortMethod.ExpirationOnly or 5,
	NAME = AuraContainerSortMethod and AuraContainerSortMethod.NameOnly or 7,
	INDEX = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly or 8,
}

local SORT_DIR_MAP = {
	NORMAL = AuraContainerSortDirection and AuraContainerSortDirection.Normal or 0,
	REVERSE = AuraContainerSortDirection and AuraContainerSortDirection.Reverse or 1,
}

local ENCHANT_SLOTS = AuraContainerItemEnchantmentSlot and {
	AuraContainerItemEnchantmentSlot.MainHand,
	AuraContainerItemEnchantmentSlot.OffHand,
	AuraContainerItemEnchantmentSlot.Ranged,
} or {}

local BUFF_OUTLINE_COLOR = { 169 / 255, 191 / 255, 170 / 255, 0.85 } -- Vigil sage accent
local DEBUFF_OUTLINE_COLOR = { 216 / 255, 142 / 255, 131 / 255, 0.85 } -- Vigil danger muted red
local EXTERNAL_OUTLINE_COLOR = { 229 / 255, 182 / 255, 99 / 255, 0.85 } -- Vigil warning warm gold
local ENCHANT_OUTLINE_COLOR = { 176 / 255, 118 / 255, 240 / 255, 0.85 } -- Enchant purple
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function SafeSetFont(fs, path, size, outline)
	if not fs:SetFont(path, size, outline) then
		fs:SetFont(DEFAULT_FONT, size, outline)
	end
end

local SAMPLE_DURATIONS = {
	SMART = { "2h", "4:15", "28", "4" },
	COMPACT = { "2h", "12m", "28s", "4s" },
	DETAILED = { "1h 59m", "4:15", "28", "4" },
	CLOCK = { "1:59", "4:15", "28", "4" },
	DECIMAL = { "2.0h", "4:15", "28", "4" },
	BLIZZARD = { "2 h", "12 m", "28 s", "4 s" },
}

local buffsAnchor, buffsContainer
local debuffsAnchor, debuffsContainer
local externalsAnchor, externalsContainer
local enchantsAnchor, enchantsContainer
local primaryContainers = {}
local soloEnchantItems = {}
local currentCombatAlpha = 1.0

local SOLO_ENCHANT_DEFS = AuraContainerItemEnchantmentSlot and {
	{ key = "mh", slot = AuraContainerItemEnchantmentSlot.MainHand, name = "MH", label = "MH" },
	{ key = "oh", slot = AuraContainerItemEnchantmentSlot.OffHand, name = "OH", label = "OH" },
	{ key = "ranged", slot = AuraContainerItemEnchantmentSlot.Ranged, name = "Ranged", label = "Ranged" },
} or {}

local function ResolveAnchorTarget(cfg)
	if cfg.anchorTo == "MINIMAP" and Minimap then
		return Minimap, "TOPRIGHT", "TOPLEFT"
	elseif cfg.anchorTo == "BUFFS" and buffsAnchor then
		return buffsAnchor, "TOPRIGHT", "BOTTOMRIGHT"
	end
	return UIParent, "TOPRIGHT", "TOPRIGHT"
end

local function ApplyAnchorPosition(anchor, cfg, posTable)
	local relFrame, point, relPoint = ResolveAnchorTarget(cfg)
	local pos = posTable or cfg
	anchor:ClearAllPoints()
	anchor:SetPoint(point, relFrame, relPoint, pos.x, pos.y)
end

local function GetAnchorPoint(cfg)
	local vert = (cfg.growthY == "UP") and "BOTTOM" or "TOP"
	local horiz = (cfg.growthX == "RIGHT") and "LEFT" or "RIGHT"
	return vert .. horiz
end

local function GetFlowDirections(cfg)
	local dir = AnchorUtil and AnchorUtil.FlowDirection
	local hx = (cfg.growthX == "RIGHT") and (dir and dir.Right or 1) or (dir and dir.Left or -1)
	local vy = (cfg.growthY == "UP") and (dir and dir.Up or 1) or (dir and dir.Down or -1)
	return hx, vy
end

local function ComputeMaxLineSize(cfg, style)
	local s = style or cfg
	local w, h = Merlin.GetIconDimensions(s)
	if cfg.orientation == "VERTICAL" then
		return cfg.perRow * h + math.max(0, cfg.perRow - 1) * s.spacingY + 0.5
	end
	return cfg.perRow * w + math.max(0, cfg.perRow - 1) * s.spacingX + 0.5
end

-- Placeholder / mover grid showing actual icon outlines, growth, spacing,
-- and live sample timer + stack text positioning.

local function CreateSlotOutline(parent)
	local slot = CreateFrame("Frame", nil, parent)
	slot:EnableMouse(false)

	local bg = slot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)
	slot.bg = bg

	local top = slot:CreateTexture(nil, "BORDER")
	local bottom = slot:CreateTexture(nil, "BORDER")
	local left = slot:CreateTexture(nil, "BORDER")
	local right = slot:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")

	local edges = { top, bottom, left, right }
	for _, edge in ipairs(edges) do
		edge:SetTexture(WHITE)
	end
	slot.edges = edges

	slot.duration = slot:CreateFontString(nil, "OVERLAY")
	slot.duration:SetWordWrap(false)

	slot.count = slot:CreateFontString(nil, "OVERLAY")
	slot.count:SetWordWrap(false)
	slot.count:SetTextColor(1, 0.92, 0.3, 1)

	return slot
end

local function SizeAnchor(anchor, cfg, overrideCount, styleCfg)
	local style = styleCfg or cfg
	local iconW, iconH = Merlin.GetIconDimensions(style)
	local count = overrideCount or math.min(cfg.maxIcons, cfg.perRow * 2)
	local perLine = overrideCount and 1 or cfg.perRow
	local isVertical = (cfg.orientation == "VERTICAL") and not overrideCount
	local cols = isVertical and math.max(1, math.ceil(count / perLine)) or math.min(count, perLine)
	local rows = isVertical and math.min(count, perLine) or math.max(1, math.ceil(count / perLine))
	local totalW = cols * iconW + math.max(0, cols - 1) * style.spacingX
	local totalH = rows * iconH + math.max(0, rows - 1) * style.spacingY
	anchor:SetSize(math.max(totalW, 32), math.max(totalH, 24))
	return iconW, iconH
end

-- One placeholder layout group, carrying the same spacing the container receives.
local function MoverGroup(cfg, style, count, color, samples)
	local isVert = (cfg.orientation == "VERTICAL")
	local w, h = Merlin.GetIconDimensions(style)
	local elem = isVert and style.spacingY or style.spacingX
	local line = isVert and style.spacingX or style.spacingY
	return {
		count = count,
		w = w,
		h = h,
		elementSpacing = elem,
		lineSpacing = line,
		groupSpacing = elem,
		groupLineSpacing = line,
		style = style,
		color = color,
		samples = samples,
	}
end

-- Placeholder groups in native order: attached enchants (active slots only)
-- share the Buffs line before or after the aura group.
local function BuildMoverGroups(cfg, style, borderColor, isBuff, isEnchantGroup)
	if isEnchantGroup then
		return { MoverGroup(cfg, style, math.max(1, #SOLO_ENCHANT_DEFS), ENCHANT_OUTLINE_COLOR, false) }
	end
	local auras = MoverGroup(cfg, style, math.min(cfg.maxIcons, cfg.perRow * 2), borderColor, true)
	local enchCfg = Merlin.db.enchants
	if not (isBuff and cfg.enabled and enchCfg.showWeaponEnchants and not enchCfg.detachEnchants
		and #ENCHANT_SLOTS > 0 and Merlin.GetActiveEnchantCount)
	then
		return { auras }
	end
	local n = Merlin.GetActiveEnchantCount()
	if n <= 0 then
		return { auras }
	end
	local ench = MoverGroup(cfg, Merlin.GetEnchantStyleConfig(), n, ENCHANT_OUTLINE_COLOR, false)
	ench.groupSpacing, ench.groupLineSpacing = auras.elementSpacing, auras.lineSpacing
	if enchCfg.enchantPlacement == "AFTER" then
		return { auras, ench }
	end
	return { ench, auras }
end

-- Follows the native flow layout rules (AnchorUtil.ApplyFlowLayout, Forever
-- 1.60.1): wrap when a line exceeds maxLine, group spacing between non-empty
-- groups, offsets measured from the shared anchor point.
local function FlowMoverSlots(cfg, maxLine, groups)
	local isVert = (cfg.orientation == "VERTICAL")
	local xDir = (cfg.growthX == "RIGHT") and 1 or -1
	local yDir = (cfg.growthY == "UP") and 1 or -1
	local pDir = isVert and yDir or xDir
	local cDir = isVert and xDir or yDir
	local cursorP, cursorC, lineP, lineC = 0, 0, 0, 0
	local placed = false
	local out, boundsW, boundsH = {}, 0, 0

	local function NextLine(gap)
		cursorP = 0
		cursorC = cursorC + (lineC + gap) * cDir
		lineP, lineC = 0, 0
	end

	for _, g in ipairs(groups) do
		if g.count > 0 then
			if placed and g.groupSpacing > 0 then
				if lineP > 0 and lineP + g.groupSpacing > maxLine then
					NextLine(g.groupLineSpacing)
				else
					cursorP = cursorP + g.groupSpacing * pDir
					lineP = lineP + g.groupSpacing
				end
			end
			local pSize = isVert and g.h or g.w
			local cSize = isVert and g.w or g.h
			for i = 1, g.count do
				local nextP = (lineP > 0) and (lineP + pSize) or pSize
				if lineP > 0 and nextP > maxLine then
					NextLine(g.lineSpacing)
					nextP = pSize
				end
				local x = isVert and cursorC or cursorP
				local y = isVert and cursorP or cursorC
				out[#out + 1] = { x = x, y = y, group = g, index = i }
				boundsW = math.max(boundsW, math.abs(x) + g.w)
				boundsH = math.max(boundsH, math.abs(y) + g.h)
				cursorP = cursorP + (pSize + g.elementSpacing) * pDir
				lineP = nextP + g.elementSpacing
				lineC = math.max(lineC, cSize)
				placed = true
			end
		end
	end
	return out, boundsW, boundsH
end

local function LayoutMoverSlots(anchor, cfg, groups, maxLine)
	local mover = anchor.mover
	if not mover then
		return
	end
	local point = GetAnchorPoint(cfg)
	local placed, boundsW, boundsH = FlowMoverSlots(cfg, maxLine, groups)

	-- Mover covers every placeholder (attached enchants may add a line) while the
	-- anchor keeps its stable size for groups anchored to it.
	mover:ClearAllPoints()
	mover:SetPoint(point, anchor, point, 0, 0)
	mover:SetSize(math.max(anchor:GetWidth(), boundsW), math.max(anchor:GetHeight(), boundsH))

	local px = Merlin.GetPixelSize(UIParent)
	local uCol = Merlin.db.colors.timerUrgent
	local wCol = Merlin.db.colors.timerWarn

	for i, info in ipairs(placed) do
		local g = info.group
		local style = g.style
		local slot = mover.slots[i]
		if not slot then
			slot = CreateSlotOutline(mover)
			mover.slots[i] = slot
		end

		slot:SetSize(g.w, g.h)
		slot:ClearAllPoints()
		slot:SetPoint(point, mover, point, info.x, info.y)

		slot.edges[1]:SetHeight(px)
		slot.edges[2]:SetHeight(px)
		slot.edges[3]:SetWidth(px)
		slot.edges[4]:SetWidth(px)
		local c = g.color
		for _, edge in ipairs(slot.edges) do
			edge:SetVertexColor(c[1], c[2], c[3], c[4])
		end

		local font = Merlin.GetFontPath(style.fontName)
		local outline = style.fontOutline
		local idx = info.index

		-- Sample timer and stack text on the first aura slots for live preview
		if g.samples and idx <= 4 and style.showDuration then
			local samples = SAMPLE_DURATIONS[style.durationFormat] or SAMPLE_DURATIONS.SMART
			SafeSetFont(slot.duration, font, style.durationFontSize, outline)
			Merlin.PositionDurationText(slot.duration, slot, style)
			local txt = samples[idx]
			if idx == 4 and style.showDecimals and style.durationFormat ~= "BLIZZARD" then
				txt = (style.durationFormat == "COMPACT") and "4.2s" or "4.2"
			end
			slot.duration:SetText(txt)
			if style.colorDurationByTime and idx == 4 then
				slot.duration:SetTextColor(uCol[1], uCol[2], uCol[3], 1)
			elseif style.colorDurationByTime and idx == 3 then
				slot.duration:SetTextColor(wCol[1], wCol[2], wCol[3], 1)
			else
				slot.duration:SetTextColor(1.0, 1.0, 1.0, 1)
			end
			slot.duration:Show()
		else
			slot.duration:Hide()
		end

		if g.samples and idx <= 2 and style.showCount then
			SafeSetFont(slot.count, font, style.countFontSize, outline)
			Merlin.PositionCountText(slot.count, slot, style)
			slot.count:SetText(idx == 1 and "3" or "2")
			slot.count:Show()
		else
			slot.count:Hide()
		end

		slot:Show()
	end
	for i = #placed + 1, #mover.slots do
		mover.slots[i]:Hide()
	end
end

local function CreateMoverOverlay(anchor, labelText, cfgKey, borderColor, slotKey)
	local mover = CreateFrame("Frame", nil, anchor)
	mover:SetAllPoints(anchor)
	mover:SetFrameStrata("DIALOG")
	mover:EnableMouse(true)
	mover:SetMovable(true)
	mover:RegisterForDrag("LeftButton")
	mover.slots = {}

	local badge = CreateFrame("Frame", nil, mover)
	badge:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 4)
	badge:SetHeight(18)
	local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
	badgeBg:SetAllPoints()
	badgeBg:SetColorTexture(0, 0, 0, 0.85)
	local accent = badge:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT")
	accent:SetPoint("BOTTOMLEFT")
	accent:SetWidth(2)
	accent:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)

	local label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 7, 0)
	label:SetTextColor(0.9, 0.9, 0.9, 1)
	label:SetText(labelText)
	badge:SetWidth(math.ceil(label:GetStringWidth()) + 14)

	mover:SetScript("OnEnter", function()
		badgeBg:SetColorTexture(0.12, 0.12, 0.12, 0.92)
		for _, slot in ipairs(mover.slots) do
			if slot:IsShown() then
				slot.bg:SetColorTexture(0.12, 0.12, 0.12, 0.65)
			end
		end
	end)
	mover:SetScript("OnLeave", function()
		badgeBg:SetColorTexture(0, 0, 0, 0.85)
		for _, slot in ipairs(mover.slots) do
			if slot:IsShown() then
				slot.bg:SetColorTexture(0, 0, 0, 0.55)
			end
		end
	end)

	mover:SetScript("OnHide", function()
		anchor:StopMovingOrSizing()
	end)
	mover:SetScript("OnDragStart", function()
		if Merlin.IsRestricted() then
			return
		end
		anchor:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		anchor:StopMovingOrSizing()
		if Merlin.IsRestricted() then
			return
		end
		local cfg = Merlin.db[cfgKey]
		local pos = (slotKey and cfg.slots) and cfg.slots[slotKey] or cfg
		local relFrame, _, relPoint = ResolveAnchorTarget(cfg)
		local rightPos = anchor:GetRight()
		local topPos = anchor:GetTop()
		local refX = (relPoint == "TOPLEFT") and relFrame:GetLeft() or relFrame:GetRight()
		local refY = (relPoint == "BOTTOMRIGHT") and relFrame:GetBottom() or relFrame:GetTop()
		local aScale = anchor:GetEffectiveScale()
		local rScale = relFrame:GetEffectiveScale()
		if rightPos and topPos and refX and refY and aScale and rScale and aScale > 0 then
			local ratio = rScale / aScale
			pos.x = math.floor((rightPos - refX * ratio) + 0.5)
			pos.y = math.floor((topPos - refY * ratio) + 0.5)
		end
		ApplyAnchorPosition(anchor, cfg, pos)
		if Merlin.RefreshOptions then
			Merlin.RefreshOptions()
		end
	end)

	mover:Hide()
	anchor.mover = mover
	return mover
end

local function CreateAnchor(name, labelText, cfgKey, borderColor, slotKey)
	local anchor = CreateFrame("Frame", name, UIParent)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	anchor:SetSize(240, 44)
	CreateMoverOverlay(anchor, labelText, cfgKey, borderColor, slotKey)
	return anchor
end

local function ApplyContainerConfig(anchor, container, groupKey, cfg, borderColor, isBuff)
	if not (anchor and container) then
		return
	end
	local style = (not groupKey) and Merlin.GetEnchantStyleConfig() or cfg
	local iconW, iconH = SizeAnchor(anchor, cfg, nil, style)
	if not Merlin.db.locked and not Merlin.IsRestricted() then
		local groups = BuildMoverGroups(cfg, style, borderColor, isBuff, not groupKey)
		LayoutMoverSlots(anchor, cfg, groups, ComputeMaxLineSize(cfg, style))
	end
	ApplyAnchorPosition(anchor, cfg)

	local detachedGrouped = (not groupKey) and (cfg.showWeaponEnchants and cfg.detachEnchants and cfg.grouped)
	local active = groupKey and cfg.enabled or detachedGrouped
	if not active and container._merlinEnabled == false then
		return
	end

	local point = GetAnchorPoint(cfg)
	container:ClearAllPoints()
	container:SetPoint(point, anchor, point, 0, 0)

	local isVert = (cfg.orientation == "VERTICAL")
	if AnchorUtil and AnchorUtil.FlowLayoutAxis then
		local axis = isVert
			and AnchorUtil.FlowLayoutAxis.Vertical
			or AnchorUtil.FlowLayoutAxis.Horizontal
		container:SetFlowLayoutAxis(axis)
	end
	container:SetFlowLayoutAnchorPoint(point)
	local hx, vy = GetFlowDirections(cfg)
	container:SetFlowLayoutGrowthDirection(hx, vy)
	container:SetFlowLayoutMaximumLineSize(ComputeMaxLineSize(cfg, style))

	local elemSpacing = isVert and style.spacingY or style.spacingX
	local lineSpacing = isVert and style.spacingX or style.spacingY
	local layoutOpts = {
		elementSpacing = elemSpacing,
		lineSpacing = lineSpacing,
		groupSpacing = elemSpacing,
		groupLineSpacing = lineSpacing,
		elementWidth = iconW,
		elementHeight = iconH,
	}

	if groupKey then
		container:SetAuraGroupEnabled(groupKey, cfg.enabled)
		container:SetAuraGroupMaxFrameCount(groupKey, cfg.maxIcons)
		container:SetAuraGroupSortMethod(
			groupKey,
			SORT_METHOD_MAP[cfg.sortMethod] or SORT_METHOD_MAP.DEFAULT,
			SORT_DIR_MAP[cfg.sortDirection] or SORT_DIR_MAP.NORMAL
		)
		container:SetAuraGroupLayout(groupKey, layoutOpts)
	end

	if isBuff and #ENCHANT_SLOTS > 0 then
		local enchCfg = Merlin.db.enchants
		local enchStyle = Merlin.GetEnchantStyleConfig()
		local enchW, enchH = Merlin.GetIconDimensions(enchStyle)
		local attached = cfg.enabled and enchCfg.showWeaponEnchants and not enchCfg.detachEnchants
		local placement = (enchCfg.enchantPlacement == "AFTER")
			and CustomAuraContainerItemEnchantmentPlacement.AfterAuraGroups
			or CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups
		container:SetItemEnchantmentLayout({
			placement = placement,
			elementSpacing = isVert and enchStyle.spacingY or enchStyle.spacingX,
			lineSpacing = isVert and enchStyle.spacingX or enchStyle.spacingY,
			groupSpacing = isVert and cfg.spacingY or cfg.spacingX,
			groupLineSpacing = isVert and cfg.spacingX or cfg.spacingY,
			elementWidth = enchW,
			elementHeight = enchH,
		})
		for _, slot in ipairs(ENCHANT_SLOTS) do
			container:SetItemEnchantmentEnabled(slot, attached)
		end
	elseif not groupKey and #ENCHANT_SLOTS > 0 then
		container:SetItemEnchantmentLayout({
			placement = CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups,
			elementSpacing = elemSpacing,
			lineSpacing = lineSpacing,
			groupSpacing = elemSpacing,
			groupLineSpacing = lineSpacing,
			elementWidth = iconW,
			elementHeight = iconH,
		})
		for _, slot in ipairs(ENCHANT_SLOTS) do
			container:SetItemEnchantmentEnabled(slot, detachedGrouped)
		end
		container._merlinEnabled = detachedGrouped
		container:SetEnabled(detachedGrouped)
		container:UpdateAllAuras()
		return
	end

	container._merlinEnabled = cfg.enabled
	container:SetEnabled(cfg.enabled)
	container:UpdateAllAuras()
end

local function ApplySoloEnchants(cfg)
	local style = Merlin.GetEnchantStyleConfig()
	local active = cfg.showWeaponEnchants and cfg.detachEnchants and not cfg.grouped
	local unlocked = not Merlin.db.locked and not Merlin.IsRestricted()
	local point = GetAnchorPoint(cfg)
	local hx, vy = GetFlowDirections(cfg)

	for _, item in ipairs(soloEnchantItems) do
		local pos = cfg.slots[item.key]
		local iconW, iconH = SizeAnchor(item.anchor, cfg, 1, style)
		if unlocked then
			local group = MoverGroup(cfg, style, 1, ENCHANT_OUTLINE_COLOR, false)
			LayoutMoverSlots(item.anchor, cfg, { group }, iconW + 1)
		end
		ApplyAnchorPosition(item.anchor, cfg, pos)

		local c = item.container
		if active or c._merlinEnabled ~= false then
			c:ClearAllPoints()
			c:SetPoint(point, item.anchor, point, 0, 0)
			if AnchorUtil and AnchorUtil.FlowLayoutAxis then
				c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
			end
			c:SetFlowLayoutAnchorPoint(point)
			c:SetFlowLayoutGrowthDirection(hx, vy)
			c:SetFlowLayoutMaximumLineSize(iconW + 1)
			c:SetItemEnchantmentLayout({
				placement = CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups,
				elementSpacing = 0,
				lineSpacing = 0,
				elementWidth = iconW,
				elementHeight = iconH,
			})
			c:SetItemEnchantmentEnabled(item.slot, active)
			c._merlinEnabled = active
			c:SetEnabled(active)
			c:UpdateAllAuras()
		end
	end
end

function Merlin.GetCurrentCombatAlpha()
	return currentCombatAlpha
end

function Merlin.UpdateCombatAlpha(inCombat)
	if not Merlin.db then
		return
	end
	local combat = (inCombat ~= nil) and inCombat or (UnitAffectingCombat and UnitAffectingCombat("player"))
	local alpha = combat and 1.0 or Merlin.db.oocAlpha
	currentCombatAlpha = alpha
	for _, c in ipairs(primaryContainers) do
		if c then
			c:SetAlpha(alpha)
		end
	end
	for _, item in ipairs(soloEnchantItems) do
		if item.container then
			item.container:SetAlpha(alpha)
		end
	end
	if Merlin.SetEnchantOverlayAlpha then
		Merlin.SetEnchantOverlayAlpha(alpha)
	end
end

function Merlin.UpdateMovers()
	local unlocked = Merlin.db and not Merlin.db.locked and not Merlin.IsRestricted()
	if buffsAnchor and buffsAnchor.mover then
		buffsAnchor.mover:SetShown(unlocked and Merlin.db.buffs.enabled)
	end
	if debuffsAnchor and debuffsAnchor.mover then
		debuffsAnchor.mover:SetShown(unlocked and Merlin.db.debuffs.enabled)
	end
	if externalsAnchor and externalsAnchor.mover then
		externalsAnchor.mover:SetShown(unlocked and Merlin.db.externals.enabled)
	end
	local detached = unlocked and Merlin.db.enchants.showWeaponEnchants and Merlin.db.enchants.detachEnchants
	if enchantsAnchor and enchantsAnchor.mover then
		enchantsAnchor.mover:SetShown(detached and Merlin.db.enchants.grouped)
	end
	for _, item in ipairs(soloEnchantItems) do
		if item.anchor and item.anchor.mover then
			item.anchor.mover:SetShown(detached and not Merlin.db.enchants.grouped)
		end
	end
end

function Merlin.RefreshContainers()
	if Merlin.IsRestricted() then
		return
	end
	-- Always update Buffs first so anchors targeting BUFFS read its current size & position.
	ApplyContainerConfig(buffsAnchor, buffsContainer, "Buffs", Merlin.db.buffs, BUFF_OUTLINE_COLOR, true)
	ApplyContainerConfig(debuffsAnchor, debuffsContainer, "Debuffs", Merlin.db.debuffs, DEBUFF_OUTLINE_COLOR, false)
	ApplyContainerConfig(externalsAnchor, externalsContainer, "Externals", Merlin.db.externals, EXTERNAL_OUTLINE_COLOR, false)
	ApplyContainerConfig(enchantsAnchor, enchantsContainer, nil, Merlin.db.enchants, ENCHANT_OUTLINE_COLOR, false)
	ApplySoloEnchants(Merlin.db.enchants)
	Merlin.UpdateCombatAlpha()
	Merlin.UpdateMovers()
end

function Merlin.InitContainers()
	local db = Merlin.db

	-- Buffs (+ weapon enchantments)
	buffsAnchor = CreateAnchor("MerlinBuffsAnchor", "Buffs (Drag)", "buffs", BUFF_OUTLINE_COLOR)
	buffsContainer = CreateFrame("AuraContainer", "MerlinBuffsContainer", UIParent, "CustomAuraContainerTemplate")
	buffsContainer:SetUnit("player")

	buffsContainer:AddAuraGroup("Buffs", "HELPFUL", {
		maxFrameCount = db.buffs.maxIcons,
		sortMethod = SORT_METHOD_MAP[db.buffs.sortMethod] or SORT_METHOD_MAP.DEFAULT,
		sortDirection = SORT_DIR_MAP[db.buffs.sortDirection] or SORT_DIR_MAP.NORMAL,
		layout = {
			elementSpacing = db.buffs.spacingX,
			lineSpacing = db.buffs.spacingY,
			elementWidth = db.buffs.size,
			elementHeight = db.buffs.size,
		},
		initializeFrame = function(button)
			Merlin.InitializeAuraButton("buff", button)
		end,
	})

	for _, def in ipairs(SOLO_ENCHANT_DEFS) do
		buffsContainer:AddItemEnchantment(def.slot, {
			hidePermanent = false,
			initializeFrame = function(button)
				Merlin.InitializeAuraButton("enchant", button, def.key, "attached")
			end,
		})
	end

	-- Debuffs
	debuffsAnchor = CreateAnchor("MerlinDebuffsAnchor", "Debuffs (Drag)", "debuffs", DEBUFF_OUTLINE_COLOR)
	debuffsContainer = CreateFrame("AuraContainer", "MerlinDebuffsContainer", UIParent, "CustomAuraContainerTemplate")
	debuffsContainer:SetUnit("player")

	debuffsContainer:AddAuraGroup("Debuffs", "HARMFUL", {
		maxFrameCount = db.debuffs.maxIcons,
		sortMethod = SORT_METHOD_MAP[db.debuffs.sortMethod] or SORT_METHOD_MAP.DEFAULT,
		sortDirection = SORT_DIR_MAP[db.debuffs.sortDirection] or SORT_DIR_MAP.NORMAL,
		layout = {
			elementSpacing = db.debuffs.spacingX,
			lineSpacing = db.debuffs.spacingY,
			elementWidth = db.debuffs.size,
			elementHeight = db.debuffs.size,
		},
		initializeFrame = function(button)
			Merlin.InitializeAuraButton("debuff", button)
		end,
	})

	-- External Defensives
	local externalFilter = "HELPFUL|EXTERNAL_DEFENSIVE"
	if AuraUtil and AuraUtil.CreateFilterString and AuraUtil.AuraFilters
		and AuraUtil.AuraFilters.Helpful and AuraUtil.AuraFilters.ExternalDefensive
	then
		externalFilter = AuraUtil.CreateFilterString(
			AuraUtil.AuraFilters.Helpful,
			AuraUtil.AuraFilters.ExternalDefensive
		)
	end

	externalsAnchor = CreateAnchor("MerlinExternalsAnchor", "Externals (Drag)", "externals", EXTERNAL_OUTLINE_COLOR)
	externalsContainer = CreateFrame("AuraContainer", "MerlinExternalsContainer", UIParent, "CustomAuraContainerTemplate")
	externalsContainer:SetUnit("player")

	externalsContainer:AddAuraGroup("Externals", externalFilter, {
		maxFrameCount = db.externals.maxIcons,
		sortMethod = SORT_METHOD_MAP[db.externals.sortMethod] or SORT_METHOD_MAP.DEFAULT,
		sortDirection = SORT_DIR_MAP[db.externals.sortDirection] or SORT_DIR_MAP.NORMAL,
		layout = {
			elementSpacing = db.externals.spacingX,
			lineSpacing = db.externals.spacingY,
			elementWidth = db.externals.size,
			elementHeight = db.externals.size,
		},
		initializeFrame = function(button)
			Merlin.InitializeAuraButton("external", button)
		end,
	})

	-- Detached Weapon Enchants (grouped container + 3 independent single-slot containers)
	enchantsAnchor = CreateAnchor("MerlinEnchantsAnchor", "Enchants (Drag)", "enchants", ENCHANT_OUTLINE_COLOR)
	enchantsContainer = CreateFrame("AuraContainer", "MerlinEnchantsContainer", UIParent, "CustomAuraContainerTemplate")
	enchantsContainer:SetUnit("player")

	for _, def in ipairs(SOLO_ENCHANT_DEFS) do
		enchantsContainer:AddItemEnchantment(def.slot, {
			hidePermanent = false,
			initializeFrame = function(button)
				Merlin.InitializeAuraButton("enchant_detached", button, def.key, "grouped")
			end,
		})
	end

	for _, def in ipairs(SOLO_ENCHANT_DEFS) do
		local soloAnchor = CreateAnchor(
			"MerlinEnchant" .. def.name .. "Anchor",
			def.label,
			"enchants",
			ENCHANT_OUTLINE_COLOR,
			def.key
		)
		local soloContainer = CreateFrame(
			"AuraContainer",
			"MerlinEnchant" .. def.name .. "Container",
			UIParent,
			"CustomAuraContainerTemplate"
		)
		soloContainer:SetUnit("player")
		soloContainer:AddItemEnchantment(def.slot, {
			hidePermanent = false,
			initializeFrame = function(button)
				Merlin.InitializeAuraButton("enchant_detached", button, def.key, "solo")
			end,
		})
		soloEnchantItems[#soloEnchantItems + 1] = {
			key = def.key,
			slot = def.slot,
			anchor = soloAnchor,
			container = soloContainer,
		}
	end

	Merlin.buffsContainer = buffsContainer
	Merlin.debuffsContainer = debuffsContainer
	Merlin.externalsContainer = externalsContainer
	Merlin.enchantsContainer = enchantsContainer
	primaryContainers[1] = buffsContainer
	primaryContainers[2] = debuffsContainer
	primaryContainers[3] = externalsContainer
	primaryContainers[4] = enchantsContainer
	Merlin.buffsAnchor = buffsAnchor
	Merlin.debuffsAnchor = debuffsAnchor
	Merlin.externalsAnchor = externalsAnchor
	Merlin.enchantsAnchor = enchantsAnchor

	Merlin.RegisterRefresh(Merlin.RefreshContainers)
end
