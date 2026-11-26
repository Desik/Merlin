-- UI/Kit/Dialogs.lua
-- Modal confirmation dialog (with optional icon pair or Forever-safe /reload
-- hardware action button) and scrollable multiline Import/Export dialog.

local _, ns = ...
local UI = ns.UI
local T = UI.T

--------------------------------------------------------------------------------
-- Confirmation modal
--------------------------------------------------------------------------------

local confirmBox

-- Modal question over `parent`: a title, short explanation, and an accept button
-- that runs onAccept; Cancel or clicking outside closes it.
-- optsOrIcons: `{ leftTex, rightTex }` OR `{ icons = { left, right }, cancel = "Cancel", reload = bool, danger = bool }`
function UI.confirm(parent, title, text, accept, onAccept, optsOrIcons)
    local opts = {}
    if type(optsOrIcons) == "table" then
        if optsOrIcons[1] and optsOrIcons[2] then
            opts.icons = optsOrIcons
        else
            opts = optsOrIcons
        end
    end
    if not confirmBox then
        local f = CreateFrame("Button", nil, parent)
        f:RegisterForClicks("AnyUp")
        f:SetScript("OnClick", function(self)
            self:Hide()
        end)
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function() end)
        UI.fill(f, { 0, 0, 0 }, 0.6)

        local box = CreateFrame("Frame", nil, f)
        box:SetWidth(320)
        box:SetPoint("CENTER")
        box:EnableMouse(true)
        UI.panel(box, T.popup)
        UI.shadow(box, 8, 0.8)

        box.title = UI.text(box, "", "GameFontHighlightLarge")
        box.title:SetPoint("TOPLEFT", 16, -14)
        box.title:SetPoint("TOPRIGHT", -16, -14)

        local pair = CreateFrame("Frame", nil, box)
        pair:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -10)
        pair:SetPoint("TOPRIGHT", box.title, "BOTTOMRIGHT", 0, -10)
        pair:SetHeight(48)
        UI.fill(pair, T.band)
        local function makePreviewIcon(point, rel, relPoint, ox)
            local holder = CreateFrame("Frame", nil, pair)
            holder:SetSize(34, 34)
            holder:SetPoint(point, rel, relPoint, ox, 0)
            local tex = holder:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 1, -1)
            tex:SetPoint("BOTTOMRIGHT", -1, 1)
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local edge = UI.Edge(holder, "OVERLAY")
            UI.SetEdge(edge, { 1, 1, 1, 0.22 })
            return tex
        end
        pair.plus = UI.text(pair, "+", "GameFontHighlightLarge", T.accent)
        pair.plus:SetPoint("CENTER")
        pair.leftIcon = makePreviewIcon("RIGHT", pair.plus, "LEFT", -12)
        pair.rightIcon = makePreviewIcon("LEFT", pair.plus, "RIGHT", 12)
        pair:Hide()
        box.pair = pair

        box.text = UI.text(box, "", "GameFontHighlight", T.muted)
        box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -8)
        box.text:SetWidth(288)
        box.text:SetSpacing(2)

        box.ok = UI.button(box, "", 130, 24)
        box.ok:SetPoint("BOTTOMRIGHT", -16, 14)

        box.reloadOk = UI.reloadButton(box, "", 130, 24, function()
            if InCombatLockdown() or UI.IsRestricted() then
                return false
            end
            if f.onBeforeReload then
                if f.onBeforeReload() == false then
                    return false
                end
            end
            f:Hide()
        end)
        box.reloadOk:SetPoint("BOTTOMRIGHT", -16, 14)
        box.reloadOk:Hide()

        local cancel = UI.button(box, "Cancel", 90, 24)
        cancel:SetPoint("RIGHT", box.ok, "LEFT", -6, 0)
        cancel:SetScript("OnClick", function()
            f:Hide()
        end)
        box.cancel = cancel

        f.box = box
        confirmBox = f
    end

    local f, box = confirmBox, confirmBox.box
    f:SetParent(parent)
    f:ClearAllPoints()
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 100)
    box.title:SetText(title)

    local pairH = 0
    box.text:ClearAllPoints()
    if opts.icons and opts.icons[1] and opts.icons[2] then
        box.pair.leftIcon:SetTexture(opts.icons[1])
        box.pair.rightIcon:SetTexture(opts.icons[2])
        box.pair:Show()
        box.text:SetPoint("TOPLEFT", box.pair, "BOTTOMLEFT", 0, -10)
        pairH = 10 + 48 + 2
    else
        box.pair:Hide()
        box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -8)
    end

    box.text:SetWidth(288)
    box.text:SetText(text)
    box.cancel:SetLabel(opts.cancel or "Cancel")

    local acceptColor = opts.danger and T.danger or T.accent
    if opts.reload then
        f.onBeforeReload = onAccept
        box.ok:Hide()
        box.reloadOk:SetLabel(accept or "Confirm")
        box.reloadOk:SetTextColor(acceptColor)
        box.reloadOk:Show()
    else
        f.onBeforeReload = nil
        box.reloadOk:Hide()
        box.ok:SetLabel(accept or "Confirm")
        box.ok:SetTextColor(acceptColor)
        box.ok:SetScript("OnClick", function()
            f:Hide()
            if onAccept then
                onAccept()
            end
        end)
        box.ok:Show()
    end

    box:SetHeight(14 + box.title:GetStringHeight() + 8 + pairH + box.text:GetStringHeight() + 26 + 24 + 14)
    f:Show()
end

function UI.CloseConfirm()
    if confirmBox then
        confirmBox:Hide()
    end
end

--------------------------------------------------------------------------------
-- Import / Export scrollable multiline dialog
--------------------------------------------------------------------------------

local ioBox

-- Opens a scrollable multiline Import / Export dialog over `parent`.
-- opts: {
--   mode        = "export" | "import",
--   title       = string,
--   hint        = string,
--   text        = string,
--   actionLabel = string (default "Import"),
--   closeLabel  = string (default "Close"),
--   width       = number (default 350),
--   height      = number (default 220),
--   onSubmit    = fn(text) -> ok, errMsg,
-- }
function UI.ioDialog(parent, opts)
    opts = opts or {}
    if not ioBox then
        local f = CreateFrame("Button", nil, parent)
        f:RegisterForClicks("AnyUp")
        f:SetScript("OnClick", function(self) self:Hide() end)
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function() end)
        UI.fill(f, { 0, 0, 0 }, 0.6)

        local box = CreateFrame("Frame", nil, f)
        box:SetPoint("CENTER")
        box:EnableMouse(true)
        UI.panel(box, T.popup)
        UI.shadow(box, 8, 0.8)

        box.title = UI.text(box, "", "GameFontHighlight")
        box.title:SetPoint("TOPLEFT", 14, -12)
        box.title:SetPoint("TOPRIGHT", -14, -12)

        box.hint = UI.text(box, "", "GameFontHighlightSmall", T.muted)
        box.hint:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
        box.hint:SetPoint("TOPRIGHT", box.title, "BOTTOMRIGHT", 0, -4)

        local well = CreateFrame("Frame", nil, box)
        well:SetPoint("TOPLEFT", 14, -48)
        well:SetPoint("BOTTOMRIGHT", -14, 42)
        UI.panel(well, T.control)

        local scroll = CreateFrame("ScrollFrame", nil, well)
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -6, 6)
        scroll:EnableMouseWheel(true)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetWidth(300)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(0)
        edit:SetAutoFocus(false)
        edit:SetFontObject("GameFontHighlightSmall")
        edit:SetTextInsets(2, 2, 2, 2)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        edit:SetScript("OnTextChanged", function(self)
            local w = scroll:GetWidth()
            if w and w > 0 then
                self:SetWidth(w)
            end
        end)
        edit:SetScript("OnCursorChanged", function(_, _, cy, _, ch)
            if not cy or not ch then
                return
            end
            local viewH = scroll:GetHeight()
            local cur = scroll:GetVerticalScroll()
            local top = -cy
            local bottom = top + ch
            if top < cur then
                scroll:SetVerticalScroll(top)
            elseif bottom > cur + viewH then
                scroll:SetVerticalScroll(math.max(0, bottom - viewH))
            end
        end)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnSizeChanged", function(_, w)
            if w and w > 0 then
                edit:SetWidth(w)
            end
        end)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local maxScroll = math.max(0, (edit:GetHeight() or 0) - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 24)))
        end)
        well:EnableMouse(true)
        well:SetScript("OnMouseDown", function() edit:SetFocus() end)

        box.err = UI.text(box, "", "GameFontHighlightSmall", T.danger)
        box.err:SetPoint("BOTTOMLEFT", 14, 15)
        box.err:SetPoint("RIGHT", box, "BOTTOMRIGHT", -180, 15)
        box.err:SetWordWrap(false)

        box.action = UI.button(box, "Import", 84, 24)
        box.action:SetPoint("BOTTOMRIGHT", -14, 10)
        box.action:SetTextColor(T.accent)

        box.close = UI.button(box, "Close", 68, 24)
        box.close:SetScript("OnClick", function() f:Hide() end)

        box.scroll = scroll
        box.edit = edit
        f.box = box
        ioBox = f
    end

    local f, box = ioBox, ioBox.box
    f:SetParent(parent)
    f:ClearAllPoints()
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 100)
    box:SetSize(opts.width or 350, opts.height or 220)
    box.title:SetText(opts.title or (opts.mode == "export" and "Export" or "Import"))
    box.hint:SetText(opts.hint or "")
    box.err:SetText("")
    box.edit:SetText(opts.text or "")
    box.scroll:SetVerticalScroll(0)
    box.close:SetLabel(opts.closeLabel or "Close")

    if opts.mode == "export" then
        box.action:Hide()
        box.close:ClearAllPoints()
        box.close:SetPoint("BOTTOMRIGHT", -14, 10)
        f:Show()
        box.edit:SetFocus()
        box.edit:HighlightText()
    else
        box.action:SetLabel(opts.actionLabel or "Import")
        box.action:SetScript("OnClick", function()
            if UI.WritesBlocked() then
                box.err:SetText("Unavailable in combat.")
                return
            end
            if opts.onSubmit then
                local ok, msg = opts.onSubmit(box.edit:GetText())
                if ok then
                    f:Hide()
                else
                    box.err:SetText(msg or "Import failed.")
                end
            else
                f:Hide()
            end
        end)
        box.action:Show()
        box.close:ClearAllPoints()
        box.close:SetPoint("RIGHT", box.action, "LEFT", -6, 0)
        f:Show()
        box.edit:SetFocus()
    end
end

function UI.CloseIO()
    if ioBox then
        ioBox:Hide()
    end
end
