-- Square Minimap: square map with a thin border, without the round frame, and optional mouse wheel zoom.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local ROUND_MASK = "Textures\\MinimapMask"

-- Pieces of the round frame, hidden while the map is square. Missing ones are skipped.
local ROUND_PARTS = { "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag" }
local ZOOM_BUTTONS = { "MinimapZoomIn", "MinimapZoomOut" }

local mod
local border
local originalShape -- GetMinimapShape before we replaced it, nil when there was none
local wheelHooked, oldWheelScript, oldWheelEnabled

local function SquareShape() return "SQUARE" end

local function ShowParts(names, shown)
    for _, name in ipairs(names) do
        local part = _G[name]
        if part then
            if shown then part:Show() else part:Hide() end
        end
    end
end

-- Other minimap buttons (ours, LibDBIcon) read GetMinimapShape to know where to sit.
local function SetShape(square)
    if square then
        if GetMinimapShape ~= SquareShape then originalShape = GetMinimapShape end
        GetMinimapShape = SquareShape
    elseif GetMinimapShape == SquareShape then
        GetMinimapShape = originalShape
    end
    local button = TW.modules.MinimapButton
    if button and button.active and button.Place then button:Place() end
end

local function BuildBorder()
    border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
end

local function OnWheel(_, delta)
    if delta > 0 then
        if Minimap_ZoomIn then Minimap_ZoomIn() else Minimap:SetZoom(math.min(Minimap:GetZoom() + 1, Minimap:GetZoomLevels() - 1)) end
    else
        if Minimap_ZoomOut then Minimap_ZoomOut() else Minimap:SetZoom(math.max(Minimap:GetZoom() - 1, 0)) end
    end
end

local function SetWheelZoom(on)
    if on and not wheelHooked then
        oldWheelScript = Minimap:GetScript("OnMouseWheel")
        oldWheelEnabled = Minimap:IsMouseWheelEnabled()
        Minimap:EnableMouseWheel(true)
        Minimap:SetScript("OnMouseWheel", OnWheel)
        wheelHooked = true
    elseif not on and wheelHooked then
        Minimap:SetScript("OnMouseWheel", oldWheelScript)
        Minimap:EnableMouseWheel(oldWheelEnabled and true or false)
        wheelHooked = false
    end
end

local function Apply()
    local on = mod.active
    Minimap:SetMaskTexture(on and SQUARE_MASK or ROUND_MASK)
    ShowParts(ROUND_PARTS, not on)
    ShowParts(ZOOM_BUTTONS, not (on and mod.db.hideZoomButtons))
    SetShape(on)
    SetWheelZoom(on and mod.db.wheelZoom)

    if on and mod.db.border then
        if not border then BuildBorder() end
        local c = mod.db.borderColor
        border:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        border:Show()
    elseif border then
        border:Hide()
    end
end

mod = TW:NewModule("SquareMinimap", {
    title = L["Square Minimap"],
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    section = L["Interface"],
    desc = L["Makes the minimap square, with a thin border instead of the round frame. Can also zoom with the mouse wheel and hide the zoom buttons."],
    defaults = { border = true, borderColor = { r = 0, g = 0, b = 0 }, wheelZoom = true, hideZoomButtons = true },
    options = {
        { type = "toggle", key = "border", label = L["Border"] },
        { type = "color", key = "borderColor", label = L["Border color"] },
        { type = "toggle", key = "wheelZoom", label = L["Zoom with the mouse wheel"] },
        { type = "toggle", key = "hideZoomButtons", label = L["Hide the zoom buttons"] },
    },
})

function mod:OnEnable() Apply() end
function mod:OnDisable() Apply() end
function mod:OnOptionChanged() Apply() end
