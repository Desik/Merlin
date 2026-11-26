-- UI/Kit/Shell.lua
-- Reusable flat borderless settings window shell: floating halo wordmark,
-- close button, optional collapsible sidebar, resizable or fixed geometry,
-- opacity control, floating status toast, and combat/restriction dismissal.

local _, ns = ...
local UI = ns.UI
local T = UI.T

local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function buildWordmark(window, cfg)
    local wm = type(cfg) == "table" and cfg or { style = "slash", text = cfg or "" }
    local label = wm.text or ""
    if label == "" and not wm.format then
        return
    end
    local style = wm.style or "slash"
    local isDiamonds = style == "diamonds"

    local function formatted()
        if wm.format then
            return wm.format(UI.hex(UI.HeaderColour()))
        end
        if style == "slash" then
            return "|cffffffff\\|r" .. UI.hex(UI.HeaderColour()) .. label .. "|r"
        end
        if style == "diamonds" then
            return "|cffffffff" .. label .. "|r"
        end
        return UI.hex(UI.HeaderColour()) .. label .. "|r"
    end

    local haloText = style == "slash" and ("\\" .. label) or label
    local rings = isDiamonds and 2 or 3
    local angles = isDiamonds and 8 or 12
    local baseAlpha = isDiamonds and 0.16 or 0.14
    local haloX = isDiamonds and -1 or -1.5

    for ring = 1, rings do
        for i = 0, angles - 1 do
            local angle = i * (2 * math.pi / angles)
            local halo = window:CreateFontString(nil, "BACKGROUND")
            halo:SetFont(DEFAULT_FONT, 30, "")
            halo:SetJustifyH("CENTER")
            halo:SetPoint("CENTER", window, "TOP",
                haloX + math.cos(angle) * ring * 2, 2 + math.sin(angle) * ring * 2)
            halo:SetTextColor(0, 0, 0, baseAlpha / ring)
            halo:SetText(haloText)
        end
    end

    local texts = {}
    for _, offset in ipairs({ { -0.45, 0 }, { 0.45, 0 }, { 0, -0.45 }, { 0, 0.45 } }) do
        local weight = UI.text(window, "")
        weight:SetFont(DEFAULT_FONT, 30, "OUTLINE")
        weight:SetJustifyH("CENTER")
        weight:SetPoint("CENTER", window, "TOP", offset[1], 2 + offset[2])
        weight:SetText(formatted())
        texts[#texts + 1] = weight
    end
    local title = UI.text(window, "")
    title:SetFont(DEFAULT_FONT, 30, "OUTLINE")
    title:SetJustifyH("CENTER")
    title:SetPoint("CENTER", window, "TOP", 0, 2)
    title:SetShadowColor(0, 0, 0, 0)
    title:SetShadowOffset(0, 0)
    title:SetText(formatted())
    texts[#texts + 1] = title

    if isDiamonds then
        local diag = math.rad(45)
        local diamonds = {}
        local function paintDiamonds()
            local c = UI.HeaderColour()
            for _, d in ipairs(diamonds) do
                d:SetVertexColor(c[1], c[2], c[3], 1)
            end
        end
        for _, side in ipairs({
            { point = "RIGHT", relPoint = "LEFT", ox = -10 },
            { point = "LEFT", relPoint = "RIGHT", ox = 10 },
        }) do
            local outline = window:CreateTexture(nil, "OVERLAY", nil, 0)
            outline:SetSize(10, 10)
            outline:SetTexture("Interface\\Buttons\\WHITE8X8")
            outline:SetVertexColor(0, 0, 0, 0.9)
            outline:SetRotation(diag)
            outline:SetPoint(side.point, title, side.relPoint, side.ox, -1)

            local diamond = window:CreateTexture(nil, "OVERLAY", nil, 1)
            diamond:SetSize(7, 7)
            diamond:SetTexture("Interface\\Buttons\\WHITE8X8")
            diamond:SetRotation(diag)
            diamond:SetPoint("CENTER", outline, "CENTER")
            diamonds[#diamonds + 1] = diamond
        end
        paintDiamonds()
        UI.OnHeaderColour(paintDiamonds)
    end

    UI.OnHeaderColour(function()
        local s = formatted()
        for _, fs in ipairs(texts) do
            fs:SetText(s)
        end
    end)
end

-- Creates a reusable settings window controller (lazy frame construction).
function UI.CreateShell(cfg)
    cfg = cfg or {}
    local shell = {
        config = cfg,
        pages = {},
        builders = {},
        navButtons = {},
        navLabels = {},
        activePage = cfg.defaultPage,
    }

    local minW = cfg.minWidth or cfg.width or 544
    local minH = cfg.minHeight or cfg.height or 550
    local maxWCap = cfg.maxWidth or minW
    local maxHCap = cfg.maxHeight or minH

    local window, nav, main, status
    local refreshQueued = false
    local statusToken = 0

    local function resizeLimits()
        local pw = UIParent and UIParent:GetWidth() or maxWCap
        local ph = UIParent and UIParent:GetHeight() or maxHCap
        return math.max(minW, math.min(maxWCap, pw - 24)),
            math.max(minH, math.min(maxHCap, ph - 48))
    end

    local function pinTopLeft()
        if not window then
            return
        end
        local left, top = window:GetLeft(), window:GetTop()
        if left and top then
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
                left - UIParent:GetLeft(), top - UIParent:GetTop())
        end
    end

    local function saveGeometry()
        if not (window and cfg.saveGeometry) then
            return
        end
        local size = { width = window:GetWidth(), height = window:GetHeight() }
        local pos
        local left, top = window:GetLeft(), window:GetTop()
        if left and top then
            pos = { x = left - UIParent:GetLeft(), y = top - UIParent:GetTop() }
        end
        cfg.saveGeometry(size, pos)
    end

    local function stopManipulation()
        if not window then
            return
        end
        window:StopMovingOrSizing()
        pinTopLeft()
        if cfg.resizable then
            saveGeometry()
        end
    end

    function shell:ApplyOpacity(alpha)
        if window and window.bg then
            local a = alpha or (cfg.getOpacity and cfg.getOpacity()) or 0.95
            UI.SetColor(window.bg, T.window, a)
        end
    end

    function shell:RequestRefresh()
        if not window or refreshQueued then
            return
        end
        refreshQueued = true
        window:SetScript("OnUpdate", function(frame)
            frame:SetScript("OnUpdate", nil)
            refreshQueued = false
            shell:Refresh()
        end)
    end

    function shell:RegisterPage(name, builder)
        self.builders[name] = builder
    end

    function shell:GetPage(name)
        if not self.pages[name] and self.builders[name] and main then
            local p = self.builders[name](main)
            p.frame:SetAllPoints(main)
            self.pages[name] = p
        end
        return self.pages[name]
    end

    function shell:Status(text, duration)
        if not status then
            return
        end
        statusToken = statusToken + 1
        local token = statusToken
        status.text:SetText(text or "")
        local room = math.max(40, ((main and main:GetWidth()) or (window and window:GetWidth()) or 300) - 24)
        status.text:SetWidth(0)
        status:SetWidth(math.min(room, math.ceil(status.text:GetStringWidth()) + 16))
        status.text:SetWidth(status:GetWidth() - 16)
        status:SetShown(text ~= nil and text ~= "")
        C_Timer.After(duration or cfg.toastDuration or 4, function()
            if token == statusToken and status then
                status:Hide()
            end
        end)
    end

    -- Helper for building standard sidebar nav items inside cfg.sidebar.build(nav, shell).
    function shell:CreateNavButton(parent, opts)
        local sb = cfg.sidebar or {}
        local navW = sb.width or 124
        local h = opts.height or 35
        local b = UI.button(parent, opts.label or "", navW - 8, h, true)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 10, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        b.fullLabel = opts.label or ""
        b.initial = opts.glyph or ""
        b.glyphKey = opts.glyph or ""
        b.glyph = UI.Glyph(b, b.glyphKey, 16)
        b.glyph:SetPoint("LEFT", 8, 0)
        local paint = b.Paint
        b.Paint = function()
            paint()
            b.glyph:Draw(b.glyphKey, b.disabled and T.faint or b.active and T.accent or b.hover and T.text or T.muted)
        end
        b:HookScript("OnEnter", function() b.Paint() end)
        b:HookScript("OnLeave", function() b.Paint() end)
        if opts.hasCount ~= false then
            b.count = UI.text(b, "", "GameFontHighlightSmall", T.faint)
            b.count:SetPoint("RIGHT", -8, 0)
        end
        b:SetTextColor(T.muted)
        if opts.disabled then
            b:SetDisabled(true)
        end
        if opts.alpha then
            b:SetAlpha(opts.alpha)
        end
        if opts.onClick then
            b:SetScript("OnClick", opts.onClick)
        end
        UI.tip(b, function()
            local collapsed = sb.getCollapsed and sb.getCollapsed()
            if collapsed then
                return b.fullLabel
            end
            return opts.tip and (type(opts.tip) == "function" and opts.tip() or opts.tip) or nil
        end, opts.desc)
        self.navButtons[#self.navButtons + 1] = b
        return b
    end

    function shell:SetCollapseButton(b)
        self.navToggle = b
    end

    function shell:AddNavLabel(fs)
        self.navLabels[#self.navLabels + 1] = fs
        return fs
    end

    function shell:LayoutNav()
        local sb = cfg.sidebar
        if not (sb and nav) then
            return
        end
        local collapsed = sb.getCollapsed and sb.getCollapsed() and true or false
        local fullW = sb.width or 124
        local colW = sb.collapsedWidth or 42
        local w = collapsed and colW or fullW
        nav:SetWidth(w)
        if sb.collapseMode == "resize" and window then
            window:SetWidth(minW - (fullW - w))
        end
        for _, b in ipairs(self.navButtons) do
            b:SetWidth(w - 8)
            b:SetLabel(collapsed and "" or b.fullLabel)
            b.label:ClearAllPoints()
            b.glyph:ClearAllPoints()
            b.glyph:SetSize(collapsed and 20 or 16, collapsed and 20 or 16)
            if collapsed then
                b.label:SetPoint("CENTER")
                b.glyph:SetPoint("CENTER")
            else
                b.glyph:SetPoint("LEFT", 8, 0)
                b.label:SetPoint("LEFT", 31, 0)
                local countPad = b.count and (b.countPad or 26) or 5
                b.label:SetWidth(math.max(1, (w - 8) - 31 - countPad))
            end
            b.Paint()
            if b.count then
                b.count:SetShown(not collapsed)
            end
        end
        for _, fs in ipairs(self.navLabels) do
            fs:SetShown(not collapsed)
        end
        if self.navToggle then
            local t = self.navToggle
            t:SetLabel("")
            t.glyphKey = collapsed and "expand" or "collapse"
            t.glyph:SetSize(16, 16)
            t.glyph:ClearAllPoints()
            if collapsed then
                t.glyph:SetPoint("CENTER")
            else
                t.glyph:SetPoint("RIGHT", -1, 0)
            end
            t.Paint()
        end
    end

    function shell:ToggleSidebar()
        local sb = cfg.sidebar
        if not (sb and window) then
            return
        end
        if sb.collapseMode == "resize" then
            if sb.setCollapsed then
                sb.setCollapsed(not (sb.getCollapsed and sb.getCollapsed()))
            end
            self:LayoutNav()
            self:Refresh()
            return
        end
        -- Reflow mode: keep the outer window size and corner fixed.
        window:StopMovingOrSizing()
        pinTopLeft()
        local width, height = window:GetSize()
        if sb.setCollapsed then
            sb.setCollapsed(not (sb.getCollapsed and sb.getCollapsed()))
        end
        window:SetSize(width, height)
        self:Refresh()
        self:RequestRefresh()
    end

    function shell:ResetGeometry()
        if cfg.saveGeometry then
            cfg.saveGeometry({}, {})
        end
        if window then
            self:ApplyOpacity()
            window:StopMovingOrSizing()
            window:ClearAllPoints()
            window:SetSize(minW, minH)
            window:SetPoint("CENTER", UIParent, "CENTER")
            self:RequestRefresh()
        end
    end

    local function ensureCreated()
        if window then
            return
        end
        window = CreateFrame("Frame", cfg.name, UIParent)
        window:SetFrameStrata(cfg.strata or "HIGH")
        window:SetToplevel(true)
        window:SetClampedToScreen(true)
        window:SetPoint("CENTER")
        window:EnableMouse(true)
        window:SetMovable(true)
        if cfg.resizable then
            window:SetResizable(true)
            local maxW, maxH = resizeLimits()
            window:SetResizeBounds(minW, minH, maxW, maxH)
        end
        UI.panel(window, T.window)
        shell:ApplyOpacity()
        UI.shadow(window, 12, 0.9)
        if cfg.name and UISpecialFrames then
            table.insert(UISpecialFrames, cfg.name)
        end

        window:SetScript("OnHide", function()
            stopManipulation()
            window:SetScript("OnUpdate", nil)
            refreshQueued = false
            UI.CloseMenu()
            UI.CloseConfirm()
            UI.CloseIO()
            if cfg.onHide then
                cfg.onHide(shell)
            end
        end)

        if cfg.wordmark then
            buildWordmark(window, cfg.wordmark)
        end

        local close = CreateFrame("Button", nil, window)
        close:SetSize(16, 16)
        close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
        close:SetFrameLevel(window:GetFrameLevel() + 30)
        UI.fill(close, { 0.3, 0.3, 0.3, 0.25 })
        local closeIcon = close:CreateTexture(nil, "OVERLAY")
        closeIcon:SetAllPoints()
        closeIcon:SetTexture(UI.mediaRoot .. "close.tga")
        local hovered, pressed = false, false
        local function paintClose()
            if not close:IsEnabled() then
                closeIcon:SetVertexColor(0.5, 0.5, 0.5)
            elseif hovered or pressed then
                closeIcon:SetVertexColor(1, 0, 0)
            else
                closeIcon:SetVertexColor(1, 1, 1)
            end
        end
        close:SetScript("OnEnter", function() hovered = true; paintClose() end)
        close:SetScript("OnLeave", function() hovered = false; paintClose() end)
        close:SetScript("OnMouseDown", function() pressed = true; paintClose() end)
        close:SetScript("OnMouseUp", function() pressed = false; paintClose() end)
        close:SetScript("OnEnable", paintClose)
        close:SetScript("OnDisable", paintClose)
        close:SetScript("OnHide", function()
            hovered, pressed = false, false
            paintClose()
        end)
        close:SetScript("OnClick", function()
            window:Hide()
        end)

        main = CreateFrame("Frame", nil, window)
        if cfg.sidebar then
            nav = CreateFrame("Frame", nil, window)
            nav:SetPoint("TOPLEFT")
            nav:SetPoint("BOTTOMLEFT")
            nav:SetWidth(cfg.sidebar.width or 124)
            UI.panel(nav, T.sidebar)
            if cfg.sidebar.build then
                cfg.sidebar.build(nav, shell)
            end
            main:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
            main:SetPoint("BOTTOMRIGHT")
        else
            main:SetAllPoints(window)
        end

        if cfg.dragMode == "window" then
            window:RegisterForDrag("LeftButton")
            window:SetScript("OnDragStart", function()
                UI.CloseMenu()
                window:StartMoving()
            end)
            window:SetScript("OnDragStop", stopManipulation)
        else
            local dragArea = CreateFrame("Frame", nil, window)
            dragArea:SetPoint("TOPLEFT", main, "TOPLEFT")
            dragArea:SetPoint("TOPRIGHT", main, "TOPRIGHT")
            dragArea:SetHeight(48)
            dragArea:EnableMouse(true)
            dragArea:RegisterForDrag("LeftButton")
            dragArea:SetScript("OnDragStart", function()
                UI.CloseMenu()
                window:StartMoving()
            end)
            dragArea:SetScript("OnDragStop", stopManipulation)
        end

        status = CreateFrame("Frame", nil, window)
        status:SetHeight(20)
        if cfg.toastPlacement == "below" then
            status:SetPoint("TOP", window, "BOTTOM", 0, -6)
        else
            status:SetPoint("BOTTOM", main, "BOTTOM", 0, 8)
        end
        status:SetFrameLevel(window:GetFrameLevel() + 40)
        UI.panel(status, cfg.toastColor or T.popup)
        status.text = UI.text(status, "", "GameFontHighlightSmall", cfg.toastTextColor or T.text)
        status.text:SetPoint("CENTER")
        status.text:SetWordWrap(false)
        status:Hide()

        if cfg.resizable then
            local grip = CreateFrame("Button", nil, window)
            window.resizeGrip = grip
            grip:SetSize(16, 16)
            grip:SetPoint("BOTTOMRIGHT")
            grip:SetFrameLevel(window:GetFrameLevel() + 20)
            local mark = UI.text(grip, "//", "GameFontHighlightSmall", T.faint)
            mark:SetPoint("CENTER")
            grip:SetScript("OnMouseDown", function(_, mouse)
                local locked = cfg.getSizeLocked and cfg.getSizeLocked()
                if mouse == "LeftButton" and not locked then
                    UI.CloseMenu()
                    window:StopMovingOrSizing()
                    pinTopLeft()
                    window:StartSizing("BOTTOMRIGHT")
                end
            end)
            grip:SetScript("OnMouseUp", function(_, mouse)
                if mouse == "LeftButton" then
                    stopManipulation()
                    shell:RequestRefresh()
                end
            end)
            UI.tip(grip, "Resize", "Drag to resize. The size is saved.")
            window:SetScript("OnSizeChanged", function()
                if window:IsShown() then
                    shell:RequestRefresh()
                end
            end)

            local maxW, maxH = resizeLimits()
            local savedSize, position = {}, {}
            if cfg.loadGeometry then
                local s, p = cfg.loadGeometry()
                savedSize = s or {}
                position = p or {}
            end
            local function dim(v, lo, hi)
                return type(v) == "number" and v == v and math.max(lo, math.min(hi, v)) or lo
            end
            window:SetSize(dim(savedSize.width, minW, maxW), dim(savedSize.height, minH, maxH))
            if type(position.x) == "number" and type(position.y) == "number"
                and position.x == position.x and position.y == position.y
                and math.abs(position.x) < 10000 and math.abs(position.y) < 10000
            then
                window:ClearAllPoints()
                window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", position.x, position.y)
            end
        else
            window:SetSize(minW, minH)
        end

        if cfg.closeInCombat or cfg.closeOnRestricted then
            local watcher = CreateFrame("Frame")
            if cfg.closeInCombat then
                watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
            end
            if cfg.closeOnRestricted then
                pcall(watcher.RegisterEvent, watcher, "ADDON_RESTRICTION_STATE_CHANGED")
            end
            watcher:SetScript("OnEvent", function(_, event)
                if event == "PLAYER_REGEN_DISABLED" then
                    if window and window:IsShown() then
                        window:Hide()
                    end
                elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
                    C_Timer.After(0, function()
                        if window and window:IsShown() and UI.IsRestricted() then
                            window:Hide()
                        end
                    end)
                end
            end)
        end

        shell.window = window
        shell.nav = nav
        shell.main = main
        window:Hide()
    end

    function shell:Refresh()
        if not (window and window:IsShown()) then
            return
        end
        if cfg.resizable then
            local sizeLocked = cfg.getSizeLocked and cfg.getSizeLocked() or false
            window:SetResizable(not sizeLocked)
            if window.resizeGrip then
                window.resizeGrip:SetShown(not sizeLocked)
            end
        end
        if cfg.onRefresh then
            cfg.onRefresh(self)
        end
        if cfg.sidebar then
            self:LayoutNav()
        end
        for name, p in pairs(self.pages) do
            p.frame:SetShown(name == self.activePage)
        end
        if self.activePage then
            local p = self:GetPage(self.activePage)
            if p then
                p.frame:Show()
                if p.Refresh then
                    p:Refresh()
                end
            end
        end
    end

    function shell:Show(name)
        if (cfg.closeInCombat and InCombatLockdown()) or (cfg.closeOnRestricted and UI.IsRestricted()) then
            if cfg.combatMessage then
                DEFAULT_CHAT_FRAME:AddMessage(cfg.combatMessage)
            end
            return
        end
        if name then
            self.activePage = name
        end
        UI.CloseMenu()
        ensureCreated()
        window:Show()
        if cfg.onShow then
            cfg.onShow(self)
        end
        self:Refresh()
    end

    function shell:Hide()
        if window and window:IsShown() then
            window:Hide()
        end
    end

    function shell:Toggle(name)
        if window and window:IsShown() then
            window:Hide()
        else
            self:Show(name or self.activePage)
        end
    end

    function shell:IsShown()
        return window and window:IsShown() or false
    end

    return shell
end
