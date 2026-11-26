-- UI/Kit/Theme.lua
-- Flat borderless UI palette, class-accent tracking, pixel helpers, surfaces
-- and tooltips. Self-contained and addon-agnostic; host addons can inject
-- optional hooks through UI.Configure(opts).

local addonName, ns = ...

local UI = ns.UI or {}
ns.UI = UI

UI.PAD = 12
UI.ROW = 22
UI.HEADER_Y = -14
UI.mediaRoot = ("Interface\\AddOns\\%s\\Media\\Icons\\"):format(addonName)

local config = {}

-- Optional host hooks:
--   mediaRoot      string: overrides Media/Icons/ path
--   getPriestAccent fn() -> { r, g, b[, a] } | nil
--   isRestricted   fn() -> boolean (default checks Combat/Encounter/PvPMatch)
--   guardWrites    boolean (when true, widget clicks/edits no-op while restricted)
--   fallbackAccent { r, g, b[, a] } (default sage #a9bfaa)
function UI.Configure(opts)
    if type(opts) ~= "table" then
        return
    end
    for k, v in pairs(opts) do
        config[k] = v
    end
    if type(opts.mediaRoot) == "string" and opts.mediaRoot ~= "" then
        UI.mediaRoot = opts.mediaRoot
    end
end

local function isKnown(value)
    if value == nil then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return false
    end
    if _G and _G.canaccessvalue and not _G.canaccessvalue(value) then
        return false
    end
    return true
end

local function isFinite(value)
    return isKnown(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Colours: hex to 0..1 RGBA table.
local function rgb(hexString, a)
    local r, g, b = hexString:match("#(%x%x)(%x%x)(%x%x)")
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, a or 1 }
end
UI.rgb = rgb

-- Mapita/Obscura's black window with neutral greys and layered white tints;
-- floating menus and dialogs use opaque `popup`.
local T = {
    window = { 0, 0, 0, 1 },
    sidebar = { 0, 0, 0, 0.45 },
    popup = rgb("#0b0b0b"),
    surface = rgb("#ffffff", 0.035),
    band = rgb("#ffffff", 0.045),
    bandStrong = rgb("#ffffff", 0.06),
    control = rgb("#ffffff", 0.075),
    hover = rgb("#ffffff", 0.12),
    pressed = rgb("#ffffff", 0.17),
    accentSoft = rgb("#a9bfaa", 30 / 255),
    text = rgb("#e6e6e6"),
    muted = rgb("#8e8e8e"),
    faint = rgb("#737373"),
    accent = rgb("#a9bfaa"),
    warning = rgb("#e5b663"),
    danger = rgb("#d88e83"),
    ok = rgb("#8fd18f"),
    none = { 0, 0, 0, 0 },
    black = { 0, 0, 0, 1 },
}
UI.T = T

local SAGE = rgb("#a9bfaa")

function UI.hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Two colours alike to the 8-bit value a picker shows (alpha: 1 if absent).
function UI.SameColor(a, b)
    for i = 1, 4 do
        local x, y = a[i] or 1, b[i] or 1
        if math.floor(x * 255 + 0.5) ~= math.floor(y * 255 + 0.5) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Combat & Forever addon restrictions
--------------------------------------------------------------------------------

local DEFAULT_RESTRICTIONS = { "Combat", "Encounter", "PvPMatch" }

function UI.IsRestricted()
    if config.isRestricted then
        return config.isRestricted() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    local types = Enum and Enum.AddOnRestrictionType
    local isActive = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
    if not (types and isActive) then
        return false
    end
    for _, name in ipairs(DEFAULT_RESTRICTIONS) do
        local t = types[name]
        if t ~= nil then
            local ok, active = pcall(isActive, t)
            if ok and active == true then
                return true
            end
        end
    end
    return false
end

function UI.WritesBlocked()
    return config.guardWrites == true and UI.IsRestricted() or false
end

--------------------------------------------------------------------------------
-- Class accent & live recolouring
--------------------------------------------------------------------------------

function UI.ClassColour(class)
    local key = class or select(2, UnitClass("player")) or ""
    local c = C_ClassColor and C_ClassColor.GetClassColor(key)
    c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[key])
    if c then
        return { c.r, c.g, c.b, 1 }
    end
    local fb = config.fallbackAccent or SAGE
    return { fb[1], fb[2], fb[3], 1 }
end

function UI.IsPriest()
    return select(2, UnitClass("player")) == "PRIEST"
end

function UI.PriestAccent()
    local c = config.getPriestAccent and config.getPriestAccent()
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return { c[1], c[2], c[3], 1 }
    end
    return { 1, 1, 1, 1 }
end

function UI.HeaderColour()
    return UI.IsPriest() and UI.PriestAccent() or UI.ClassColour()
end

function UI.AccentColour()
    if UI.IsPriest() then
        return UI.PriestAccent()
    end
    local c = UI.ClassColour()
    local mix, base = 0.75, 0.72
    return { base + (c[1] - base) * mix, base + (c[2] - base) * mix, base + (c[3] - base) * mix, 1 }
end

-- Every accent colour table and the alpha it carries.
local accentTints = { [T.accent] = 1, [T.accentSoft] = 30 / 255 }
local accentTextures = setmetatable({}, { __mode = "k" }) -- texture -> tint
local accentAlpha = setmetatable({}, { __mode = "k" })    -- texture -> alpha
local accentTexts = setmetatable({}, { __mode = "k" })    -- font string -> tint
UI.accentButtons = setmetatable({}, { __mode = "k" })
UI.accentGlyphs = setmetatable({}, { __mode = "k" })      -- glyph -> texture
local accentPainters = {}
local wordmarkFns = {}

function UI.IsAccent(c)
    return c ~= nil and accentTints[c] ~= nil
end

function UI.AccentTint(alpha)
    local c = { T.accent[1], T.accent[2], T.accent[3], alpha }
    accentTints[c] = alpha
    return c
end

function UI.OnAccent(fn)
    accentPainters[#accentPainters + 1] = fn
end

function UI.OnHeaderColour(fn)
    wordmarkFns[#wordmarkFns + 1] = fn
end

function UI.TrackColor(t, c, alpha)
    if accentTints[c] then
        accentTextures[t], accentAlpha[t] = c, alpha or false
    elseif accentTextures[t] then
        accentTextures[t] = nil
        accentAlpha[t] = nil
    end
end

local function setColor(t, c, alpha)
    t:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
    UI.TrackColor(t, c, alpha)
end
UI.SetColor = setColor

function UI.ApplyAccent()
    local a = UI.AccentColour()
    for c, alpha in pairs(accentTints) do
        c[1], c[2], c[3], c[4] = a[1], a[2], a[3], alpha
    end
    for t, c in pairs(accentTextures) do
        t:SetColorTexture(c[1], c[2], c[3], c[4] * (accentAlpha[t] or 1))
    end
    for fs, c in pairs(accentTexts) do
        fs:SetTextColor(c[1], c[2], c[3], c[4])
    end
    for f, icon in pairs(UI.accentGlyphs) do
        if f.color then
            icon:SetVertexColor(unpack(f.color))
        end
    end
    for b in pairs(UI.accentButtons) do
        if b.Paint then
            b.Paint()
        end
    end
    for _, fn in ipairs(accentPainters) do
        fn()
    end
    for _, fn in ipairs(wordmarkFns) do
        fn()
    end
end

--------------------------------------------------------------------------------
-- Pixel geometry & flat surfaces
--------------------------------------------------------------------------------

function UI.Crisp(t)
    if t and t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

function UI.PixelSize(region)
    local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()
    local scale = region and region.GetEffectiveScale and region:GetEffectiveScale()
    if not (isFinite(factor) and factor > 0 and isFinite(scale) and scale > 0) then
        return 1
    end
    return factor / scale
end

function UI.Pixels(region, count, minPixels)
    local px = UI.PixelSize(region)
    local n = math.floor((count or 0) + 0.5)
    if minPixels and count ~= 0 then
        n = math.max(minPixels, n)
    end
    return n * px
end

-- Crisp N-pixel edge inside f: four non-overlapping strips.
function UI.Edge(f, layer, pixels)
    local t = { owner = f }
    for i = 1, 4 do
        t[i] = UI.Crisp(f:CreateTexture(nil, layer or "OVERLAY", nil, 7))
    end
    local size = UI.Pixels(f, pixels or 1, 1)
    t[1]:SetPoint("TOPLEFT")
    t[1]:SetPoint("TOPRIGHT")
    t[1]:SetHeight(size)
    t[2]:SetPoint("BOTTOMLEFT")
    t[2]:SetPoint("BOTTOMRIGHT")
    t[2]:SetHeight(size)
    t[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -size)
    t[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, size)
    t[3]:SetWidth(size)
    t[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -size)
    t[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, size)
    t[4]:SetWidth(size)
    return t
end

function UI.SetEdge(edge, c)
    for _, t in ipairs(edge) do
        setColor(t, c or T.control)
    end
end

function UI.TextSize(fs, size)
    if size then
        local font, _, flags = fs:GetFont()
        fs:SetFont(font, size, flags)
    end
end

function UI.fill(f, color, alpha, layer)
    local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, -8)
    t:SetAllPoints()
    setColor(t, color, alpha)
    return t
end

-- A flat fill; `base` is the colour it returns to after a hover.
function UI.panel(f, color)
    f.base = color or T.control
    f.bg = UI.fill(f, f.base)
    return f
end

function UI.shade(f, color)
    setColor(f.bg, color)
end

-- Soft drop shadow around a frame using a 9-slice TGA (`shadow.tga`).
function UI.shadow(parent, thickness, alpha)
    thickness = thickness or 12
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
    f:EnableMouse(false)
    local path = UI.mediaRoot .. "shadow.tga"
    local uv = { 0, 0.25, 0.75, 1 }
    local corner = { [1] = "TOPLEFT", [3] = "TOPRIGHT", [7] = "BOTTOMLEFT", [9] = "BOTTOMRIGHT" }
    for index = 1, 9 do
        if index ~= 5 then
            local col, row = (index - 1) % 3 + 1, math.floor((index - 1) / 3) + 1
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

function UI.text(parent, s, template, color)
    local t = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    t:SetTextColor(unpack(color or T.text))
    if color and accentTints[color] then
        accentTexts[t] = color
    end
    t:SetJustifyH("LEFT")
    t:SetText(s or "")
    return t
end

-- A tooltip: a title and an explanation (either may be a function).
function UI.tip(f, title, desc)
    f:HookScript("OnEnter", function(self)
        if GetCursorInfo and GetCursorInfo() then
            return
        end
        local t, d = title, desc
        if type(t) == "function" then
            t = t()
        end
        if type(d) == "function" then
            d = d()
        end
        if type(t) ~= "string" or t == "" then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(t, 1, 1, 1)
        if type(d) == "string" and d ~= "" then
            GameTooltip:AddLine(d, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    f:HookScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
end
