local _, Merlin = ...

-- Vigil-inspired flat UI: solid fills, zero borders, muted class accent,
-- hover by shade, floating diamond-bookend wordmark, left sidebar + 2-column pages.

local function Rgb(hex, a)
	local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, a or 1 }
end

local T = {
	window = { 0, 0, 0, 1 },
	sidebar = { 0, 0, 0, 0.45 },
	popup = Rgb("#0b0b0b", 0.98),
	band = Rgb("#ffffff", 0.045),
	control = Rgb("#ffffff", 0.075),
	hover = Rgb("#ffffff", 0.12),
	pressed = Rgb("#ffffff", 0.17),
	navActive = Rgb("#ffffff", 0.06),
	text = Rgb("#e6e6e6"),
	muted = Rgb("#8e8e8e"),
	faint = Rgb("#737373"),
	accent = Rgb("#a9bfaa"),
	danger = Rgb("#d88e83"),
	none = { 0, 0, 0, 0 },
	black = { 0, 0, 0, 1 },
}

local WIDTH, HEIGHT = 544, 550
local NAV_W, NAV_COLLAPSED = 104, 40
local PAD = 12
local COL_GAP = 16
local COL_W = math.floor((WIDTH - NAV_W - PAD * 2 - COL_GAP) / 2)
local CTRL_W = 104
local PREVIEW_H = 70
local WHITE = "Interface\\Buttons\\WHITE8X8"

local window, nav, main
local activePage = "buffs"
local navButtons = {}
local pages = {}
local refreshFns = {}
local statusFrame, statusText
local statusToken = 0

local menu, catcher
local CreateGlyph, AttachTip

local function SetColor(tex, c, alpha)
	tex:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
end

local function Fill(parent, color, alpha, layer)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, -8)
	tex:SetAllPoints()
	SetColor(tex, color, alpha)
	return tex
end

local function Panel(frame, color)
	frame.base = color or T.control
	frame.bg = Fill(frame, frame.base)
	return frame
end

local function Shade(frame, color)
	SetColor(frame.bg, color)
end

-- Soft 9-slice outer drop shadow (Vigil / Mapita approach, MIT)
local function AddShadow(parent, thickness, alpha)
	thickness = thickness or 12
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
	f:EnableMouse(false)
	local path = "Interface\\AddOns\\Merlin\\Media\\Icons\\shadow.tga"
	local uv = { 0, 0.25, 0.75, 1 }
	local corner = { [1] = "TOPLEFT", [3] = "TOPRIGHT", [7] = "BOTTOMLEFT", [9] = "BOTTOMRIGHT" }
	for index = 1, 9 do
		if index ~= 5 then
			local col = (index - 1) % 3 + 1
			local row = math.floor((index - 1) / 3) + 1
			local slice = f:CreateTexture(nil, "BACKGROUND")
			slice:SetTexture(path)
			slice:SetTexCoord(uv[col], uv[col + 1], uv[row], uv[row + 1])
			slice:SetVertexColor(0, 0, 0, alpha or 0.9)
			if col == 2 then
				local edge = row == 1 and "TOP" or "BOTTOM"
				local offset = row == 1 and thickness or -thickness
				slice:SetPoint(edge .. "LEFT", parent, edge .. "LEFT", 0, offset)
				slice:SetPoint(edge .. "RIGHT", parent, edge .. "RIGHT", 0, offset)
				slice:SetHeight(thickness)
			elseif row == 2 then
				local edge = col == 1 and "LEFT" or "RIGHT"
				local offset = col == 1 and -thickness or thickness
				slice:SetPoint("TOP" .. edge, parent, "TOP" .. edge, offset, 0)
				slice:SetPoint("BOTTOM" .. edge, parent, "BOTTOM" .. edge, offset, 0)
				slice:SetWidth(thickness)
			else
				slice:SetSize(thickness, thickness)
				slice:SetPoint(corner[index], parent, corner[index],
					col == 1 and -thickness or thickness, row == 1 and thickness or -thickness)
			end
		end
	end
	return f
end

local function Text(parent, str, template, color)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	fs:SetTextColor(unpack(color or T.text))
	fs:SetJustifyH("LEFT")
	fs:SetText(str or "")
	return fs
end

local function CloseMenu()
	if menu then
		menu:Hide()
	end
end

local function ShowStatus(msg)
	if not statusFrame then
		return
	end
	statusToken = statusToken + 1
	local token = statusToken
	statusText:SetText(msg or "")
	statusText:SetWidth(0)
	local w = math.min(WIDTH - NAV_W - 32, math.ceil(statusText:GetStringWidth()) + 20)
	statusFrame:SetWidth(math.max(60, w))
	statusFrame:SetShown(msg ~= nil and msg ~= "")
	C_Timer.After(3.5, function()
		if token == statusToken and statusFrame then
			statusFrame:Hide()
		end
	end)
end

local function ApplyWindowOpacity()
	if window and window.bg then
		SetColor(window.bg, T.window, Merlin.db and Merlin.db.windowOpacity or 0.94)
	end
end

-- Flat borderless button
local function CreateButton(parent, label, w, h, transparent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 80, h or 24)
	Panel(b, transparent and T.none or T.control)
	b.label = Text(b, label, "GameFontHighlight", T.text)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyH("CENTER")
	b.textColor = T.text

	local function Paint()
		if b.disabled then
			Shade(b, b.base)
			b.label:SetTextColor(unpack(T.faint))
			return
		end
		if b.hover then
			Shade(b, T.hover)
		elseif b.active then
			Shade(b, transparent and T.navActive or T.pressed)
		else
			Shade(b, b.base)
		end
		b.label:SetTextColor(unpack(b.active and T.accent or b.textColor))
	end

	b.Paint = Paint
	function b:SetLabel(s)
		self.label:SetText(s)
	end
	function b:SetActive(on)
		self.active = on and true or nil
		Paint()
	end
	function b:SetTextColor(c)
		self.textColor = c
		Paint()
	end
	function b:SetDisabled(off)
		self.disabled = off and true or nil
		self:EnableMouse(not off)
		Paint()
	end

	b:SetScript("OnEnter", function()
		b.hover = true
		Paint()
	end)
	b:SetScript("OnLeave", function()
		b.hover = nil
		Paint()
	end)
	return b
end

-- Two-click armed confirmation button
local function CreateArmedButton(parent, label, w, onConfirm)
	local b = CreateButton(parent, label, w or 130, 24, false)
	local function Disarm()
		b.armToken = nil
		b:SetLabel(label)
		b:SetTextColor(T.text)
	end
	b:SetScript("OnClick", function()
		if InCombatLockdown() then
			return
		end
		if not b.armToken then
			local token = {}
			b.armToken = token
			b:SetLabel("Click again")
			b:SetTextColor(T.danger)
			C_Timer.After(3, function()
				if b.armToken == token then
					Disarm()
				end
			end)
			return
		end
		Disarm()
		onConfirm()
	end)
	b:SetScript("OnHide", Disarm)
	return b
end

-- Shared dropdown popup menu
local function OpenMenu(anchor, options, current, onPick, openUp)
	if not menu then
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:Hide()

		menu = CreateFrame("Frame", nil, UIParent)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetClampedToScreen(true)
		menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
		menu:EnableMouse(true)
		Panel(menu, T.popup)
		menu.items = {}
		menu.measure = Text(menu, "", "GameFontHighlight")
		menu.measure:Hide()

		catcher:SetScript("OnClick", function() menu:Hide() end)
		menu:SetScript("OnHide", function() catcher:Hide() end)
	end

	local width = math.max(anchor:GetWidth(), 120)
	for _, opt in ipairs(options) do
		menu.measure:SetText(opt.label)
		width = math.max(width, math.ceil(menu.measure:GetStringWidth()) + 22)
	end

	menu.onPick = onPick
	for i, opt in ipairs(options) do
		local item = menu.items[i]
		if not item then
			item = CreateFrame("Button", nil, menu)
			item.bg = Fill(item, T.black, 0)
			item.label = Text(item, "", "GameFontHighlight")
			item.label:SetPoint("LEFT", 8, 0)
			item:SetScript("OnEnter", function(self) SetColor(self.bg, T.hover) end)
			item:SetScript("OnLeave", function(self) SetColor(self.bg, T.black, 0) end)
			item:SetScript("OnClick", function(self)
				menu:Hide()
				if menu.onPick then
					menu.onPick(self.store)
				end
			end)
			menu.items[i] = item
		end
		item:SetSize(width - 4, 21)
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 21)
		item.label:SetText(opt.label)
		item.store = opt.store
		item.label:SetTextColor(unpack(opt.store == current and T.accent or T.text))
		item:Show()
	end
	for i = #options + 1, #menu.items do
		menu.items[i]:Hide()
	end
	menu:SetSize(width, #options * 21 + 4)
	menu:ClearAllPoints()
	if openUp then
		menu:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
	else
		menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	end
	catcher:Show()
	menu:Show()
end

-- Compact form rows

local function CreateSection(parent, y, label, onReset)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(18)
	local fs = Text(row, label, "GameFontHighlight", T.accent)
	fs:SetPoint("LEFT", 0, 0)
	if onReset then
		local rb = CreateFrame("Button", nil, row)
		rb:SetSize(16, 16)
		rb:SetPoint("RIGHT", 0, 0)
		local g = CreateGlyph(rb, "reset", 12)
		g:SetPoint("CENTER")
		g:Draw("reset", T.faint)
		rb:SetScript("OnEnter", function() g:Draw("reset", T.text) end)
		rb:SetScript("OnLeave", function() g:Draw("reset", T.faint) end)
		rb:SetScript("OnClick", function()
			if InCombatLockdown() then
				return
			end
			onReset()
			Merlin.RequestRefresh()
			Merlin.RefreshOptions()
			ShowStatus(label .. " reset to defaults.")
		end)
		AttachTip(rb, "Reset " .. label:lower())
	end
	return y - 22
end

local function CreateCheckRow(parent, y, label, getVal, setVal, disabledFn)
	local row = CreateFrame("Button", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(22)

	local box = CreateFrame("Frame", nil, row)
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 0, 0)
	Panel(box, T.control)

	local mark = box:CreateTexture(nil, "ARTWORK")
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	SetColor(mark, T.accent)

	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(box)
	SetColor(hl, T.text, 0.12)

	local fs = Text(row, label, "GameFontHighlight", T.text)
	fs:SetPoint("LEFT", box, "RIGHT", 7, 0)

	local function Refresh()
		local off = disabledFn and disabledFn() or false
		row:SetAlpha(off and 0.45 or 1)
		row:EnableMouse(not off)
		mark:SetShown(getVal() and true or false)
	end

	row:SetScript("OnClick", function()
		if InCombatLockdown() then
			return
		end
		setVal(not getVal())
		Refresh()
		Merlin.RequestRefresh()
	end)

	refreshFns[#refreshFns + 1] = Refresh
	return y - 23
end

local function CreateCheckPairRow(parent, y, labelA, getA, setA, labelB, getB, setB, splitX)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(22)

	local function AddHalf(xOff, w, label, getVal, setVal)
		local btn = CreateFrame("Button", nil, row)
		btn:SetPoint("TOPLEFT", xOff, 0)
		btn:SetSize(w, 22)

		local box = CreateFrame("Frame", nil, btn)
		box:SetSize(14, 14)
		box:SetPoint("LEFT", 0, 0)
		Panel(box, T.control)

		local mark = box:CreateTexture(nil, "ARTWORK")
		mark:SetPoint("TOPLEFT", 3, -3)
		mark:SetPoint("BOTTOMRIGHT", -3, 3)
		SetColor(mark, T.accent)

		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(box)
		SetColor(hl, T.text, 0.12)

		local fs = Text(btn, label, "GameFontHighlight", T.text)
		fs:SetPoint("LEFT", box, "RIGHT", 6, 0)

		local function Refresh()
			mark:SetShown(getVal() and true or false)
		end

		btn:SetScript("OnClick", function()
			if InCombatLockdown() then
				return
			end
			setVal(not getVal())
			Refresh()
			Merlin.RequestRefresh()
		end)

		refreshFns[#refreshFns + 1] = Refresh
	end

	local sx = splitX or 112
	AddHalf(0, sx - 2, labelA, getA, setA)
	AddHalf(sx, COL_W - sx, labelB, getB, setB)
	return y - 23
end

local function CreateNumberInput(parent, width, minVal, maxVal, getVal, setVal)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetFontObject("GameFontHighlight")
	box:SetJustifyH("CENTER")
	box:SetMaxLetters(6)
	Panel(box, T.control)

	local display = Text(box, "", "GameFontHighlight", T.text)
	display:SetPoint("CENTER")
	display:SetJustifyH("CENTER")

	local function Refresh()
		if not box:HasFocus() then
			display:SetText(tostring(getVal()))
		end
	end

	box:SetScript("OnEditFocusGained", function(self)
		self.cancel = nil
		display:Hide()
		self:SetText(tostring(getVal()))
		self:HighlightText()
		Shade(self, T.hover)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		Shade(self, T.control)
		local v = tonumber(self:GetText())
		if not self.cancel and v and v == v and not InCombatLockdown() then
			v = math.floor(math.max(minVal, math.min(maxVal, v)) + 0.5)
			setVal(v)
			Merlin.RequestRefresh()
		end
		self:SetText("")
		Refresh()
		display:Show()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self.cancel = true
		self:ClearFocus()
	end)

	refreshFns[#refreshFns + 1] = Refresh
	return box
end

-- Paired X / Y compact number inputs on a single row
local function CreatePairRow(parent, y, label, minVal, maxVal, getX, setX, getY, setY)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(22)

	local fs = Text(row, label, "GameFontHighlight", T.text)
	fs:SetPoint("LEFT", 0, 0)

	local boxW = math.floor((CTRL_W - 4) / 2)
	local yBox = CreateNumberInput(row, boxW, minVal, maxVal, getY, setY)
	yBox:SetPoint("RIGHT", 0, 0)

	local xBox = CreateNumberInput(row, boxW, minVal, maxVal, getX, setX)
	xBox:SetPoint("RIGHT", yBox, "LEFT", -4, 0)

	return y - 24
end

local function CreateSliderRow(parent, y, label, minVal, maxVal, step, getVal, setVal, fmtFn, ctrlW)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(22)

	local fs = Text(row, label, "GameFontHighlight", T.text)
	fs:SetPoint("LEFT", 0, 0)

	local control = CreateFrame("Frame", nil, row)
	control:SetPoint("RIGHT", 0, 0)
	control:SetSize(ctrlW or CTRL_W, 20)

	local valBox = CreateFrame("EditBox", nil, control)
	valBox:SetPoint("RIGHT", 0, 0)
	valBox:SetSize(40, 20)
	valBox:SetAutoFocus(false)
	valBox:SetFontObject("GameFontHighlight")
	valBox:SetJustifyH("RIGHT")
	valBox:SetTextInsets(2, 3, 0, 0)
	valBox:SetMaxLetters(6)
	Panel(valBox, T.none)

	local valText = Text(valBox, "", "GameFontHighlight", T.text)
	valText:SetPoint("LEFT", 2, 0)
	valText:SetPoint("RIGHT", -3, 0)
	valText:SetJustifyH("RIGHT")
	valText:SetWordWrap(false)

	local slider = CreateFrame("Slider", nil, control)
	slider:SetPoint("LEFT", 0, 0)
	slider:SetPoint("RIGHT", valBox, "LEFT", -4, 0)
	slider:SetHeight(16)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minVal, maxVal)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)

	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	SetColor(track, T.control)

	slider:SetThumbTexture(WHITE)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(4, 14)
	thumb:SetVertexColor(unpack(T.accent))

	local filled = slider:CreateTexture(nil, "ARTWORK")
	filled:SetPoint("LEFT", track)
	filled:SetPoint("RIGHT", thumb, "CENTER")
	filled:SetHeight(4)
	SetColor(filled, T.accent, 0.45)

	local function FormatVal(v)
		return fmtFn and fmtFn(v) or tostring(v)
	end

	local function ClampStep(v)
		local rounded = minVal + math.floor((v - minVal) / step + 0.5) * step
		return math.max(minVal, math.min(maxVal, tonumber(("%.4f"):format(rounded))))
	end

	slider:SetScript("OnEnter", function() SetColor(track, T.hover) end)
	slider:SetScript("OnLeave", function() SetColor(track, T.control) end)

	local syncing = false
	local function Refresh()
		local v = getVal()
		syncing = true
		slider:SetValue(v)
		if not valBox:HasFocus() then
			valText:SetText(FormatVal(v))
		end
		syncing = false
	end

	slider:SetScript("OnValueChanged", function(_, v)
		if syncing or InCombatLockdown() then
			return
		end
		local rounded = ClampStep(v)
		valText:SetText(FormatVal(rounded))
		setVal(rounded)
		Merlin.RequestRefresh()
	end)

	valBox:SetScript("OnEnter", function(self)
		if not self:HasFocus() then
			Shade(self, T.control)
		end
	end)
	valBox:SetScript("OnLeave", function(self)
		if not self:HasFocus() then
			Shade(self, T.none)
		end
	end)
	valBox:SetScript("OnEditFocusGained", function(self)
		self.cancel = nil
		valText:Hide()
		local cur = getVal()
		local editVal = (fmtFn and maxVal <= 1) and math.floor(cur * 100 + 0.5) or cur
		self:SetText(tostring(editVal))
		self:HighlightText()
		Shade(self, T.hover)
	end)
	valBox:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		Shade(self, T.none)
		local raw = (self:GetText() or ""):gsub("%%", "")
		local num = tonumber(raw)
		if not self.cancel and num and num == num and not InCombatLockdown() then
			if fmtFn and maxVal <= 1 and num > 1 then
				num = num / 100
			end
			local clamped = ClampStep(num)
			setVal(clamped)
			Merlin.RequestRefresh()
		end
		self:SetText("")
		Refresh()
		valText:Show()
	end)
	valBox:SetScript("OnEnterPressed", valBox.ClearFocus)
	valBox:SetScript("OnEscapePressed", function(self)
		self.cancel = true
		self:ClearFocus()
	end)

	refreshFns[#refreshFns + 1] = Refresh
	return y - 24
end

local function CreateChoiceRow(parent, y, label, optionsOrFn, getVal, setVal, ctrlW)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(22)

	local fs = Text(row, label, "GameFontHighlight", T.text)
	fs:SetPoint("LEFT", 0, 0)

	local btn = CreateButton(row, "", ctrlW or CTRL_W, 20, false)
	btn:SetPoint("RIGHT", 0, 0)
	btn.label:ClearAllPoints()
	btn.label:SetPoint("LEFT", 6, 0)
	btn.label:SetPoint("RIGHT", -16, 0)
	btn.label:SetJustifyH("LEFT")
	btn.label:SetWordWrap(false)

	local caret = CreateGlyph(btn, "chevron", 11)
	caret:SetPoint("RIGHT", -5, 0)
	caret:Draw("chevron", T.muted)

	local function GetOpts()
		return type(optionsOrFn) == "function" and optionsOrFn() or optionsOrFn
	end

	local function Refresh()
		local cur = getVal()
		local shown = tostring(cur)
		for _, opt in ipairs(GetOpts()) do
			if opt.store == cur then
				shown = opt.label
				break
			end
		end
		btn:SetLabel(shown)
	end

	btn:SetScript("OnClick", function()
		if InCombatLockdown() then
			return
		end
		OpenMenu(btn, GetOpts(), getVal(), function(store)
			setVal(store)
			Refresh()
			Merlin.RequestRefresh()
		end)
	end)

	refreshFns[#refreshFns + 1] = Refresh
	return y - 24
end

-- Flat borderless color swatch row (loads Blizzard_ColorPickerFrame on demand)
local function CreateColorRow(parent, y, label, getColor, setColorFn)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(21)

	local fs = Text(row, label, "GameFontHighlight", T.text)
	fs:SetPoint("LEFT", 0, 0)

	local btn = CreateFrame("Button", nil, row)
	btn:SetPoint("RIGHT", 0, 0)
	btn:SetSize(34, 17)
	Panel(btn, T.control)

	local chip = btn:CreateTexture(nil, "ARTWORK")
	chip:SetPoint("TOPLEFT", 2, -2)
	chip:SetPoint("BOTTOMRIGHT", -2, 2)

	local function Refresh()
		local c = getColor()
		chip:SetColorTexture(c[1], c[2], c[3], 1)
	end

	btn:SetScript("OnEnter", function() Shade(btn, T.hover) end)
	btn:SetScript("OnLeave", function() Shade(btn, T.control) end)
	btn:SetScript("OnClick", function()
		if InCombatLockdown() then
			return
		end
		if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then
			C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
		end
		if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
			ShowStatus("Color picker unavailable.")
			return
		end
		local c = getColor()
		local prev = { c[1], c[2], c[3] }
		ColorPickerFrame:SetupColorPickerAndShow({
			r = c[1],
			g = c[2],
			b = c[3],
			hasOpacity = false,
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				setColorFn(r, g, b)
				Refresh()
				Merlin.RequestRefresh()
			end,
			cancelFunc = function()
				setColorFn(prev[1], prev[2], prev[3])
				Refresh()
				Merlin.RequestRefresh()
			end,
		})
	end)

	refreshFns[#refreshFns + 1] = Refresh
	return y - 22
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
	{ label = "1:30 / 5m", store = "SMART" },
	{ label = "2m / 45s", store = "COMPACT" },
	{ label = "Blizzard", store = "BLIZZARD" },
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
	Merlin.RefreshOptions()
end

-- Live preview strip inside each group page

local function Sample(icon, smart, compact, blizz, tier, borderKey, stacks, dur, rem, isEnchant, dec)
	return {
		icon = "Interface\\Icons\\" .. icon,
		smart = smart,
		compact = compact,
		blizz = blizz,
		tier = tier,
		borderKey = borderKey,
		stacks = stacks,
		dur = dur,
		rem = rem,
		isEnchant = isEnchant,
		dec = dec,
	}
end

local PREVIEW_ITEMS = {
	buffs = {
		Sample("Spell_Holy_WordFortitude", "12m", "12m", "12 m", "normal", "buffBorder", nil, 60, 45),
		Sample("Spell_Nature_Regeneration", "28", "28s", "28 s", "warn", "buffBorder", nil, 60, 28),
		Sample("Spell_Holy_PowerWordShield", "4", "4s", "4 s", "urgent", "buffBorder", nil, 30, 4, false, true),
		Sample("Spell_Arcane_Arcane01", "4:15", "4m", "4 m", "normal", "buffBorder", "3", 60, 36),
		Sample("Spell_Nature_Swiftness", nil, nil, nil, nil, "buffBorder"),
		Sample("Ability_Poisons", "24m", "24m", "24 m", "normal", "enchantBorder", "45", 60, 48, true),
	},
	debuffs = {
		Sample("Ability_Gouge", "18", "18s", "18 s", "warn", "dispelNone", "2", 30, 18),
		Sample("Spell_Shadow_ShadowWordPain", "4", "4s", "4 s", "urgent", "dispelMagic", nil, 30, 4, false, true),
		Sample("Spell_Shadow_CurseOfSargeras", "1:45", "1m", "1 m", "normal", "dispelCurse", nil, 60, 42),
		Sample("Ability_Creature_Poison_02", "12", "12s", "12 s", "warn", "dispelPoison", "5", 30, 12),
		Sample("Spell_Nature_NullifyDisease", "2m", "2m", "2 m", "normal", "dispelDisease", nil, 60, 40),
		Sample("Ability_Warrior_Riposte", "8", "8s", "8 s", "warn", "dispelBleed", "3", 30, 8),
	},
	externals = {
		Sample("Spell_Holy_SealOfProtection", "8", "8s", "8 s", "warn", "externalBorder", nil, 12, 8),
		Sample("Spell_Nature_StoneClawTotem", "3", "3s", "3 s", "urgent", "externalBorder", nil, 12, 3, false, true),
		Sample("Spell_Holy_DivineIntervention", "12", "12s", "12 s", "warn", "externalBorder", "2", 20, 12),
	},
	enchants = {
		Sample("Ability_Poisons", "28m", "28m", "28 m", "normal", "enchantBorder", "45", 60, 48),
		Sample("Ability_Rogue_DualWeild", "12m", "12m", "12 m", "normal", "enchantBorder", "20", 60, 24),
		Sample("INV_Ammo_Arrow_02", "4", "4s", "4 s", "urgent", "enchantBorder", nil, 30, 4, false, true),
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

	local border = CreateFrame("Frame", nil, f)
	border:SetAllPoints()
	border:SetFrameLevel(cd:GetFrameLevel() + 1)
	local top = border:CreateTexture(nil, "OVERLAY")
	local bottom = border:CreateTexture(nil, "OVERLAY")
	local left = border:CreateTexture(nil, "OVERLAY")
	local right = border:CreateTexture(nil, "OVERLAY")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	for _, edge in ipairs({ top, bottom, left, right }) do
		edge:SetTexture(WHITE)
	end
	f.borderFrame = border
	f.edges = { top, bottom, left, right }

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
	local items = PREVIEW_ITEMS[cfgKey] or {}
	for i = 1, #items do
		slots[i] = CreatePreviewIcon(strip)
	end

	local function Refresh()
		local cfg = (cfgKey == "enchants") and Merlin.GetEnchantStyleConfig() or Merlin.db[cfgKey]
		local db = Merlin.db
		local font = Merlin.GetFontPath()
		local outline = db.fontOutline
		local px = Merlin.GetPixelSize(strip) * db.borderSize
		local size = math.min(cfg.size, 36)
		local stripW = WIDTH - NAV_W - PAD * 2

		local active = {}
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
				if db.borderSize > 0 then
					slot.borderFrame:Show()
					slot.edges[1]:SetHeight(px)
					slot.edges[2]:SetHeight(px)
					slot.edges[3]:SetWidth(px)
					slot.edges[4]:SetWidth(px)
					for _, edge in ipairs(slot.edges) do
						edge:SetVertexColor(bCol[1], bCol[2], bCol[3], 1)
					end
				else
					slot.borderFrame:Hide()
				end

				if cfgKey == "debuffs" and cfg.showDispelIcon and i > 1 then
					slot.dispelBadge:SetVertexColor(bCol[1], bCol[2], bCol[3], 1)
					slot.dispelBadge:Show()
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

				if cfg.showDuration and data.smart then
					local txt = (cfg.durationFormat == "COMPACT") and data.compact
						or (cfg.durationFormat == "BLIZZARD" and data.blizz or data.smart)
					if data.dec and cfg.showDecimals and cfg.durationFormat ~= "BLIZZARD" then
						txt = (cfg.durationFormat == "COMPACT") and (data.smart .. ".2s") or (data.smart .. ".2")
					end
					slot.duration:SetFont(font, cfg.durationFontSize, outline)
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
					slot.count:SetFont(font, cfg.countFontSize, outline)
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

	refreshFns[#refreshFns + 1] = Refresh
	return strip
end

-- Single 2-column group page: Preview strip + Left (Layout & Position) + Right (Display & Text)

local function BuildGroupPage(cfgKey, titleText, isBuff)
	local page = CreateFrame("Frame", nil, main)
	page:SetAllPoints(main)
	page:Hide()

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
			function(v) Merlin.db.enchants.showWeaponEnchants = v end
		)
		ly = CreateCheckRow(leftCol, ly, "Detach from Buffs",
			function() return Merlin.db.enchants.detachEnchants end,
			function(v)
				Merlin.db.enchants.detachEnchants = v
				if v then
					Merlin.db.enchants.showWeaponEnchants = true
				end
				Merlin.RefreshOptions()
			end
		)
		ly = CreateCheckRow(leftCol, ly, "Group slots",
			function() return Merlin.db.enchants.grouped end,
			function(v)
				Merlin.db.enchants.grouped = v
				Merlin.RefreshOptions()
			end
		)
	else
		ly = CreateCheckRow(leftCol, ly, "Enable " .. titleText:lower(),
			function() return Merlin.db[cfgKey].enabled end,
			function(v) Merlin.db[cfgKey].enabled = v end
		)
	end
	ly = CreateSliderRow(leftCol, ly, "Icon size", 18, 64, 1,
		function() return Merlin.db[cfgKey].size end,
		function(v) Merlin.db[cfgKey].size = v end
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
			function(v) Merlin.db[cfgKey].perRow = v end
		)
	end
	ly = CreateSliderRow(leftCol, ly, "Spacing X", 0, 32, 1,
		function() return Merlin.db[cfgKey].spacingX end,
		function(v) Merlin.db[cfgKey].spacingX = v end
	)
	ly = CreateSliderRow(leftCol, ly, "Spacing Y", 0, 32, 1,
		function() return Merlin.db[cfgKey].spacingY end,
		function(v) Merlin.db[cfgKey].spacingY = v end
	)
	ly = CreateChoiceRow(leftCol, ly, "Axis", ORIENTATION_OPTS,
		function() return Merlin.db[cfgKey].orientation end,
		function(v) Merlin.db[cfgKey].orientation = v end
	)
	ly = CreateChoiceRow(leftCol, ly, "Grow X", GROWTH_X_OPTS,
		function() return Merlin.db[cfgKey].growthX end,
		function(v) Merlin.db[cfgKey].growthX = v end
	)
	ly = CreateChoiceRow(leftCol, ly, "Grow Y", GROWTH_Y_OPTS,
		function() return Merlin.db[cfgKey].growthY end,
		function(v) Merlin.db[cfgKey].growthY = v end
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
		function(v) ApplyAnchorPreset(cfgKey, v) end
	)
	if cfgKey == "enchants" then
		ly = CreateChoiceRow(leftCol, ly, "Slot", ENCHANT_SLOT_OPTS,
			function() return selectedEnchantSlot end,
			function(v)
				selectedEnchantSlot = v
				Merlin.RefreshOptions()
			end
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
			end
		)
	else
		CreatePairRow(leftCol, ly, "X / Y", -5000, 5000,
			function() return Merlin.db[cfgKey].x end,
			function(v) Merlin.db[cfgKey].x = v end,
			function() return Merlin.db[cfgKey].y end,
			function(v) Merlin.db[cfgKey].y = v end
		)
	end

	-- Right column: Timer text + Stacks & cooldown (+ Dispel badge / Enchant behavior)
	local ry = 0
	ry = CreateSection(rightCol, ry, "Timer text", function()
		ResetKeys({
			"showDuration", "colorDurationByTime", "showDecimals",
			"durationFormat", "durationFontSize", "durationAnchor",
			"durationOffsetX", "durationOffsetY",
		})
	end)
	ry = CreateCheckRow(rightCol, ry, "Show duration",
		function() return Merlin.db[cfgKey].showDuration end,
		function(v) Merlin.db[cfgKey].showDuration = v end
	)
	ry = CreateCheckPairRow(rightCol, ry,
		"Color by time",
		function() return Merlin.db[cfgKey].colorDurationByTime end,
		function(v) Merlin.db[cfgKey].colorDurationByTime = v end,
		"Decimals",
		function() return Merlin.db[cfgKey].showDecimals end,
		function(v) Merlin.db[cfgKey].showDecimals = v end,
		112
	)
	ry = CreateChoiceRow(rightCol, ry, "Format", DURATION_FMT_OPTS,
		function() return Merlin.db[cfgKey].durationFormat end,
		function(v) Merlin.db[cfgKey].durationFormat = v end
	)
	ry = CreateSliderRow(rightCol, ry, "Font size", 8, 24, 1,
		function() return Merlin.db[cfgKey].durationFontSize end,
		function(v) Merlin.db[cfgKey].durationFontSize = v end
	)
	ry = CreateChoiceRow(rightCol, ry, "Position", DURATION_ANCHOR_OPTS,
		function() return Merlin.db[cfgKey].durationAnchor end,
		function(v) Merlin.db[cfgKey].durationAnchor = v end
	)
	ry = CreatePairRow(rightCol, ry, "Offset X/Y", -32, 32,
		function() return Merlin.db[cfgKey].durationOffsetX end,
		function(v) Merlin.db[cfgKey].durationOffsetX = v end,
		function() return Merlin.db[cfgKey].durationOffsetY end,
		function(v) Merlin.db[cfgKey].durationOffsetY = v end
	)

	ry = ry - 6
	ry = CreateSection(rightCol, ry, "Stacks & cooldown", function()
		ResetKeys({
			"showCount", "countFontSize", "countAnchor",
			"countOffsetX", "countOffsetY",
			"showCooldownSwipe", "reverseCooldownSwipe", "showDispelIcon",
		})
	end)
	ry = CreateCheckRow(rightCol, ry, "Show stacks",
		function() return Merlin.db[cfgKey].showCount end,
		function(v) Merlin.db[cfgKey].showCount = v end
	)
	ry = CreateSliderRow(rightCol, ry, "Stack size", 8, 24, 1,
		function() return Merlin.db[cfgKey].countFontSize end,
		function(v) Merlin.db[cfgKey].countFontSize = v end
	)
	ry = CreateChoiceRow(rightCol, ry, "Stack pos", COUNT_ANCHOR_OPTS,
		function() return Merlin.db[cfgKey].countAnchor end,
		function(v) Merlin.db[cfgKey].countAnchor = v end
	)
	ry = CreatePairRow(rightCol, ry, "Offset X/Y", -32, 32,
		function() return Merlin.db[cfgKey].countOffsetX end,
		function(v) Merlin.db[cfgKey].countOffsetX = v end,
		function() return Merlin.db[cfgKey].countOffsetY end,
		function(v) Merlin.db[cfgKey].countOffsetY = v end
	)
	ry = CreateCheckPairRow(rightCol, ry,
		"CD swipe",
		function() return Merlin.db[cfgKey].showCooldownSwipe end,
		function(v) Merlin.db[cfgKey].showCooldownSwipe = v end,
		"Reverse",
		function() return Merlin.db[cfgKey].reverseCooldownSwipe end,
		function(v) Merlin.db[cfgKey].reverseCooldownSwipe = v end,
		112
	)

	if cfgKey == "debuffs" then
		CreateCheckRow(rightCol, ry, "Dispel icon badge",
			function() return Merlin.db.debuffs.showDispelIcon end,
			function(v) Merlin.db.debuffs.showDispelIcon = v end
		)
	elseif cfgKey == "enchants" then
		ry = ry - 6
		ry = CreateSection(rightCol, ry, "Behavior")
		ry = CreateCheckRow(rightCol, ry, "Follow Buffs style",
			function() return Merlin.db.enchants.followBuffsStyle end,
			function(v)
				Merlin.db.enchants.followBuffsStyle = v
				Merlin.RefreshOptions()
			end
		)
		CreateChoiceRow(rightCol, ry, "In Buffs", ENCHANT_PLACE_OPTS,
			function() return Merlin.db.enchants.enchantPlacement end,
			function(v) Merlin.db.enchants.enchantPlacement = v end
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
		if InCombatLockdown() then
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
		if InCombatLockdown() then
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
				ShowStatus(titleText .. " using Default profile.")
			end
		end, true)
	end)
	refreshFns[#refreshFns + 1] = RefreshProfile

	return page
end

local ioDialog
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
	if InCombatLockdown() then
		return
	end
	if not ioDialog then
		local d = CreateFrame("Frame", nil, window)
		d:SetSize(330, 210)
		d:SetPoint("CENTER", window, "CENTER", 0, 0)
		d:SetFrameLevel(window:GetFrameLevel() + 50)
		d:EnableMouse(true)
		Panel(d, T.popup)

		-- Dim backdrop over window while dialog is open
		local dim = CreateFrame("Button", nil, d)
		dim:SetAllPoints(window)
		dim:SetFrameLevel(d:GetFrameLevel() - 1)
		Fill(dim, T.black, 0.55)
		dim:SetScript("OnClick", function() d:Hide() end)

		d.title = Text(d, "", "GameFontHighlight", T.text)
		d.title:SetPoint("TOPLEFT", 12, -10)

		d.hint = Text(d, "", "GameFontHighlightSmall", T.muted)
		d.hint:SetPoint("TOPLEFT", 12, -26)

		local boxBg = CreateFrame("Frame", nil, d)
		boxBg:SetPoint("TOPLEFT", 12, -44)
		boxBg:SetPoint("BOTTOMRIGHT", -12, 40)
		Panel(boxBg, T.control)

		local edit = CreateFrame("EditBox", nil, boxBg)
		edit:SetPoint("TOPLEFT", 6, -6)
		edit:SetPoint("BOTTOMRIGHT", -6, 6)
		edit:SetMultiLine(true)
		edit:SetMaxLetters(0)
		edit:SetAutoFocus(false)
		edit:SetFontObject("GameFontHighlightSmall")
		edit:SetTextInsets(2, 2, 2, 2)
		edit:SetScript("OnEscapePressed", function() d:Hide() end)
		d.edit = edit

		boxBg:EnableMouse(true)
		boxBg:SetScript("OnMouseDown", function() edit:SetFocus() end)

		d.actionBtn = CreateButton(d, "Import", 84, 22, false)
		d.actionBtn:SetPoint("BOTTOMRIGHT", -12, 10)

		local closeIo = CreateButton(d, "Close", 68, 22, false)
		closeIo:SetPoint("RIGHT", d.actionBtn, "LEFT", -6, 0)
		closeIo:SetScript("OnClick", function() d:Hide() end)
		d.closeBtn = closeIo

		ioDialog = d
	end

	local label = GetIOTargetLabel(target)
	if mode == "EXPORT" then
		local str, err = Merlin.ExportProfile(target)
		if not str then
			ShowStatus(err or "Export failed.")
			return
		end
		ioDialog.title:SetText("Export — " .. label)
		ioDialog.hint:SetText("Press Ctrl+C to copy this string.")
		ioDialog.edit:SetText(str)
		ioDialog.actionBtn:Hide()
		ioDialog.closeBtn:ClearAllPoints()
		ioDialog.closeBtn:SetPoint("BOTTOMRIGHT", -12, 10)
		ioDialog:Show()
		ioDialog.edit:SetFocus()
		ioDialog.edit:HighlightText()
	else
		ioDialog.title:SetText("Import — " .. label)
		ioDialog.hint:SetText("Paste a !MERLIN1! string (replaces " .. label .. ").")
		ioDialog.edit:SetText("")
		ioDialog.actionBtn:SetLabel("Import")
		ioDialog.actionBtn:SetScript("OnClick", function()
			local ok, err = Merlin.ImportProfile(ioDialog.edit:GetText(), target)
			if ok then
				ioDialog:Hide()
				ShowStatus("Imported into " .. label .. ".")
			else
				ShowStatus(err or "Import failed.")
			end
		end)
		ioDialog.actionBtn:Show()
		ioDialog.closeBtn:ClearAllPoints()
		ioDialog.closeBtn:SetPoint("RIGHT", ioDialog.actionBtn, "LEFT", -6, 0)
		ioDialog:Show()
		ioDialog.edit:SetFocus()
	end
end

-- Global Settings page (2-column)

local function BuildSettingsPage()
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
	ly = CreateSection(leftCol, ly, "Window")
	ly = CreateSliderRow(leftCol, ly, "Opacity", 0.5, 1.0, 0.02,
		function() return Merlin.db.windowOpacity end,
		function(v)
			Merlin.db.windowOpacity = v
			ApplyWindowOpacity()
		end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end
	)

	ly = ly - 6
	ly = CreateSection(leftCol, ly, "Appearance", function()
		local def = Merlin.defaults
		Merlin.db.fontName = def.fontName
		Merlin.db.fontOutline = def.fontOutline
		Merlin.db.iconZoom = def.iconZoom
		Merlin.db.borderSize = def.borderSize
	end)
	ly = CreateChoiceRow(leftCol, ly, "Font", Merlin.GetFontOptions,
		function() return Merlin.db.fontName end,
		function(v) Merlin.db.fontName = v end
	)
	ly = CreateChoiceRow(leftCol, ly, "Outline", OUTLINE_OPTS,
		function() return Merlin.db.fontOutline end,
		function(v) Merlin.db.fontOutline = v end
	)
	ly = CreateSliderRow(leftCol, ly, "Icon zoom", 0.0, 0.15, 0.01,
		function() return Merlin.db.iconZoom end,
		function(v) Merlin.db.iconZoom = v end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end
	)
	ly = CreateSliderRow(leftCol, ly, "Border px", 0, 3, 1,
		function() return Merlin.db.borderSize end,
		function(v) Merlin.db.borderSize = v end
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
	CreateSliderRow(leftCol, ly, "OOC alpha", 0.0, 1.0, 0.05,
		function() return Merlin.db.oocAlpha end,
		function(v) Merlin.db.oocAlpha = v end,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end
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

	ry = ry - 8
	ry = CreateSection(rightCol, ry, "Timer thresholds", function()
		Merlin.db.warnThreshold = Merlin.defaults.warnThreshold
		Merlin.db.urgentThreshold = Merlin.defaults.urgentThreshold
	end)
	ry = CreateSliderRow(rightCol, ry, "Warn (s)", 5, 60, 1,
		function() return Merlin.db.warnThreshold end,
		function(v) Merlin.db.warnThreshold = v end
	)
	ry = CreateSliderRow(rightCol, ry, "Urgent (s)", 1, 15, 1,
		function() return Merlin.db.urgentThreshold end,
		function(v) Merlin.db.urgentThreshold = v end
	)

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
		function(v) ioTarget = v end
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

	return page
end

-- Sidebar & window chrome

local function SelectPage(key)
	activePage = key
	CloseMenu()
	for k, p in pairs(pages) do
		p:SetShown(k == key)
	end
	for _, b in ipairs(navButtons) do
		if b.pageKey then
			b:SetActive(b.pageKey == key)
		end
	end
end

AttachTip = function(frame, titleFn, bodyFn)
	frame:HookScript("OnEnter", function(self)
		local title = titleFn
		if type(title) == "function" then
			title = title()
		end
		if type(title) ~= "string" or title == "" then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		local body = bodyFn
		if type(body) == "function" then
			body = body()
		end
		if type(body) == "string" and body ~= "" then
			GameTooltip:AddLine(body, 0.75, 0.75, 0.75, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function()
		if GameTooltip:IsOwned(frame) then
			GameTooltip:Hide()
		end
	end)
end

local MEDIA_ICONS = "Interface\\AddOns\\Merlin\\Media\\Icons\\"
local GLYPH_TEX_W, GLYPH_TEX_H, GLYPH_BIG = 256, 64, 64
local GLYPH_SIZES = { 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32 }
local GLYPH_SLOT = {
	[10] = { 66, 2 },
	[11] = { 78, 2 },
	[12] = { 91, 2 },
	[13] = { 105, 2 },
	[14] = { 120, 2 },
	[15] = { 136, 2 },
	[16] = { 153, 2 },
	[18] = { 171, 2 },
	[20] = { 191, 2 },
	[22] = { 213, 2 },
	[24] = { 66, 26 },
	[28] = { 92, 26 },
	[32] = { 122, 26 },
	[64] = { 0, 0 },
}

local function GlyphPixels(f, size)
	if not GetPhysicalScreenSize then
		return nil
	end
	local _, height = GetPhysicalScreenSize()
	if not height or height <= 0 then
		return nil
	end
	return math.floor(size * f:GetEffectiveScale() * height / 768 + 0.5)
end

local function BestGlyphSize(px)
	if not px then
		return nil
	end
	for _, n in ipairs(GLYPH_SIZES) do
		if n >= px then
			return n
		end
	end
	return nil
end

CreateGlyph = function(parent, key, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size or 16, size or 16)
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	f.texture = icon
	local current, currentPx

	function f:Draw(name, color)
		local px = GlyphPixels(f, f:GetWidth())
		if current ~= name or currentPx ~= px then
			local n = BestGlyphSize(px) or GLYPH_BIG
			local slot = GLYPH_SLOT[n]
			icon:SetTexture(MEDIA_ICONS .. name .. ".tga")
			icon:SetTexCoord(slot[1] / GLYPH_TEX_W, (slot[1] + n) / GLYPH_TEX_W,
				slot[2] / GLYPH_TEX_H, (slot[2] + n) / GLYPH_TEX_H)
			current, currentPx = name, px
		end
		local c = color or T.muted
		f.color = c
		icon:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end

	f:SetScript("OnShow", function()
		if current then
			f:Draw(current, f.color)
		end
	end)
	f:Draw(key, T.muted)
	return f
end

local function CreateNavItem(parent, label, glyphKey, onClick)
	local b = CreateButton(parent, label, NAV_W - 8, 32, true)
	b.fullLabel = label
	b.glyphKey = glyphKey
	b.glyph = CreateGlyph(b, glyphKey, 16)
	b.glyph:SetPoint("LEFT", 6, 0)
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", 26, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	b:SetTextColor(T.muted)

	local basePaint = b.Paint
	b.Paint = function()
		basePaint()
		local c = b.disabled and T.faint or b.active and T.accent or b.hover and T.text or T.muted
		b.glyph:Draw(b.glyphKey, c)
	end
	b:HookScript("OnEnter", function() b.Paint() end)
	b:HookScript("OnLeave", function() b.Paint() end)
	b:SetScript("OnClick", onClick)
	AttachTip(b, function()
		return Merlin.db and Merlin.db.navCollapsed and b.fullLabel or nil
	end)
	navButtons[#navButtons + 1] = b
	return b
end

local function LayoutNav()
	if not nav or not window then
		return
	end
	local collapsed = Merlin.db and Merlin.db.navCollapsed and true or false
	local w = collapsed and NAV_COLLAPSED or NAV_W
	nav:SetWidth(w)
	window:SetWidth(WIDTH - (NAV_W - w))
	for _, b in ipairs(navButtons) do
		b:SetWidth(w - 8)
		b:SetLabel(collapsed and "" or b.fullLabel)
		b.label:ClearAllPoints()
		b.glyph:ClearAllPoints()
		b.glyph:SetSize(collapsed and 20 or 16, collapsed and 20 or 16)
		if collapsed then
			b.label:SetPoint("CENTER")
			b.glyph:SetPoint("CENTER")
		else
			b.glyph:SetPoint("LEFT", 6, 0)
			b.label:SetPoint("LEFT", 26, 0)
			b.label:SetJustifyH("LEFT")
		end
		b.Paint()
	end
	if nav.groupsLbl then
		nav.groupsLbl:SetShown(not collapsed)
	end
	if nav.toggle then
		nav.toggle:SetWidth(w - 8)
		nav.toggle:SetLabel("")
		nav.toggle.glyphKey = collapsed and "expand" or "collapse"
		nav.toggle.glyph:SetSize(16, 16)
		nav.toggle.glyph:ClearAllPoints()
		if collapsed then
			nav.toggle.glyph:SetPoint("CENTER")
		else
			nav.toggle.glyph:SetPoint("RIGHT", -1, 0)
		end
		nav.toggle.Paint()
	end
end

local function CreateOptionsWindow()
	local ar, ag, ab = Merlin.GetMutedClassColor()
	T.accent[1], T.accent[2], T.accent[3], T.accent[4] = ar, ag, ab, 1

	window = CreateFrame("Frame", "MerlinOptionsFrame", UIParent)
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetScript("OnHide", function()
		CloseMenu()
		if ioDialog then
			ioDialog:Hide()
		end
	end)
	Panel(window, T.window)
	ApplyWindowOpacity()
	AddShadow(window, 12, 0.9)

	-- Floating wordmark across the top edge: class-colored diamond bookends + white Merlin
	local wordmark = "|cffffffffMerlin|r"
	for ring = 1, 2 do
		for i = 0, 7 do
			local angle = i * math.pi / 4
			local halo = window:CreateFontString(nil, "BACKGROUND")
			halo:SetFont(STANDARD_TEXT_FONT, 30, "")
			halo:SetJustifyH("CENTER")
			halo:SetPoint("CENTER", window, "TOP",
				-1 + math.cos(angle) * ring * 2, 2 + math.sin(angle) * ring * 2)
			halo:SetTextColor(0, 0, 0, 0.16 / ring)
			halo:SetText("Merlin")
		end
	end
	for _, offset in ipairs({ { -0.45, 0 }, { 0.45, 0 }, { 0, -0.45 }, { 0, 0.45 } }) do
		local weight = Text(window, wordmark, "GameFontHighlightLarge", T.text)
		weight:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE")
		weight:SetJustifyH("CENTER")
		weight:SetPoint("CENTER", window, "TOP", offset[1], 2 + offset[2])
	end
	local title = Text(window, wordmark, "GameFontHighlightLarge", T.text)
	title:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE")
	title:SetJustifyH("CENTER")
	title:SetPoint("CENTER", window, "TOP", 0, 2)

	local cr, cg, cb = Merlin.GetClassColor()
	local diag = math.rad(45)
	for _, side in ipairs({
		{ point = "RIGHT", relPoint = "LEFT", ox = -10 },
		{ point = "LEFT", relPoint = "RIGHT", ox = 10 },
	}) do
		local outline = window:CreateTexture(nil, "OVERLAY", nil, 0)
		outline:SetSize(10, 10)
		outline:SetTexture(WHITE)
		outline:SetVertexColor(0, 0, 0, 0.9)
		outline:SetRotation(diag)
		outline:SetPoint(side.point, title, side.relPoint, side.ox, -1)

		local diamond = window:CreateTexture(nil, "OVERLAY", nil, 1)
		diamond:SetSize(7, 7)
		diamond:SetTexture(WHITE)
		diamond:SetVertexColor(cr, cg, cb, 1)
		diamond:SetRotation(diag)
		diamond:SetPoint("CENTER", outline, "CENTER")
	end

	-- Left sidebar
	nav = CreateFrame("Frame", nil, window)
	nav:SetPoint("TOPLEFT")
	nav:SetPoint("BOTTOMLEFT")
	nav:SetWidth(NAV_W)
	Panel(nav, T.sidebar)

	local groupsLbl = Text(nav, "Groups", "GameFontHighlightSmall", T.faint)
	groupsLbl:SetPoint("TOPLEFT", 10, -14)
	nav.groupsLbl = groupsLbl

	local buffsNav = CreateNavItem(nav, "Buffs", "buffs", function() SelectPage("buffs") end)
	buffsNav.pageKey = "buffs"
	buffsNav:SetPoint("TOPLEFT", 4, -34)

	local debuffsNav = CreateNavItem(nav, "Debuffs", "debuffs", function() SelectPage("debuffs") end)
	debuffsNav.pageKey = "debuffs"
	debuffsNav:SetPoint("TOPLEFT", 4, -68)

	local externalsNav = CreateNavItem(nav, "Externals", "externals", function() SelectPage("externals") end)
	externalsNav.pageKey = "externals"
	externalsNav:SetPoint("TOPLEFT", 4, -102)

	local enchantsNav = CreateNavItem(nav, "Enchants", "enchants", function() SelectPage("enchants") end)
	enchantsNav.pageKey = "enchants"
	enchantsNav:SetPoint("TOPLEFT", 4, -136)

	local settingsNav = CreateNavItem(nav, "Settings", "settings", function() SelectPage("settings") end)
	settingsNav.pageKey = "settings"
	settingsNav:SetPoint("BOTTOMLEFT", 4, 10)

	local lockNav = CreateNavItem(nav, "Locked", "locked", function()
		if InCombatLockdown() then
			return
		end
		Merlin.db.locked = not Merlin.db.locked
		Merlin.RequestRefresh()
		Merlin.RefreshOptions()
	end)
	lockNav:SetPoint("BOTTOMLEFT", settingsNav, "TOPLEFT", 0, 2)
	AttachTip(lockNav,
		function() return Merlin.db.locked and "Locked" or "Unlocked" end,
		function() return Merlin.db.locked and "Unlock aura movers." or "Lock aura movers." end
	)
	refreshFns[#refreshFns + 1] = function()
		local locked = Merlin.db.locked
		lockNav.fullLabel = locked and "Locked" or "Unlocked"
		lockNav.glyphKey = locked and "locked" or "unlocked"
		lockNav:SetActive(not locked)
		LayoutNav()
	end

	local sep = Fill(nav, T.control)
	sep:ClearAllPoints()
	sep:SetPoint("BOTTOMLEFT", lockNav, "TOPLEFT", 8, 4)
	sep:SetPoint("BOTTOMRIGHT", lockNav, "TOPRIGHT", -8, 4)
	sep:SetHeight(1)

	local toggleNav = CreateButton(nav, "", NAV_W - 8, 32, true)
	toggleNav:SetPoint("BOTTOMLEFT", lockNav, "TOPLEFT", 0, 9)
	toggleNav:SetTextColor(T.muted)
	toggleNav.glyphKey = "collapse"
	toggleNav.glyph = CreateGlyph(toggleNav, "collapse", 16)
	local toggleBasePaint = toggleNav.Paint
	toggleNav.Paint = function()
		toggleBasePaint()
		toggleNav.glyph:Draw(toggleNav.glyphKey, toggleNav.hover and T.text or T.muted)
	end
	toggleNav:HookScript("OnEnter", function() toggleNav.Paint() end)
	toggleNav:HookScript("OnLeave", function() toggleNav.Paint() end)
	toggleNav:SetScript("OnClick", function()
		Merlin.db.navCollapsed = not Merlin.db.navCollapsed
		LayoutNav()
	end)
	AttachTip(toggleNav, function()
		return Merlin.db and Merlin.db.navCollapsed and "Expand sidebar" or "Collapse sidebar"
	end)
	nav.toggle = toggleNav

	-- Main content area
	main = CreateFrame("Frame", nil, window)
	main:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
	main:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)

	local closeBtn = CreateFrame("Button", nil, window)
	closeBtn:SetSize(16, 16)
	closeBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
	closeBtn:SetFrameLevel(window:GetFrameLevel() + 30)
	Fill(closeBtn, { 0.3, 0.3, 0.3, 0.25 })
	local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
	closeIcon:SetAllPoints()
	closeIcon:SetTexture(MEDIA_ICONS .. "close.tga")
	local closeHover, closePressed = false, false
	local function PaintClose()
		if not closeBtn:IsEnabled() then
			closeIcon:SetVertexColor(0.5, 0.5, 0.5)
		elseif closeHover or closePressed then
			closeIcon:SetVertexColor(1, 0, 0)
		else
			closeIcon:SetVertexColor(1, 1, 1)
		end
	end
	closeBtn:SetScript("OnEnter", function() closeHover = true; PaintClose() end)
	closeBtn:SetScript("OnLeave", function() closeHover = false; PaintClose() end)
	closeBtn:SetScript("OnMouseDown", function() closePressed = true; PaintClose() end)
	closeBtn:SetScript("OnMouseUp", function() closePressed = false; PaintClose() end)
	closeBtn:SetScript("OnEnable", PaintClose)
	closeBtn:SetScript("OnDisable", PaintClose)
	closeBtn:SetScript("OnHide", function()
		closeHover, closePressed = false, false
		PaintClose()
	end)
	closeBtn:SetScript("OnClick", function() window:Hide() end)
	PaintClose()

	statusFrame = CreateFrame("Frame", nil, window)
	statusFrame:SetHeight(22)
	statusFrame:SetPoint("TOP", window, "BOTTOM", 0, -6)
	statusFrame:SetFrameLevel(window:GetFrameLevel() + 20)
	Panel(statusFrame, T.popup)
	statusText = Text(statusFrame, "", "GameFontHighlightSmall", T.accent)
	statusText:SetPoint("CENTER")
	statusFrame:Hide()

	pages.buffs = BuildGroupPage("buffs", "Buffs", true)
	pages.debuffs = BuildGroupPage("debuffs", "Debuffs", false)
	pages.externals = BuildGroupPage("externals", "Externals", false)
	pages.enchants = BuildGroupPage("enchants", "Enchants", false)
	pages.settings = BuildSettingsPage()

	SelectPage(activePage)
	window:Hide()
	if UISpecialFrames then
		UISpecialFrames[#UISpecialFrames + 1] = "MerlinOptionsFrame"
	end
	Merlin.RegisterRefresh(function()
		if window and window:IsShown() then
			Merlin.RefreshOptions()
		end
	end)
end

function Merlin.RefreshOptions()
	if not window then
		return
	end
	ApplyWindowOpacity()
	for _, fn in ipairs(refreshFns) do
		fn()
	end
end

function Merlin.CloseOptions()
	CloseMenu()
	if window and window:IsShown() then
		window:Hide()
	end
end

function Merlin.ToggleOptions()
	if InCombatLockdown() then
		Merlin.Print("Options are unavailable in combat.")
		return
	end
	if not window then
		CreateOptionsWindow()
	end
	if window:IsShown() then
		window:Hide()
	else
		Merlin.RefreshOptions()
		window:Show()
	end
end
