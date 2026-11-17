-- Minimap: square map with a border, its icons in a column, without the round frame, and optional mouse wheel zoom.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local ROUND_MASK = "Textures\\MinimapMask"

-- Pieces of the round frame, hidden while the map is square. Missing ones are skipped.
local ROUND_PARTS = { "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag" }
-- Zoom buttons: globals on older clients, children of the map on newer ones (shown on hover).
local function ZoomButtons()
    local list, seen = {}, {}
    for _, b in ipairs({ _G.MinimapZoomIn, _G.MinimapZoomOut, Minimap.ZoomIn, Minimap.ZoomOut }) do
        if b and not seen[b] then seen[b] = true; list[#list + 1] = b end
    end
    return list
end

-- Made invisible rather than hidden: the map shows them again on hover.
local function ShowZoomButtons(shown)
    for _, b in ipairs(ZoomButtons()) do
        b:SetAlpha(shown and 1 or 0)
        b:EnableMouse(shown)
    end
end

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

-- The buttons beside the map stand in one column, left or right: ours, LibDBIcon's (BugSack,
-- RXPGuides...) and ForeverCore's (SkillUp...). Both libraries place their buttons again when they
-- create, show, refresh or drag them: each time they go back in the column, where dragging is off.
local SPACING = 32 -- a 31 pixel button and a small gap

local function LibDBIcon()
    return LibStub and LibStub("LibDBIcon-1.0", true)
end

local function ForeverButtons()
    local core = _G.ForeverCore
    local lib = type(core) == "table" and core.MinimapButton
    return type(lib) == "table" and type(lib.Buttons) == "function" and lib or nil
end

-- Ours first, then the others by name, so the order stays the same from one session to the next.
local function ColumnButtons()
    local own = _G.TinkerwiseMinimapButton
    local others = {}
    local lib = LibDBIcon()
    if lib and lib.objects then
        for name, button in pairs(lib.objects) do
            if not (button.db and button.db.hide) then others[#others + 1] = { name = name, button = button } end
        end
    end
    local fc = ForeverButtons()
    if fc then
        for _, button in ipairs(fc.Buttons()) do
            if button:IsShown() then
                local spec = button.minimapButtonSpec
                others[#others + 1] = { name = spec and spec.title or button:GetName() or "", button = button }
            end
        end
    end
    table.sort(others, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    local list = {}
    if own and own:IsShown() then list[1] = own end
    for _, entry in ipairs(others) do list[#list + 1] = entry.button end
    return list, own
end

-- Drag scripts of the other addons' buttons, kept to give them back when the column goes.
local savedDrag = {}

local function Layout()
    if not (mod and mod.active) then return end
    local right = mod.db.iconSide == "right"
    local gap = (mod.db.border and (mod.db.borderSize or 3) or 0) + 3
    local perColumn = math.max(1, math.floor((Minimap:GetHeight() + gap) / SPACING))
    local buttons, own = ColumnButtons()
    for i, button in ipairs(buttons) do
        local column, row = math.floor((i - 1) / perColumn), (i - 1) % perColumn
        local x, y = gap + column * SPACING, -row * SPACING
        button:ClearAllPoints()
        if right then
            button:SetPoint("TOPLEFT", Minimap, "TOPRIGHT", x, y)
        else
            button:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -x, y)
        end
        if button ~= own then
            local start, stop = button:GetScript("OnDragStart"), button:GetScript("OnDragStop")
            if start or stop then savedDrag[button] = { start, stop } end
            button:SetScript("OnDragStart", nil)
            button:SetScript("OnDragStop", nil)
        end
    end
end

-- True while the icons stand in the column: our button then neither moves around nor drags.
function ns.MinimapIconsInColumn() return mod and mod.active or false end
ns.LayoutMinimapIcons = Layout

local libHooked, foreverHooked = false, false
local function HookLibraries()
    local lib = LibDBIcon()
    if lib and not libHooked then
        libHooked = true
        for _, method in ipairs({ "Register", "Show", "Hide", "Refresh" }) do
            if type(lib[method]) == "function" then hooksecurefunc(lib, method, Layout) end
        end
    end
    local fc = ForeverButtons()
    if fc and not foreverHooked then
        foreverHooked = true
        for _, method in ipairs({ "Create", "Destroy", "Refresh", "SetShown" }) do
            if type(fc[method]) == "function" then hooksecurefunc(fc, method, Layout) end
        end
    end
end

-- Back to each library's own placement around the map, dragging included.
local function RestoreIcons()
    for button, scripts in pairs(savedDrag) do
        button:SetScript("OnDragStart", scripts[1])
        button:SetScript("OnDragStop", scripts[2])
    end
    wipe(savedDrag)
    local lib = LibDBIcon()
    if lib and lib.objects then
        for name in pairs(lib.objects) do lib:Refresh(name) end
    end
    local fc = ForeverButtons()
    if fc and type(fc.Refresh) == "function" then fc.Refresh() end
end

-- Other minimap buttons read GetMinimapShape to know where to sit.
local function SetShape(square)
    if square then
        if GetMinimapShape ~= SquareShape then originalShape = GetMinimapShape end
        GetMinimapShape = SquareShape
        HookLibraries()
        Layout()
    elseif GetMinimapShape == SquareShape then
        GetMinimapShape = originalShape
        RestoreIcons()
    end
    local button = TW.modules.MinimapButton
    if button and button.active and button.Place then button:Place() end
end

local function BuildBorder()
    border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
    border:SetFrameLevel(Minimap:GetFrameLevel() + 1)
end

-- The border sits outside the map, as thick as the option says.
local function SizeBorder(size)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", -size, size)
    border:SetPoint("BOTTOMRIGHT", size, -size)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = size })
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

-- The quest, task and archaeology areas draw a round ring at the edge of the map: hide it when square.
local RING_SETTERS = {
    "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha",
    "SetTaskBlobRingScalar", "SetTaskBlobRingAlpha",
    "SetArchBlobRingScalar", "SetArchBlobRingAlpha",
}

local function ShowRings(shown)
    for _, setter in ipairs(RING_SETTERS) do
        if Minimap[setter] then Minimap[setter](Minimap, shown and 1 or 0) end
    end
end

local function Apply()
    local on = mod.active
    Minimap:SetMaskTexture(on and SQUARE_MASK or ROUND_MASK)
    ShowRings(not on)
    ShowParts(ROUND_PARTS, not on)
    ShowZoomButtons(not (on and mod.db.hideZoomButtons))
    SetShape(on)
    SetWheelZoom(on and mod.db.wheelZoom)

    if on and mod.db.border then
        if not border then BuildBorder() end
        SizeBorder(mod.db.borderSize or 3)
        local c = mod.db.borderColor
        border:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        border:Show()
    elseif border then
        border:Hide()
    end
end

mod = TW:NewModule("SquareMinimap", {
    title = "Minimap", -- same name in every language; L["Minimap"] is Immersion's "Minicarte"
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    section = L["Interface"],
    desc = L["Makes the minimap square, with a bronze border instead of the round frame, and lines its icons up in a column on the left or right. Can also zoom with the mouse wheel and hide the zoom buttons."],
    defaults = { border = true, borderColor = { r = 0.6, g = 0.5, b = 0.35 }, borderSize = 3, wheelZoom = true, hideZoomButtons = true, iconSide = "left" },
    options = {
        { type = "toggle", key = "border", label = L["Border"] },
        { type = "slider", key = "borderSize", label = L["Border thickness"], min = 1, max = 6, step = 1 },
        { type = "color", key = "borderColor", label = L["Border color"] },
        { type = "toggle", key = "wheelZoom", label = L["Zoom with the mouse wheel"] },
        { type = "toggle", key = "hideZoomButtons", label = L["Hide the zoom buttons"] },
        { type = "select", key = "iconSide", label = L["Minimap icons"], values = {
            { "left", L["On the left"] },
            { "right", L["On the right"] },
        } },
    },
})

-- The border used to be black by default: move an untouched black one to the bronze of the interface.
local function UpgradeColor()
    local c = mod.db.borderColor
    if not mod.db.bronzeBorder and c.r == 0 and c.g == 0 and c.b == 0 then
        mod.db.borderColor = { r = 0.6, g = 0.5, b = 0.35 }
    end
    mod.db.bronzeBorder = true
end

-- The game finishes laying out the minimap (edit mode, size) after login: line the icons up again
-- once the world is loaded and each time the map changes size.
local function Replace()
    Layout()
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function() C_Timer.After(0.5, Replace) end)
local sizeHooked = false

function mod:OnEnable()
    UpgradeColor()
    Apply()
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    if not sizeHooked then
        sizeHooked = true
        Minimap:HookScript("OnSizeChanged", Replace)
    end
end

function mod:OnDisable()
    watcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Apply()
end
function mod:OnOptionChanged() Apply() end
