-- UI/Kit/Glyphs.lua
-- Multi-size TGA spritesheet glyph renderer (`256x64` packed TGA in `UI.mediaRoot`).
-- Crops the rendered size matching on-screen physical pixels so small icons stay
-- crisp across UI scales and refresh automatically on scale/display changes.

local _, ns = ...
local UI = ns.UI

local TEX_W, TEX_H, BIG = 256, 64, 64
local SIZES = { 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32 }
local SLOT = {
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

local allGlyphs = setmetatable({}, { __mode = "k" })

local function pixels(f, size)
    if not GetPhysicalScreenSize then
        return nil
    end
    local _, height = GetPhysicalScreenSize()
    if issecretvalue and issecretvalue(height) then
        return nil
    end
    if type(height) ~= "number" or height <= 0 then
        return nil
    end
    local scale = f:GetEffectiveScale()
    if issecretvalue and issecretvalue(scale) then
        return nil
    end
    if type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    return math.floor(size * scale * height / 768 + 0.5)
end

local function bestSize(px)
    if not px then
        return nil
    end
    for _, n in ipairs(SIZES) do
        if n >= px then
            return n
        end
    end
    return nil
end

function UI.RefreshGlyphs()
    for f in pairs(allGlyphs) do
        if f:IsVisible() and f._glyphKey then
            f:Draw(f._glyphKey, f.color)
        end
    end
end

local scaleWatcher = CreateFrame("Frame")
local scaleQueued = false
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatcher:SetScript("OnEvent", function()
    if scaleQueued then
        return
    end
    scaleQueued = true
    C_Timer.After(0, function()
        scaleQueued = false
        UI.RefreshGlyphs()
    end)
end)

function UI.Glyph(parent, name, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size or 16, size or 16)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    f.texture = icon -- callers may rotate it (e.g. an up chevron)
    local current, currentPx

    local function load(key)
        if type(key) ~= "string" or key == "" then
            icon:SetTexture(nil)
            return nil
        end
        local n = bestSize(pixels(f, f:GetWidth())) or BIG
        local x, y = unpack(SLOT[n])
        icon:SetTexture(UI.mediaRoot .. key .. ".tga")
        icon:SetTexCoord(x / TEX_W, (x + n) / TEX_W, y / TEX_H, (y + n) / TEX_H)
        return n
    end

    function f.Draw(_, key, color)
        local px = pixels(f, f:GetWidth())
        if current ~= key or currentPx ~= px then
            load(key)
            current, currentPx = key, px
            f._glyphKey = key
        end
        color = color or UI.T.muted
        f.color = color
        icon:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        UI.accentGlyphs[f] = UI.IsAccent(color) and icon or nil
    end

    -- Scale is only final once the glyph is shown in its window.
    f:SetScript("OnShow", function()
        if current then
            f:Draw(current, f.color)
        end
    end)

    allGlyphs[f] = true
    f:Draw(name)
    return f
end
