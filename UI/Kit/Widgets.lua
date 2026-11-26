-- UI/Kit/Widgets.lua
-- Flat borderless controls, compact 40/60 form rows, scrollable popup menus,
-- tabbed option panels, and stacked forms.

local _, ns = ...
local UI = ns.UI
local T = UI.T
local setColor = UI.SetColor

--------------------------------------------------------------------------------
-- Buttons & headings
--------------------------------------------------------------------------------

-- A flat button: transparent = no fill until hovered.
-- opts: { dimByParent = bool, action = bool (InsecureActionButtonTemplate) }
function UI.button(parent, label, w, h, transparent, opts)
    local template = opts and opts.action and "InsecureActionButtonTemplate" or nil
    local b = CreateFrame("Button", nil, parent, template)
    if opts and opts.action then
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
    end
    b:SetSize(w or 80, h or 26)
    UI.panel(b, transparent and T.none or T.control)
    b.label = UI.text(b, label, "GameFontHighlight")
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.textColor = T.text
    b.dimByParent = opts and opts.dimByParent or nil

    local function paint()
        if b.disabled then
            UI.shade(b, b.base)
            b.label:SetTextColor(unpack(b.dimByParent and b.textColor or T.faint))
            return
        end
        if b.hover then
            UI.shade(b, T.hover)
        elseif b.active then
            UI.shade(b, transparent and UI.rgb("#ffffff", 0.06) or T.pressed)
        else
            UI.shade(b, b.base)
        end
        b.label:SetTextColor(unpack(b.active and T.accent or b.textColor))
    end
    b.Paint = paint
    UI.accentButtons[b] = true

    function b.SetLabel(_, s)
        b.label:SetText(s)
    end
    function b.SetActive(_, on)
        b.active = on and true or nil
        paint()
    end
    function b.SetTextColor(_, c)
        b.textColor = c
        paint()
    end
    function b.SetDisabled(_, off)
        b.disabled = off and true or nil
        b:EnableMouse(not off)
        paint()
    end

    b:SetScript("OnEnter", function()
        b.hover = true
        paint()
    end)
    b:SetScript("OnLeave", function()
        b.hover = nil
        paint()
    end)
    b:SetScript("OnHide", function()
        if b.hover then
            b.hover = nil
            paint()
        end
    end)
    return b
end

-- Forever blocks direct addon ReloadUI() calls; a real hardware click on an
-- InsecureActionButtonTemplate running `/reload` works cleanly out of combat.
-- Optional onBeforeReload() runs in PreClick and cancels reload if it returns false.
function UI.reloadButton(parent, label, w, h, onBeforeReload)
    local b = UI.button(parent, label or "Reload", w or 110, h or 24, false, { action = true })
    b:SetAttribute("type", "macro")
    b:SetScript("PreClick", function(self)
        if not InCombatLockdown() then
            self:SetAttribute("macrotext", nil)
        end
        if self.disabled or UI.IsRestricted() then
            return
        end
        if onBeforeReload and onBeforeReload() == false then
            return
        end
        self:SetAttribute("macrotext", "/reload")
    end)
    b:SetScript("PostClick", function(self)
        if not InCombatLockdown() then
            self:SetAttribute("macrotext", nil)
        end
    end)
    return b
end

-- Reset arrow beside a widget: puts that widget back to its default.
function UI.resetButton(parent, w, h, onClick)
    local b = UI.button(parent, "", w or 18, h or w or 18, true)
    local glyph = UI.Glyph(b, "reset", 12)
    glyph:SetPoint("CENTER")
    local function paint()
        glyph:Draw("reset", b.disabled and T.faint or b.hover and T.accent or T.muted)
    end
    b:HookScript("OnEnter", paint)
    b:HookScript("OnLeave", paint)
    b:HookScript("OnHide", paint)
    b:SetScript("OnClick", function()
        if b.disabled or UI.WritesBlocked() then
            return
        end
        if onClick then
            onClick()
        end
    end)
    function b.SetChanged(_, changed)
        b:SetDisabled(not changed)
        paint()
    end
    b:SetChanged(false)
    return b
end

-- Two-click confirmation button (tokenized timeout + OnHide disarm).
function UI.armedButton(parent, label, w, run, color, opts)
    opts = opts or {}
    local b = UI.button(parent, label, w, opts.height or 24)
    if color then
        b:SetTextColor(color)
    end
    local function disarm()
        b.armToken = nil
        b:SetLabel(label)
        b:SetTextColor(color or T.text)
    end
    b:SetScript("OnClick", function()
        if b.disabled or UI.WritesBlocked() then
            return
        end
        if not b.armToken then
            local token = {}
            b.armToken = token
            b:SetLabel(opts.confirmLabel or "Click again")
            b:SetTextColor(T.danger)
            C_Timer.After(opts.timeout or 3, function()
                if b.armToken == token then
                    disarm()
                end
            end)
            return
        end
        disarm()
        run()
    end)
    b:HookScript("OnHide", disarm)
    return b
end

-- Section heading, accent coloured, with optional right-aligned reset glyph.
-- opts: { onReset = fn, resetTip = string, isChanged = fn }
function UI.heading(parent, s, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 20)
    f.label = UI.text(f, s, "GameFontHighlight", T.accent)
    f.label:SetPoint("LEFT")
    local reset
    if opts and opts.onReset then
        reset = UI.resetButton(f, 16, 16, opts.onReset)
        reset:SetPoint("RIGHT")
        f.reset = reset
        if opts.resetTip then
            UI.tip(reset, opts.resetTip)
        elseif type(s) == "string" and s ~= "" then
            UI.tip(reset, "Reset " .. s:lower())
        end
    end
    function f.Refresh()
        if reset then
            reset:SetChanged(not opts.isChanged or opts.isChanged())
        end
    end
    return f
end

-- Wrapped muted text; s may be a function (re-read on Refresh).
function UI.help(parent, s, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width or 300)
    f.label = UI.text(f, "", "GameFontHighlightSmall", T.muted)
    f.label:SetPoint("TOPLEFT")
    f.label:SetJustifyV("TOP")
    f.label:SetSpacing(2)
    f.label:SetWordWrap(true)
    function f.Refresh()
        -- Slight width margin prevents premature ellipsis mid-paragraph.
        f.label:SetWidth(math.max(1, f:GetWidth() - 4))
        f.label:SetText(type(s) == "function" and s() or s)
        f:SetHeight(math.max(f.label:GetStringHeight(), 12) + 4)
    end
    return f
end

-- Standardised page header: large title and optional muted subtitle.
function UI.pageHeader(parent, titleText, subtitleText)
    local title = UI.text(parent, titleText or "", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", UI.PAD, UI.HEADER_Y)
    local subtitle
    if subtitleText ~= nil then
        subtitle = UI.text(parent, subtitleText, "GameFontHighlightSmall", T.muted)
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetWordWrap(false)
    end
    return title, subtitle
end

--------------------------------------------------------------------------------
-- Shared scrollable popup menu
--------------------------------------------------------------------------------

local MAX_MENU_ITEMS = 12
local MENU_ITEM_H = 20
local menu, catcher

function UI.CloseMenu()
    if menu then
        menu:Hide()
    end
end

local function ensureMenu()
    if menu then
        return
    end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:Hide()

    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    UI.panel(menu, T.popup)
    UI.shadow(menu, 6, 0.7)
    menu.items = {}
    menu.measure = UI.text(menu, "", "GameFontHighlight")
    menu.measure:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, menu)
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -2, 2)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    menu.scroll = scroll
    menu.content = content

    local track = CreateFrame("Frame", nil, menu)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", -3, -3)
    track:SetPoint("BOTTOMRIGHT", -3, 3)
    UI.fill(track, T.control)
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(4)
    setColor(thumb, T.accent, 0.7)
    UI.OnAccent(function() setColor(thumb, T.accent, 0.7) end)
    menu.track = track
    menu.thumb = thumb

    function menu.SetScrollOffset(_, offset)
        local maxS = menu.maxScroll or 0
        local clamped = math.max(0, math.min(maxS, offset or 0))
        menu.scrollOffset = clamped
        scroll:SetVerticalScroll(clamped)
        if maxS > 0 then
            local trackH = track:GetHeight()
            local viewH = menu.viewH or (MAX_MENU_ITEMS * MENU_ITEM_H)
            local totalH = menu.totalH or (viewH + maxS)
            local thumbH = math.max(18, math.floor(trackH * (viewH / totalH) + 0.5))
            local travel = math.max(0, trackH - thumbH)
            local yOff = math.floor(travel * (clamped / maxS) + 0.5)
            thumb:ClearAllPoints()
            thumb:SetHeight(thumbH)
            thumb:SetPoint("TOP", track, "TOP", 0, -yOff)
        end
    end

    menu:SetScript("OnMouseWheel", function(self, delta)
        local maxS = self.maxScroll or 0
        if maxS <= 0 then
            return
        end
        self:SetScrollOffset((self.scrollOffset or 0) - delta * (self.itemH or MENU_ITEM_H) * 3)
    end)

    catcher:SetScript("OnClick", function()
        menu:Hide()
    end)
    menu:SetScript("OnHide", function()
        catcher:Hide()
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end)
end

-- options: { { label, store, tip?, tipTitle?, disabled?, divider? }, ... }
-- optsOrOpenUp: boolean (`openUp`) or `{ openUp = bool, maxItems = 12, itemHeight = 20 }`
local function openMenu(anchor, options, current, pick, optsOrOpenUp)
    ensureMenu()
    local opts = type(optsOrOpenUp) == "table" and optsOrOpenUp or { openUp = optsOrOpenUp == true }
    local maxItems = opts.maxItems or MAX_MENU_ITEMS
    local itemH = opts.itemHeight or MENU_ITEM_H
    local openUp = opts.openUp == true

    local width = math.max(anchor:GetWidth(), 140)
    for _, o in ipairs(options) do
        if o.label then
            menu.measure:SetText(o.label)
            width = math.max(width, math.ceil(menu.measure:GetStringWidth()) + 20)
        end
    end

    local count = #options
    local needsScroll = count > maxItems
    local totalH = 0
    for _, o in ipairs(options) do
        totalH = totalH + (o.divider and 7 or itemH)
    end
    local viewH = needsScroll and (maxItems * itemH) or totalH
    local scrollW = width - 4
    local menuW = width + (needsScroll and 8 or 0)

    menu.scroll:ClearAllPoints()
    menu.scroll:SetPoint("TOPLEFT", 2, -2)
    menu.scroll:SetPoint("BOTTOMRIGHT", needsScroll and -10 or -2, 2)
    menu.content:SetSize(scrollW, math.max(1, totalH))
    menu.track:SetShown(needsScroll)
    menu.thumb:SetShown(needsScroll)
    menu.viewH = viewH
    menu.totalH = totalH
    menu.itemH = itemH
    menu.maxScroll = needsScroll and math.max(0, totalH - viewH) or 0

    menu.pick = pick
    local y, currentIdx = 0, 1
    for i, o in ipairs(options) do
        local item = menu.items[i]
        if not item then
            item = CreateFrame("Button", nil, menu.content)
            item.bg = UI.fill(item, T.black, 0)
            item.label = UI.text(item, "", "GameFontHighlight")
            item.label:SetPoint("LEFT", 8, 0)
            item.rule = item:CreateTexture(nil, "ARTWORK")
            item.rule:SetPoint("LEFT", 6, 0)
            item.rule:SetPoint("RIGHT", -6, 0)
            item.rule:SetHeight(1)
            setColor(item.rule, T.control)
            item.rule:Hide()
            item:SetScript("OnEnter", function(self)
                if not self.disabled and not self.isDivider then
                    setColor(self.bg, T.hover)
                end
                if self.tipText and self.tipText ~= "" then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if self.tipTitle and self.tipTitle ~= "" then
                        GameTooltip:SetText(self.tipTitle, 1, 1, 1)
                        GameTooltip:AddLine(self.tipText, 0.85, 0.85, 0.85, true)
                    else
                        GameTooltip:SetText(self.tipText, 1, 1, 1, 1, true)
                    end
                    GameTooltip:Show()
                end
            end)
            item:SetScript("OnLeave", function(self)
                setColor(self.bg, T.black, 0)
                if GameTooltip:IsOwned(self) then
                    GameTooltip:Hide()
                end
            end)
            item:SetScript("OnClick", function(self)
                if self.disabled or self.isDivider or UI.WritesBlocked() then
                    return
                end
                menu:Hide()
                if menu.pick then
                    menu.pick(self.store)
                end
            end)
            menu.items[i] = item
        end
        local rowH = o.divider and 7 or itemH
        item:SetSize(scrollW, rowH)
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 0, -y)
        y = y + rowH
        item.isDivider = o.divider and true or false
        item.rule:SetShown(item.isDivider)
        item.label:SetShown(not item.isDivider)
        item:EnableMouse(not item.isDivider)
        setColor(item.bg, T.black, 0)
        if item.isDivider then
            item.disabled = true
            item.tipText = nil
            item.tipTitle = nil
            item.store = nil
        else
            item.label:SetText(o.label or "")
            item.disabled = o.disabled
            item.tipText = o.tip
            item.tipTitle = o.tipTitle
            item.store = o.store
            if o.store == current then
                currentIdx = i
            end
            local color = o.disabled and T.faint or (o.store == current and T.accent or T.text)
            item.label:SetTextColor(unpack(color))
        end
        item:Show()
    end
    for i = count + 1, #menu.items do
        menu.items[i]:Hide()
    end
    menu:SetSize(menuW, math.max(1, viewH) + 4)
    menu:ClearAllPoints()
    if openUp then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    catcher:Show()
    menu:Show()
    local initOffset = needsScroll and ((currentIdx - math.floor(maxItems / 2)) * itemH) or 0
    menu:SetScrollOffset(initOffset)
end
UI.OpenMenu = openMenu

--------------------------------------------------------------------------------
-- 40/60 column layout helper
--------------------------------------------------------------------------------

local function columns(row, control)
    local width = math.max(row:GetWidth(), 1)
    row.label:SetFontObject((row.stacked or row.compact) and "GameFontHighlightSmall" or "GameFontHighlight")
    if row.stacked then
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT")
        row.label:SetWidth(width)
        row.label:SetWordWrap(false)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        control:SetWidth(width)
        row:SetHeight(row.label:GetStringHeight() + 2 + control:GetHeight())
        return
    end
    control:SetWidth(row.labelWidth and math.max(1, width - row.labelWidth - 4) or width * 0.6)
    control:ClearAllPoints()
    control:SetPoint("RIGHT")
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT")
    row.label:SetWidth(row.labelWidth or math.max(1, width * 0.4 - 8))
    row.label:SetWordWrap(not row.compact)
    local minH = row.minHeight or (row.compact and UI.ROW or 35)
    row:SetHeight(row.compact and minH or math.max(minH, row.label:GetStringHeight() + 4))
end

function UI.compact(widget, height)
    widget.compact = true
    widget.minHeight = height or UI.ROW
    widget:SetHeight(widget.minHeight)
    if widget.label then
        widget.label:SetFontObject("GameFontHighlightSmall")
        widget.label:SetWordWrap(false)
    end
    if widget.button and widget.button.label then
        widget.button.label:SetFontObject("GameFontHighlightSmall")
    end
    return widget
end

--------------------------------------------------------------------------------
-- Form inputs
--------------------------------------------------------------------------------

-- A square checkbox and its label.
function UI.checkbox(parent, label, get, set, width, desc, boxSize)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(width or 300, 24)
    local box = CreateFrame("Frame", nil, f)
    local size = boxSize or 16
    box:SetSize(size, size)
    box:SetPoint("LEFT")
    UI.panel(box, T.control)
    local mark = box:CreateTexture(nil, "ARTWORK")
    local inset = size < 12 and 2 or size == 12 and 3 or 4
    mark:SetPoint("TOPLEFT", inset, -inset)
    mark:SetPoint("BOTTOMRIGHT", -inset, inset)
    setColor(mark, T.accent)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(box)
    setColor(hl, T.text, 0.1)
    f.label = UI.text(f, label)
    f.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    f.label:SetPoint("RIGHT")
    function f.Refresh()
        mark:SetShown(get() and true or false)
    end
    function f.SetDisabled(_, off)
        f.disabled = off and true or nil
        f:SetAlpha(off and 0.45 or 1)
        f:EnableMouse(not off)
    end
    f:SetScript("OnClick", function()
        if f.disabled or UI.WritesBlocked() then
            return
        end
        set(not get())
        f.Refresh()
    end)
    if desc then
        UI.tip(f, label, desc)
    end
    return f
end

-- Standardised 40/60 compact checkbox row.
function UI.checkRow(parent, label, get, set, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(opts.height or UI.ROW)
    row.label = UI.text(row, label, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT")
    row.label:SetWordWrap(false)
    local box = UI.checkbox(row, "", get, set)
    row.box = box
    box:SetPoint("RIGHT")
    function row.SetDisabled(_, off)
        row.disabled = off and true or nil
        box:SetDisabled(off)
        row.label:SetAlpha(off and 0.45 or 1)
    end
    function row.Refresh()
        local disabled = row.disabled or (opts.disabled and opts.disabled())
        row.label:SetWidth(math.max(1, row:GetWidth() * 0.4 - 4))
        box:SetWidth(row:GetWidth() * 0.6)
        box:SetDisabled(disabled)
        box.Refresh()
        row.label:SetAlpha(disabled and 0.45 or 1)
    end
    UI.tip(row, label, opts.tip or label)
    return row
end

-- Paired checkboxes side-by-side on one row.
-- opts: { height = UI.ROW, split = 0.5, compact = true, disabledA = fn, disabledB = fn, tipA = str, tipB = str }
function UI.checkPairRow(parent, labelA, getA, setA, labelB, getB, setB, opts)
    opts = opts or {}
    local h = opts.height or UI.ROW
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, h)
    local a = UI.checkbox(row, labelA, getA, setA, 140, opts.tipA, opts.boxSize)
    local b = UI.checkbox(row, labelB, getB, setB, 140, opts.tipB, opts.boxSize)
    if opts.compact ~= false then
        a.label:SetFontObject("GameFontHighlightSmall")
        b.label:SetFontObject("GameFontHighlightSmall")
        a.label:SetWordWrap(false)
        b.label:SetWordWrap(false)
    end
    a:SetHeight(h)
    b:SetHeight(h)
    row.left, row.right = a, b
    function row.SetDisabled(_, off)
        row.disabled = off and true or nil
        row.Refresh()
    end
    function row.Refresh()
        local width = math.max(1, row:GetWidth())
        local split = opts.split or 0.5
        local wA = math.max(1, width * split - 4)
        local wB = math.max(1, width - wA - 8)
        a:ClearAllPoints()
        a:SetPoint("LEFT")
        a:SetWidth(wA)
        b:ClearAllPoints()
        b:SetPoint("RIGHT")
        b:SetWidth(wB)
        a:SetDisabled(row.disabled or (opts.disabledA and opts.disabledA()))
        b:SetDisabled(row.disabled or (opts.disabledB and opts.disabledB()))
        a.Refresh()
        b.Refresh()
    end
    return row
end

-- Vertical or horizontal radio option list using `radio` / `radio-dot` glyphs.
-- options: { { label = "...", store = value, tip = "..." }, ... }
-- opts: { horizontal = bool, rowHeight = 24, gap = 2, compact = bool }
function UI.radioGroup(parent, options, get, set, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, opts.rowHeight or 24)
    local rows = {}
    local rowH = opts.rowHeight or 24
    local gap = opts.gap or 2

    local function optionList()
        return type(options) == "function" and options() or options
    end

    local function ensureRow(i)
        local r = rows[i]
        if r then
            return r
        end
        local b = UI.button(f, "", 100, rowH, true)
        local circle = UI.Glyph(b, "radio", 16)
        circle:SetPoint("LEFT")
        local dot = UI.Glyph(b, "radio-dot", 16)
        dot:SetAllPoints(circle)
        dot:Draw("radio-dot", T.accent)
        b.label:SetFontObject(opts.compact and "GameFontHighlightSmall" or "GameFontHighlight")
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", circle, "RIGHT", 8, 0)
        b.label:SetPoint("RIGHT")
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        b:SetScript("OnClick", function(self)
            if f.disabled or self.disabled or UI.WritesBlocked() then
                return
            end
            set(self.store)
            f.Refresh()
        end)
        UI.tip(b, function() return b.tipTitle end, function() return b.tipBody end)
        r = { button = b, circle = circle, dot = dot }
        rows[i] = r
        return r
    end

    function f.SetDisabled(_, off)
        f.disabled = off and true or nil
        f:SetAlpha(off and 0.45 or 1)
        f.Refresh()
    end

    function f.Refresh()
        local list = optionList()
        local current = get()
        local width = math.max(1, f:GetWidth())
        local count = #list
        for i, opt in ipairs(list) do
            local r = ensureRow(i)
            local b = r.button
            b.store = opt.store
            b.tipTitle = opt.tip and opt.label or nil
            b.tipBody = opt.tip
            b:SetLabel(opt.label)
            b:SetDisabled(f.disabled or opt.disabled)
            r.dot:SetShown(current == opt.store)
            b:ClearAllPoints()
            if opts.horizontal then
                local cellW = math.max(1, (width - (count - 1) * gap) / math.max(1, count))
                b:SetPoint("TOPLEFT", (i - 1) * (cellW + gap), 0)
                b:SetSize(cellW, rowH)
            else
                b:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + gap))
                b:SetSize(width, rowH)
            end
            b:Show()
        end
        for i = count + 1, #rows do
            rows[i].button:Hide()
        end
        f:SetHeight(opts.horizontal and rowH or math.max(rowH, count * rowH + math.max(0, count - 1) * gap))
    end
    f.rows = rows
    return f
end

-- Labelled dropdown choice.
function UI.choice(parent, label, options, get, set, width, buttonWidth, inheritTip, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 300, 35)
    f.label = UI.text(f, label)
    f.label:SetPoint("LEFT")
    local b = UI.button(f, "", buttonWidth or 130, 22)
    b:SetPoint("RIGHT")
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -22, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    local caret = UI.Glyph(b, "chevron", 10)
    caret:SetPoint("RIGHT", -8, 0)
    f.button, f.caret = b, caret

    local function listOpts()
        return type(options) == "function" and options() or options
    end

    function f.SetDisabled(_, off)
        f.disabled = off and true or nil
        f:SetAlpha(off and 0.45 or 1)
        b:SetDisabled(off)
    end

    function f.Refresh()
        local off = f.disabled or (opts.disabled and opts.disabled())
        f:SetAlpha(off and 0.45 or 1)
        b:SetDisabled(off)
        local v, shown, optTip = get(), "?", nil
        for _, o in ipairs(listOpts()) do
            if o.store == v then
                shown = o.label
                optTip = o.tip
            end
        end
        b:SetLabel(shown)
        f.activeTip = optTip
        f.activeLabel = shown
        columns(f, b)
    end

    b:SetScript("OnClick", function()
        if b.disabled or UI.WritesBlocked() then
            return
        end
        openMenu(b, listOpts(), get(), function(store)
            set(store)
            f.Refresh()
        end, opts)
    end)

    if inheritTip then
        UI.tip(b, function()
            if get() == nil then
                return inheritTip
            end
            return f.activeTip and f.activeLabel or nil
        end, function()
            return get() ~= nil and f.activeTip or nil
        end)
    else
        UI.tip(b, function()
            return f.activeTip and f.activeLabel or nil
        end, function()
            return f.activeTip
        end)
    end
    return f
end

-- Number field: Enter or focus loss applies, Escape puts it back.
function UI.numberBox(parent, width, get, set, centered, compact, opts)
    opts = opts or {}
    local minVal = opts.min or -10000
    local maxVal = opts.max or 10000
    local stepVal = opts.step
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width or 60, 22)
    box:SetAutoFocus(false)
    local font = compact and "GameFontHighlightSmall" or "GameFontHighlight"
    box:SetFontObject(font)
    local align, inset = centered and "CENTER" or "RIGHT", centered and (compact and 1 or 2) or 6
    box:SetJustifyH(align)
    box:SetTextInsets(inset, inset, 0, 0)
    box:SetMaxLetters(9)
    UI.panel(box, T.control)

    local display = box:CreateFontString(nil, "ARTWORK", font)
    if compact then
        UI.TextSize(box, 9)
        UI.TextSize(display, 9)
    end
    display:SetPoint("LEFT", inset, 0)
    display:SetPoint("RIGHT", -inset, 0)
    display:SetJustifyH(align)
    display:SetWordWrap(false)

    local function currentText()
        local v = get()
        if v == nil then
            return ""
        end
        return opts.format and opts.format(v) or tostring(v)
    end

    function box.SetDisabled(_, off)
        box.disabled = off and true or nil
        box:EnableMouse(not off)
        box:SetAlpha(off and 0.45 or 1)
        if off and box:HasFocus() then
            box.cancel = true
            box:ClearFocus()
        end
    end

    function box.Refresh()
        if not box:HasFocus() then
            display:SetText(currentText())
        end
    end

    box:SetScript("OnEditFocusGained", function(self)
        if self.disabled then
            self:ClearFocus()
            return
        end
        self.cancel = nil
        display:Hide()
        local cur = get()
        if opts.isPercent and type(cur) == "number" then
            self:SetText(tostring(math.floor(cur * 100 + 0.5)))
        else
            self:SetText(cur ~= nil and tostring(cur) or "")
        end
        self:HighlightText()
        UI.shade(self, T.hover)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        UI.shade(self, T.control)
        local raw = (self:GetText() or ""):gsub("%%", "")
        local v = tonumber(raw)
        if not self.cancel and not self.disabled and not UI.WritesBlocked()
            and type(v) == "number" and v == v and math.abs(v) < math.huge
        then
            if opts.isPercent and not (raw:find("%.") and v <= 1) then
                v = v / 100
            end
            if stepVal then
                v = minVal + math.floor((v - minVal) / stepVal + 0.5) * stepVal
            end
            v = math.max(minVal, math.min(maxVal, tonumber(("%.6f"):format(v))))
            set(v)
        end
        self:SetText("")
        box.Refresh()
        display:Show()
    end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", function(self)
        self.cancel = true
        self:ClearFocus()
    end)
    return box
end

-- Paired X / Y number inputs in a 40/60 row with Tab switching between fields.
-- opts: { step = 1, disabled = fn, tip = string, height = UI.ROW, compact = true, centered = true }
function UI.pairRow(parent, label, min, max, getX, setX, getY, setY, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, opts.height or UI.ROW)
    row.label = UI.text(row, label, opts.compact == false and "GameFontHighlight" or "GameFontHighlightSmall")
    row.label:SetPoint("LEFT")
    row.label:SetWordWrap(false)
    local controls = CreateFrame("Frame", nil, row)
    controls:SetPoint("RIGHT")
    controls:SetHeight(opts.height or UI.ROW)

    local centered = opts.centered ~= false
    local compact = opts.compact ~= false
    local boxOpts = { min = min, max = max, step = opts.step }
    local xBox = UI.numberBox(controls, 44, getX, setX, centered, compact, boxOpts)
    local yBox = UI.numberBox(controls, 44, getY, setY, centered, compact, boxOpts)
    xBox:SetPoint("LEFT")
    yBox:SetPoint("RIGHT")
    xBox:SetScript("OnTabPressed", function() yBox:SetFocus() end)
    yBox:SetScript("OnTabPressed", function() xBox:SetFocus() end)
    row.xBox, row.yBox = xBox, yBox

    function row.SetDisabled(_, off)
        row.disabled = off and true or nil
        row.Refresh()
    end

    function row.Refresh()
        local width = math.max(1, row:GetWidth())
        local ctrlW = width * 0.6
        local boxW = math.max(1, (ctrlW - 4) / 2)
        row.label:SetWidth(math.max(1, width * 0.4 - 4))
        controls:SetWidth(ctrlW)
        xBox:SetWidth(boxW)
        yBox:SetWidth(boxW)
        local off = row.disabled or (opts.disabled and opts.disabled())
        row.label:SetAlpha(off and 0.45 or 1)
        xBox:SetDisabled(off)
        yBox:SetDisabled(off)
        xBox.Refresh()
        yBox.Refresh()
    end

    if opts.tip then
        UI.tip(row, label, opts.tip)
    end
    return row
end

-- Labelled number with - and +. Typed values can use a finer increment.
function UI.stepper(parent, label, min, max, step, get, set, format, width, editable, inputStep, compactValue)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 300, 35)
    f.label = UI.text(f, label)
    f.label:SetPoint("LEFT")
    local control = CreateFrame("Frame", nil, f)
    control:SetSize(96, 22)
    local plus = UI.button(control, "+", 22, 22)
    plus:SetPoint("RIGHT")
    local value
    local function save(v, increment)
        if f.disabled or UI.WritesBlocked() then
            return
        end
        local rounded = min + math.floor((v - min) / increment + 0.5) * increment
        set(math.max(min, math.min(max, tonumber(("%.6f"):format(rounded)))))
    end
    if editable then
        value = UI.numberBox(control, 48, get, function(v) save(v, inputStep or step) end, true, compactValue)
        f.box = value
    else
        local well = CreateFrame("Frame", nil, control)
        UI.panel(well, T.control)
        well:SetHeight(22)
        value = UI.text(well, "", "GameFontHighlight")
        value:SetPoint("CENTER")
        value:SetJustifyH("CENTER")
        f.well = well
    end
    local minus = UI.button(control, "-", 22, 22)
    minus:SetPoint("LEFT")
    function f:SetStepButtonWidth(buttonWidth)
        minus:SetWidth(buttonWidth)
        plus:SetWidth(buttonWidth)
    end
    plus:SetPoint("RIGHT")
    local center = f.well or value
    center:ClearAllPoints()
    center:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    center:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local function nudge(by)
        if f.disabled or UI.WritesBlocked() then
            return
        end
        if editable and value:HasFocus() then
            value:ClearFocus()
        end
        local v = get()
        save(v and v + by or min, inputStep or step)
        f.Refresh()
    end
    minus:SetScript("OnClick", function()
        nudge(-step)
    end)
    plus:SetScript("OnClick", function()
        nudge(step)
    end)
    -- Do not consume the wheel: it belongs to the enclosing scroll panel.
    f:EnableMouseWheel(false)
    if editable then
        value:EnableMouseWheel(false)
    end
    function f.SetDisabled(_, off)
        f.disabled = off and true or nil
        f:SetAlpha(off and 0.45 or 1)
        minus:SetDisabled(off)
        plus:SetDisabled(off)
        if editable then
            value:SetDisabled(off)
        end
    end
    function f.Refresh()
        if editable then
            value.Refresh()
        else
            local v = get()
            value:SetText(v ~= nil and (format and format(v) or tostring(v)) or "")
        end
        columns(f, control)
    end
    return f
end

-- Labelled slider with thin track, accent thumb and value readout.
-- Optional opts: { editable = bool, isPercent = bool, check = { get, set }, disabled = fn, tip = string }
function UI.slider(parent, label, min, max, step, get, set, format, width, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 300, 35)
    local check = opts.check
    local checkBox
    if check then
        checkBox = UI.checkbox(f, label, check.get, function(v)
            check.set(v)
            f.Refresh()
        end, nil, nil, 14)
        f.label = checkBox.label
        f.check = checkBox
    else
        f.label = UI.text(f, label)
        f.label:SetPoint("LEFT")
    end

    local control = CreateFrame("Frame", nil, f)
    control:SetSize(96, 22)
    local value, valueText
    if opts.editable then
        value = UI.numberBox(control, 40, get, function(v)
            set(v)
            f.Refresh()
        end, false, false, {
            min = min, max = max, step = step,
            format = format, isPercent = opts.isPercent,
        })
        value:SetPoint("RIGHT")
        UI.panel(value, T.none)
        value:SetScript("OnEnter", function(self)
            if not self:HasFocus() and not self.disabled then
                UI.shade(self, T.control)
            end
        end)
        value:SetScript("OnLeave", function(self)
            if not self:HasFocus() then
                UI.shade(self, T.none)
            end
        end)
        f.box = value
    else
        valueText = UI.text(control, "", "GameFontHighlight")
        valueText:SetPoint("RIGHT")
        valueText:SetWidth(40)
        valueText:SetJustifyH("RIGHT")
    end

    local s = CreateFrame("Slider", nil, control)
    s:SetPoint("LEFT")
    s:SetPoint("RIGHT", value or valueText, "LEFT", -8, 0)
    s:SetHeight(18)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    setColor(track, T.control)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(4, 14)
    thumb:SetVertexColor(unpack(T.accent))
    UI.OnAccent(function() thumb:SetVertexColor(unpack(T.accent)) end)
    local filled = s:CreateTexture(nil, "ARTWORK")
    filled:SetPoint("LEFT", track)
    filled:SetPoint("RIGHT", thumb, "CENTER")
    filled:SetHeight(4)
    setColor(filled, T.accent, 0.45)

    local function show(v)
        if value then
            value.Refresh()
        else
            valueText:SetText(format and format(v) or tostring(v))
        end
    end

    s:SetScript("OnValueChanged", function(_, v)
        if f.refreshing or f.sliderDisabled or UI.WritesBlocked() then
            return
        end
        v = math.max(min, math.min(max, min + math.floor((v - min) / step + 0.5) * step))
        v = tonumber(("%.6f"):format(v))
        set(v)
        show(v)
    end)
    s:SetScript("OnEnter", function()
        setColor(track, T.hover)
    end)
    s:SetScript("OnLeave", function()
        setColor(track, T.control)
    end)
    -- Do not consume the wheel: it belongs to the enclosing scroll panel.
    f:EnableMouseWheel(false)
    s:EnableMouseWheel(false)
    if opts.editable then
        value:EnableMouseWheel(false)
    end
    f.slider = s
    if opts.tip then
        UI.tip(s, label, opts.tip)
    end

    function f.SetDisabled(_, off)
        f.disabled = off and true or nil
        f.Refresh()
    end

    function f.Refresh()
        local rowOff = f.disabled or (opts.disabled and opts.disabled()) or false
        local sliderOff = rowOff or (check and not check.get()) or false
        f.sliderDisabled = sliderOff
        f:SetAlpha(rowOff and 0.45 or 1)
        control:SetAlpha((sliderOff and not rowOff) and 0.45 or 1)
        s:EnableMouse(not sliderOff)
        if checkBox then
            checkBox:SetDisabled(rowOff)
            checkBox.Refresh()
        end
        if value then
            value:SetDisabled(sliderOff)
            value:SetAlpha(1)
        end
        local v = get()
        f.refreshing = true
        s:SetValue(v)
        f.refreshing = nil
        show(v)
        if checkBox then
            local widthNow = math.max(f:GetWidth(), 1)
            local ctrlW = f.labelWidth and math.max(1, widthNow - f.labelWidth - 4) or widthNow * 0.6
            local lblW = f.labelWidth or math.max(1, widthNow * 0.4 - 8)
            checkBox.label:SetFontObject((f.stacked or f.compact) and "GameFontHighlightSmall" or "GameFontHighlight")
            checkBox.label:SetWordWrap(not f.compact)
            checkBox:ClearAllPoints()
            checkBox:SetPoint("LEFT")
            checkBox:SetWidth(lblW)
            control:ClearAllPoints()
            control:SetPoint("RIGHT")
            control:SetWidth(ctrlW)
            local minH = f.minHeight or (f.compact and UI.ROW or 35)
            f:SetHeight(f.compact and minH or math.max(minH, checkBox.label:GetStringHeight() + 4))
        else
            columns(f, control)
        end
    end
    return f
end

-- Text field with placeholder and optional clear button; onEnter(text, box).
-- opts: { maxLetters = 120, height = 28, onTextChanged = fn(text, box), clearable = bool }
function UI.textBox(parent, width, placeholder, onEnter, opts)
    opts = opts or {}
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width or 200, opts.height or 28)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    local rightInset = opts.clearable and 20 or 8
    box:SetTextInsets(8, rightInset, 0, 0)
    box:SetMaxLetters(opts.maxLetters or 120)
    UI.panel(box, T.control)
    local ph = UI.text(box, placeholder or "", "GameFontHighlight", T.faint)
    ph:SetPoint("LEFT", 8, 0)
    ph:SetPoint("RIGHT", -rightInset, 0)
    ph:SetWordWrap(false)

    local clear
    if opts.clearable then
        clear = UI.button(box, "×", 16, 16, true)
        clear:SetPoint("RIGHT", -4, 0)
        clear.label:SetFontObject("GameFontHighlightSmall")
        clear:SetTextColor(T.muted)
        clear:Hide()
        clear:SetScript("OnClick", function()
            if box.disabled or UI.WritesBlocked() then
                return
            end
            box:SetText("")
            box:ClearFocus()
            if onEnter then
                onEnter("", box)
            end
        end)
        box.clearButton = clear
    end

    function box:SetPlaceholder(text)
        ph:SetText(text)
    end
    function box:SetDisabled(off)
        box.disabled = off and true or nil
        box:EnableMouse(not off)
        box:SetAlpha(off and 0.45 or 1)
        if off and box:HasFocus() then
            box:ClearFocus()
        end
        if clear then
            clear:SetDisabled(off)
        end
    end
    function box.Refresh() end

    local function onChanged(self, userInput)
        local text = box:GetText()
        ph:SetShown(text == "" and not box:HasFocus())
        if clear then
            clear:SetShown(text ~= "")
        end
        if userInput and opts.onTextChanged then
            opts.onTextChanged(text, self)
        end
    end
    box:SetScript("OnEditFocusGained", function()
        ph:SetShown(false)
    end)
    box:SetScript("OnEditFocusLost", function()
        ph:SetShown(box:GetText() == "")
    end)
    box:SetScript("OnTextChanged", onChanged)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", function(self)
        if not self.disabled and not UI.WritesBlocked() and onEnter then
            onEnter(self:GetText(), self)
        end
    end)
    return box
end

-- Compact live-filtering search field with clear button.
function UI.searchBox(parent, width, placeholder, onChange)
    local box = UI.textBox(parent, width, placeholder or "Search...", function(text, b)
        if onChange then
            onChange(text, b)
        end
    end, { height = 22, clearable = true, onTextChanged = onChange })
    box:SetFontObject("GameFontHighlightSmall")
    return box
end

--------------------------------------------------------------------------------
-- Color pickers & swatches
--------------------------------------------------------------------------------

local pickerHooked, pickerFinish
function UI.colorSwatch(parent, get, set, size, onOpen, withAlpha)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 28, 18)
    UI.panel(b, T.control)
    local chip = b:CreateTexture(nil, "ARTWORK")
    chip:SetPoint("TOPLEFT", 3, -3)
    chip:SetPoint("BOTTOMRIGHT", -3, 3)
    function b.Refresh()
        local c = get()
        chip:SetColorTexture(c[1], c[2], c[3], withAlpha and (c[4] or 1) or 1)
        b:SetAlpha(b.disabled and 0.45 or 1)
    end
    function b.SetDisabled(_, off)
        b.disabled = off and true or nil
        b:EnableMouse(not off)
        b.Refresh()
    end
    b:SetScript("OnClick", function()
        if b.disabled or UI.WritesBlocked() then
            return
        end
        if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
        end
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
            DEFAULT_CHAT_FRAME:AddMessage("The colour picker could not be loaded.")
            return
        end
        if ColorPickerFrame:IsShown() and ColorPickerFrame.OnCancel then
            ColorPickerFrame:OnCancel()
        end
        if not pickerHooked then
            ColorPickerFrame:HookScript("OnHide", function()
                local finish = pickerFinish
                pickerFinish = nil
                if finish then
                    finish()
                end
            end)
            pickerHooked = true
        end
        local c = get()
        local applySet, cancelPick = set, nil
        if onOpen then
            applySet, cancelPick, pickerFinish = onOpen()
        end
        local ready = not withAlpha
        local function apply()
            if not ready then return end
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            if withAlpha then
                applySet(r, g, bl, ColorPickerFrame:GetColorAlpha())
            else
                applySet(r, g, bl)
            end
            b.Refresh()
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3],
            hasOpacity = withAlpha == true,
            opacity = withAlpha and (c[4] or 1) or nil,
            opacityFunc = withAlpha and apply or nil,
            swatchFunc = apply,
            cancelFunc = function(previous)
                if cancelPick then
                    cancelPick()
                    b.Refresh()
                elseif previous then
                    if withAlpha then
                        applySet(previous.r, previous.g, previous.b, previous.a)
                    else
                        applySet(previous.r, previous.g, previous.b)
                    end
                    b.Refresh()
                end
            end,
        })
        ready = true
    end)
    return b
end

-- Standardised 40/60 compact color row: swatch + #rrggbb NN% readout + optional reset.
function UI.colorRow(parent, label, get, set, opts)
    opts = opts or {}
    local withAlpha = opts.withAlpha ~= false
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(opts.height or UI.ROW)
    row.label = UI.text(row, label, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT")
    row.label:SetWordWrap(false)
    local controls = CreateFrame("Frame", nil, row)
    controls:SetPoint("RIGHT")
    controls:SetHeight(opts.height or UI.ROW)
    local swatch = UI.colorSwatch(controls, get, set, 22, opts.onOpen, withAlpha)
    swatch:SetPoint("LEFT")
    local hex = UI.text(controls, "", "GameFontHighlightSmall", T.muted)
    hex:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
    local arrow
    if opts.onReset then
        arrow = UI.resetButton(controls, 16, 20, opts.onReset)
        arrow:SetPoint("RIGHT")
        if opts.resetTip then
            UI.tip(arrow, opts.resetTip)
        end
    end
    row.swatch, row.hex, row.reset = swatch, hex, arrow
    function row.SetDisabled(_, off)
        row.disabled = off and true or nil
        row.Refresh()
    end
    function row.Refresh()
        local disabled = row.disabled or (opts.disabled and opts.disabled())
        row.label:SetWidth(math.max(1, row:GetWidth() * 0.4 - 4))
        row.label:SetAlpha(disabled and 0.45 or 1)
        controls:SetWidth(row:GetWidth() * 0.6)
        local c = get()
        local value = ("#%02x%02x%02x"):format(
            math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
        hex:SetText(withAlpha and ("%s %d%%"):format(value, math.floor((c[4] or 1) * 100 + 0.5)) or value)
        hex:SetAlpha(disabled and 0.45 or 1)
        swatch:SetDisabled(disabled)
        if arrow then
            if disabled then
                arrow:SetChanged(false)
            elseif opts.isChanged then
                arrow:SetChanged(opts.isChanged())
            end
        end
    end
    UI.tip(swatch, label, opts.tip or "Click to set color and opacity.")
    return row
end

--------------------------------------------------------------------------------
-- Tabs, selector strips & option cards
--------------------------------------------------------------------------------

function UI.tabs(parent, items, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 22)
    UI.fill(f, T.band)
    f.buttons = {}
    function f.Refresh()
        local list = type(items) == "function" and items() or items
        local natural = 0
        for i, it in ipairs(list) do
            local b = f.buttons[i]
            if not b then
                b = UI.button(f, "", 60, 22, true)
                b:SetScript("OnClick", function(self)
                    set(self.key)
                end)
                f.buttons[i] = b
            end
            b.key = it.key
            b.label:SetFontObject(f.compact and "GameFontHighlightSmall" or "GameFontHighlight")
            b:SetLabel(it.label)
            natural = natural + math.ceil(b.label:GetStringWidth()) + 18
        end
        local available = math.max(f:GetWidth(), 1)
        local compact = f.compact or natural > available
        local widths, total = {}, math.max(0, #list - 1) * 2
        for i = 1, #list do
            local b = f.buttons[i]
            if compact then b.label:SetFontObject("GameFontHighlightSmall") end
            widths[i] = math.ceil(b.label:GetStringWidth()) + (compact and 8 or 16)
            total = total + widths[i]
        end
        local gap = math.max(0, #list - 1) * 2
        local scale = math.min(1, math.max(1, available - gap) / math.max(1, total - gap))
        local x = 0
        for i = 1, #list do
            local b = f.buttons[i]
            local width = math.max(1, widths[i] * scale)
            b:SetWidth(width)
            b:SetHeight(f:GetHeight())
            b.label:SetWidth(math.max(1, width - 4))
            b.label:SetWordWrap(false)
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            b:SetActive(get() == b.key)
            b:Show()
            x = x + b:GetWidth() + 2
        end
        for i = #list + 1, #f.buttons do
            f.buttons[i]:Hide()
        end
    end
    return f
end

-- Equal-width horizontal selector bar.
function UI.selectorStrip(parent, items, get, set, height)
    height = height or 20
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(height)
    local buttons = {}
    local function paint(button)
        local active = get() == button.key
        UI.shade(button, button.hover and T.hover or active and T.accentSoft or T.surface)
        button.label:SetTextColor(unpack(active and T.accent or T.muted))
    end
    for _, item in ipairs(items) do
        local button = CreateFrame("Button", nil, strip)
        button.key = item.key
        UI.panel(button, T.surface)
        button.label = UI.text(button, item.label, "GameFontHighlightSmall", T.muted)
        UI.TextSize(button.label, 11)
        button.label:SetPoint("CENTER")
        button.label:SetJustifyH("CENTER")
        button.label:SetWordWrap(false)
        button:SetScript("OnEnter", function()
            button.hover = true
            paint(button)
        end)
        button:SetScript("OnLeave", function()
            button.hover = nil
            paint(button)
        end)
        button:SetScript("OnHide", function()
            if button.hover then
                button.hover = nil
                paint(button)
            end
        end)
        button:SetScript("OnClick", function()
            set(item.key)
        end)
        buttons[#buttons + 1] = button
    end
    strip.buttons = buttons
    UI.OnAccent(function()
        for _, button in ipairs(buttons) do
            paint(button)
        end
    end)
    function strip.Refresh()
        local count = #buttons
        local width = math.max(1, (strip:GetWidth() - (count - 1) * 3) / math.max(1, count))
        for i, button in ipairs(buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", (i - 1) * (width + 3), 0)
            button:SetSize(width, height)
            button.label:SetWidth(math.max(1, width - 8))
            paint(button)
        end
    end
    return strip
end

function UI.sectionToggle(form, title, get, set, opts)
    opts = opts or {}
    local h = form:Section(title, opts.shown)
    h.label:SetFontObject("GameFontHighlightSmall")
    h.label:SetWordWrap(false)
    local entry = form.rows[#form.rows]
    entry.gap, entry.top = 3, 7
    local toggle = UI.checkbox(h, opts.toggleLabel or "Show", get, set)
    toggle.label:SetFontObject("GameFontHighlightSmall")
    toggle:SetPoint("RIGHT")
    h.toggle = toggle
    if opts.tip then
        UI.tip(toggle, title, opts.tip)
    end
    function h.Refresh()
        local width = math.max(1, h:GetWidth())
        local controls = math.min(width * 0.6, toggle.label:GetStringWidth() + 28)
        h.label:SetWidth(math.max(1, width - controls - 4))
        toggle:SetWidth(controls)
        if opts.disabled then
            toggle:SetDisabled(opts.disabled())
        end
        toggle.Refresh()
    end
    return h
end

function UI.barOptions(parent, selectors, items, get, set)
    local card = UI.panel(CreateFrame("Frame", nil, parent), T.surface)
    card:SetPoint("TOPLEFT", selectors, "BOTTOMLEFT", 0, -8)
    card:SetPoint("TOPRIGHT", selectors, "BOTTOMRIGHT", 0, -8)
    card:SetPoint("BOTTOM", parent, "BOTTOM", 0, 12)
    local line = CreateFrame("Frame", nil, card)
    line:SetPoint("TOPLEFT", 8, -4)
    line:SetPoint("TOPRIGHT", -8, -4)
    line:SetHeight(22)
    local title = UI.text(line, "Options", "GameFontHighlightSmall", T.muted)
    title:SetPoint("LEFT")
    local rule = line:CreateTexture(nil, "BACKGROUND")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    setColor(rule, T.control)
    local tabs = {}
    function line.Refresh()
        local x = title:GetStringWidth() + 9
        local choices = type(items) == "function" and items() or items
        for i, choice in ipairs(choices) do
            local b = tabs[i]
            if not b then
                b = CreateFrame("Button", nil, line)
                b.label = UI.text(b, "", "GameFontHighlightSmall", T.muted)
                b.label:SetPoint("CENTER", 0, 1)
                UI.fill(b, T.hover, 0.06, "HIGHLIGHT")
                b.underline = b:CreateTexture(nil, "ARTWORK")
                b.underline:SetPoint("BOTTOMLEFT")
                b.underline:SetPoint("BOTTOMRIGHT")
                b.underline:SetHeight(2)
                setColor(b.underline, T.accent)
                b:SetScript("OnClick", function(self) set(self.key) end)
                tabs[i] = b
            end
            b.key = choice.key
            b.label:SetText(choice.label)
            local active = get() == b.key
            b.label:SetTextColor(unpack(active and T.accent or T.muted))
            b.underline:SetShown(active)
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            local width = b.label:GetStringWidth() + 14
            b:SetSize(width, 22)
            b:Show()
            x = x + width + 2
        end
        for i = #choices + 1, #tabs do tabs[i]:Hide() end
    end
    return card, line
end
UI.optionsCard = UI.barOptions

--------------------------------------------------------------------------------
-- Scroll area and form
--------------------------------------------------------------------------------

function UI.scroll(parent, indicator)
    local sa = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sa)
    child:SetSize(1, 1)
    sa:SetScrollChild(child)
    sa.child = child
    sa:EnableMouseWheel(true)
    local bar, thumb, syncing
    if indicator then
        bar = CreateFrame("Slider", nil, parent)
        bar:SetOrientation("VERTICAL")
        bar:SetWidth(4)
        bar:SetPoint("TOPRIGHT", sa, "TOPRIGHT")
        bar:SetPoint("BOTTOMRIGHT", sa, "BOTTOMRIGHT")
        bar:SetFrameLevel(sa:GetFrameLevel() + 10)
        bar:SetMinMaxValues(0, 1)
        bar:SetValueStep(1)
        bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        thumb = bar:GetThumbTexture()
        thumb:SetWidth(3)
        thumb:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.35)
        UI.fill(bar, T.text, 0.035)
        bar:SetScript("OnValueChanged", function(_, value)
            if not syncing then
                sa:SetVerticalScroll(value)
            end
        end)
        bar:SetScript("OnEnter", function()
            thumb:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.65)
        end)
        bar:SetScript("OnLeave", function()
            thumb:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.35)
        end)
        bar:Hide()
    end
    local function updateIndicator()
        if not bar then
            return
        end
        local height = math.max(sa:GetHeight(), 1)
        local content = math.max(child:GetHeight(), height)
        local range = math.max(content - height, 0)
        syncing = true
        bar:SetMinMaxValues(0, math.max(range, 1))
        bar:SetValue(sa:GetVerticalScroll())
        thumb:SetHeight(math.min(height, math.max(18, height * height / content)))
        bar:SetShown(range > 1)
        syncing = false
    end
    local function clamp()
        local range = math.max(child:GetHeight() - sa:GetHeight(), 0)
        sa:SetVerticalScroll(math.max(0, math.min(range, sa:GetVerticalScroll())))
        updateIndicator()
    end
    sa:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(self:GetVerticalScroll() - delta * 40)
        clamp()
    end)
    sa:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(math.max(1, w - (indicator and 8 or 0)))
        clamp()
    end)
    sa:SetScript("OnVerticalScroll", updateIndicator)
    function sa.SetContentHeight(_, h)
        child:SetHeight(math.max(h, 1))
        clamp()
    end
    function sa.ToTop()
        sa:SetVerticalScroll(0)
    end
    return sa
end

function UI.Form(parent)
    local form = { rows = {} }
    function form.Add(_, widget, shown, gap)
        form.rows[#form.rows + 1] = { w = widget, shown = shown, gap = gap or 0 }
        return widget
    end
    function form.Section(_, title, shown, opts)
        local h = UI.heading(parent, title, opts)
        form.rows[#form.rows + 1] = { w = h, shown = shown, gap = 8, top = 6 }
        return h
    end
    function form.SectionToggle(_, title, get, set, label, desc)
        local h = form:Section(title)
        h:SetHeight(24)
        local toggle = UI.checkbox(h, label or "Show", get, set, nil, desc)
        h.toggle = toggle
        function h.Refresh()
            local width = math.max(h:GetWidth(), 1)
            h.label:SetWidth(math.max(1, width * 0.4 - 8))
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", h, "LEFT", width * 0.4, 0)
            toggle:SetWidth(width * 0.6)
            toggle.Refresh()
        end
        return h
    end
    function form.Divider(_, shown, gap)
        local div = CreateFrame("Frame", nil, parent)
        div:SetHeight(1)
        UI.fill(div, T.control)
        form.rows[#form.rows + 1] = { w = div, shown = shown, gap = gap or 6, top = 6 }
        return div
    end
    function form.Help(_, s, shown)
        local help = form:Add(UI.help(parent, s), shown, 8)
        form.rows[#form.rows].top = 6
        return help
    end
    function form.Refresh(_, width)
        local y, first = 0, true
        for _, r in ipairs(form.rows) do
            local show = not r.shown or r.shown()
            r.w:SetShown(show and true or false)
            if show then
                if width and not r.fixedWidth then
                    r.w:SetWidth(width)
                end
                if r.w.Refresh then
                    r.w.Refresh()
                end
                if not first then
                    y = y - (r.top or 0)
                end
                first = false
                r.w:ClearAllPoints()
                r.w:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
                y = y - r.w:GetHeight() - r.gap
            end
        end
        return -y
    end
    return form
end

function UI.barOptionsPanel(card, line, requestRefresh)
    local holder = CreateFrame("Frame", nil, card)
    holder:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -4)
    holder:SetPoint("BOTTOMRIGHT", -6, 5)
    local scroll = UI.scroll(holder, true)
    scroll:SetAllPoints()
    local blocks = {}
    local panel = { frame = holder, scroll = scroll }
    local function column()
        local frame = CreateFrame("Frame", nil, scroll.child)
        return { frame = frame, form = UI.Form(frame) }
    end
    function panel:AddPair()
        local a, b = column(), column()
        blocks[#blocks + 1] = { a, b }
        return a.frame, a.form, b.frame, b.form
    end
    function panel:AddFull()
        local a = column()
        blocks[#blocks + 1] = { a }
        return a.frame, a.form
    end
    function panel:Refresh(shown)
        holder:SetShown(shown)
        if not shown then return end
        local width = math.max(1, holder:GetWidth() - 8)
        scroll.child:SetWidth(width)
        local y = 0
        for _, block in ipairs(blocks) do
            local gap = y > 0 and 6 or 0
            local columnWidth = #block == 2 and math.max(1, (width - 14) / 2) or width
            local height = 0
            for i, c in ipairs(block) do
                local point = i == 1 and "TOPLEFT" or "TOPRIGHT"
                c.frame:ClearAllPoints()
                c.frame:SetPoint(point, scroll.child, point, 0, -y - gap)
                c.frame:SetWidth(columnWidth)
                local h = c.form:Refresh(columnWidth)
                c.frame:SetHeight(math.max(1, h))
                height = math.max(height, h)
            end
            if height > 0 then y = y + gap + height end
        end
        scroll:SetContentHeight(y)
    end
    local lastWidth
    holder:HookScript("OnSizeChanged", function(_, width)
        if width ~= lastWidth then lastWidth = width; requestRefresh() end
    end)
    return panel
end
UI.twoColumnPanel = UI.barOptionsPanel
