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
-- RXPGuides...), ForeverCore's (SkillUp...) and those other addons build on their own (Queston...).
-- They place their buttons again when they like: each time they go back in the column, where dragging
-- is off. The ones that don't fit, or that the player sends there, go in a drawer.
local SPACING = 32 -- a 31 pixel button and a small gap

local function LibDBIcon()
    return LibStub and LibStub("LibDBIcon-1.0", true)
end

local function ForeverButtons()
    local core = _G.ForeverCore
    local lib = type(core) == "table" and core.MinimapButton
    return type(lib) == "table" and type(lib.Buttons) == "function" and lib or nil
end

-- The name of a button an addon built by itself on the map, nil for anything else (the game's own
-- buttons, map pins, protected buttons, which can't be moved in combat).
local function StandaloneName(button)
    if button.IsForbidden and button:IsForbidden() then return end
    if not button:IsObjectType("Button") or button:IsProtected() then return end
    local name = button:GetName()
    if type(name) ~= "string" or issecurevariable(_G, name) then return end
    local lower = name:lower()
    if lower:find("pin", 1, true) then return end
    local short = name:match("^LibDBIcon10_(.+)")
    if not short then
        if not lower:find("minimap", 1, true) or not (lower:find("button", 1, true) or lower:find("icon", 1, true)) then return end
        local width = button:GetWidth()
        if width < 20 or width > 45 then return end
        short = name:gsub("_?[Mm]ini[Mm]ap_?[Bb]utton.*$", ""):gsub("_?[Mm]ini[Mm]ap_?[Ii]con.*$", "")
    end
    return short ~= "" and short or name
end

local names = {} -- button of another addon -> name shown in the options
local HookButton
local drawer, drawerButton

local function Collect()
    local own = _G.TinkerwiseMinimapButton
    local function Add(button, name)
        if button and button ~= own and button ~= drawerButton and not names[button] then
            names[button] = tostring(name)
            HookButton(button)
        end
    end
    local lib = LibDBIcon()
    for name, button in pairs(lib and lib.objects or {}) do Add(button, name) end
    local fc = ForeverButtons()
    for _, button in ipairs(fc and fc.Buttons() or {}) do
        local spec = button.minimapButtonSpec
        Add(button, spec and spec.title or button:GetName() or "?")
    end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not names[child] then
            local name = StandaloneName(child)
            if name then Add(child, name) end
        end
    end
    return own
end

-- Ours first, then the others by name, so the order stays the same from one session to the next.
local function ColumnButtons()
    local own = Collect()
    local others = {}
    for button in pairs(names) do
        if button:IsShown() then others[#others + 1] = button end
    end
    table.sort(others, function(a, b)
        local na, nb = names[a]:lower(), names[b]:lower()
        if na ~= nb then return na < nb end
        return (a:GetName() or "") < (b:GetName() or "")
    end)
    return others, own and own:IsShown() and own or nil
end

local original = {} -- button of another addon -> how it was before the column
local arranging = false

local function Remember(button)
    if original[button] then return end
    local point, relative, relativePoint, x, y = button:GetPoint()
    original[button] = {
        point = point and { point, relative, relativePoint, x, y },
        fixedStrata = button.HasFixedFrameStrata and button:HasFixedFrameStrata(),
        fixedLevel = button.HasFixedFrameLevel and button:HasFixedFrameLevel(),
        parent = button:GetParent(), strata = button:GetFrameStrata(), level = button:GetFrameLevel(),
    }
end

-- Drag scripts of the other addons' buttons, kept to give them back when the column goes.
local savedDrag = {}

local function StopDragging(button)
    local start, stop = button:GetScript("OnDragStart"), button:GetScript("OnDragStop")
    if start or stop then savedDrag[button] = { start, stop } end
    button:SetScript("OnDragStart", nil)
    button:SetScript("OnDragStop", nil)
end

-- Puts the button in a frame, at its strata and level. LibDBIcon fixes both on its buttons: they then
-- ignore any change, and stayed under the drawer.
local function MoveTo(button, parent, strata, level, fixedStrata, fixedLevel)
    if button.SetFixedFrameStrata then button:SetFixedFrameStrata(false) end
    if button.SetFixedFrameLevel then button:SetFixedFrameLevel(false) end
    if button:GetParent() ~= parent then button:SetParent(parent) end
    button:SetFrameStrata(strata)
    button:SetFrameLevel(level)
    if fixedStrata then button:SetFixedFrameStrata(true) end
    if fixedLevel then button:SetFixedFrameLevel(true) end
end

local function BuildDrawer()
    drawerButton = TW:CreateRoundButton("TinkerwiseMinimapDrawerButton", Minimap, "Interface\\Icons\\INV_Misc_Bag_08")
    drawerButton:SetScript("OnClick", function()
        GameTooltip:Hide()
        drawer:SetShown(not drawer:IsShown())
    end)
    drawerButton:SetScript("OnEnter", function(self)
        if drawer:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Icon drawer"])
        GameTooltip:AddLine(format(L["%d icons"], self.icons or 0), 1, 1, 1)
        GameTooltip:Show()
    end)
    drawerButton:SetScript("OnLeave", GameTooltip_Hide)

    drawer = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
    drawer:SetFrameStrata("HIGH")
    drawer:SetClampedToScreen(true)
    drawer:EnableMouse(true)
    drawer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    drawer:SetBackdropColor(0.06, 0.04, 0.02, 0.95)
    drawer:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)
    drawer:Hide()
    -- A click elsewhere closes it.
    drawer:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    drawer:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    drawer:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not drawerButton:IsMouseOver() then self:Hide() end
    end)
end

-- Which buttons stay beside the map, and which go in the drawer.
local function Split(others, own, perColumn)
    local beside, inside = {}, {}
    local skip = mod.db.drawerIcons
    for _, button in ipairs(others) do
        local list = skip and skip[names[button]] and inside or beside
        list[#list + 1] = button
    end
    if mod.db.overflow == "drawer" then
        local ours = own and 1 or 0
        local room = mod.db.maxIcons
        if room == 0 then -- one full column, the button of the drawer included
            room = perColumn
            if ours + #beside + (#inside > 0 and 1 or 0) > room then room = room - 1 end
        end
        room = math.max(room - ours, 0)
        local extra = {}
        while #beside > room do table.insert(extra, 1, table.remove(beside)) end
        for _, button in ipairs(extra) do inside[#inside + 1] = button end
    end
    if own then table.insert(beside, 1, own) end
    return beside, inside
end

local DRAWER_PAD = 8

local function FillDrawer(inside, right)
    if #inside == 0 then
        if drawer then
            drawer:Hide()
            drawerButton:Hide()
        end
        return
    end
    if not drawer then BuildDrawer() end
    drawerButton.icons = #inside
    drawerButton:Show()
    local columns = math.min(math.ceil(math.sqrt(#inside)), 5)
    drawer:SetSize(2 * DRAWER_PAD + columns * SPACING, 2 * DRAWER_PAD + math.ceil(#inside / columns) * SPACING)
    drawer:ClearAllPoints()
    if right then
        drawer:SetPoint("TOPLEFT", drawerButton, "TOPRIGHT", 4, 0)
    else
        drawer:SetPoint("TOPRIGHT", drawerButton, "TOPLEFT", -4, 0)
    end
    for i, button in ipairs(inside) do
        MoveTo(button, drawer, drawer:GetFrameStrata(), drawer:GetFrameLevel() + 5)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", drawer, "TOPLEFT",
            DRAWER_PAD + ((i - 1) % columns) * SPACING, -DRAWER_PAD - math.floor((i - 1) / columns) * SPACING)
    end
end

local function TakeOutOfDrawer(button)
    local o = original[button]
    if o and drawer and button:GetParent() == drawer then
        MoveTo(button, o.parent or Minimap, o.strata, o.level, o.fixedStrata, o.fixedLevel)
    end
end

local function Arrange()
    local right = mod.db.iconSide == "right"
    local gap = (mod.db.border and (mod.db.borderSize or 3) or 0) + 3
    local perColumn = math.max(1, math.floor((Minimap:GetHeight() + gap) / SPACING))
    local others, own = ColumnButtons()
    for _, button in ipairs(others) do
        Remember(button)
        StopDragging(button)
    end
    local beside, inside = Split(others, own, perColumn)
    FillDrawer(inside, right)
    if #inside > 0 then beside[#beside + 1] = drawerButton end
    for i, button in ipairs(beside) do
        local column, row = math.floor((i - 1) / perColumn), (i - 1) % perColumn
        local x, y = gap + column * SPACING, -row * SPACING
        TakeOutOfDrawer(button)
        button:ClearAllPoints()
        if right then
            button:SetPoint("TOPLEFT", Minimap, "TOPRIGHT", x, y)
        else
            button:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -x, y)
        end
    end
end

local function Layout()
    if not (mod and mod.active) or arranging then return end
    arranging = true
    local ok, err = pcall(Arrange) -- whatever happens, the next one must not be held back
    arranging = false
    if not ok then geterrorhandler()(err) end
end

local scheduled = false
local function ScheduleLayout()
    if scheduled or arranging or not (mod and mod.active) then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        Layout()
    end)
end

-- The addon of the button moves, shows or hides it: the column is done again. Opening the drawer also
-- runs these scripts, but doesn't change what the button itself says.
HookButton = function(button)
    local shown = button:IsShown()
    local function OnVisibility()
        if button:IsShown() == shown then return end
        shown = button:IsShown()
        ScheduleLayout()
    end
    hooksecurefunc(button, "SetPoint", function(_, point, relative, relativePoint, x, y)
        if arranging or not mod.active then return end
        local o = original[button]
        if o then o.point = { point, relative, relativePoint, x, y } end
        ScheduleLayout()
    end)
    hooksecurefunc(button, "Show", OnVisibility)
    hooksecurefunc(button, "Hide", OnVisibility)
    hooksecurefunc(button, "SetShown", OnVisibility)
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
    if drawer then
        drawer:Hide()
        drawerButton:Hide()
    end
    for button, o in pairs(original) do
        TakeOutOfDrawer(button)
        if o.point then
            button:ClearAllPoints()
            button:SetPoint(unpack(o.point, 1, 5))
        end
    end
    wipe(original)
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

-- The dark theme, when it covers the minimap, gives its own tint to the border.
local function ColorBorder()
    if not border then return end
    local c = mod.db.borderColor
    local r, g, b = c.r, c.g, c.b
    if ns.DarkThemeTint then
        local dr, dg, db = ns.DarkThemeTint("minimap")
        if dr then r, g, b = dr, dg, db end
    end
    border:SetBackdropBorderColor(r, g, b, 1)
end
ns.ColorMinimapBorder = ColorBorder

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
        ColorBorder()
        border:Show()
    elseif border then
        border:Hide()
    end
end

mod = TW:NewModule("SquareMinimap", {
    title = "Minimap", -- same name in every language; L["Minimap"] is Immersion's "Minicarte"
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    section = L["Interface"],
    desc = L["Makes the minimap square, with a bronze border instead of the round frame, and lines its icons up in a column on the left or right, the ones that don't fit in a drawer. Can also zoom with the mouse wheel and hide the zoom buttons."],
    defaults = { border = true, borderColor = { r = 0.6, g = 0.5, b = 0.35 }, borderSize = 3, wheelZoom = true, hideZoomButtons = true, iconSide = "left",
        overflow = "drawer", maxIcons = 0 },
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
        { type = "header", label = L["Icon drawer"] },
        { type = "select", key = "overflow", label = L["Too many icons"], values = {
            { "drawer", L["Put the rest in a drawer"] },
            { "columns", L["Add columns"] },
        } },
        { type = "slider", key = "maxIcons", label = L["Icons outside the drawer (0 = one full column)"], min = 0, max = 15, step = 1 },
        { type = "header", label = L["Icons beside the map (unticked: in the drawer)"] },
        { type = "checklist", key = "drawerIcons", items = function()
            local list, seen = {}, {}
            for button, name in pairs(names) do
                if button:IsShown() and not seen[name] then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
            table.sort(list, function(a, b) return a:lower() < b:lower() end)
            return list
        end },
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
watcher:SetScript("OnEvent", function()
    for _, delay in ipairs({ 0.5, 3, 10 }) do C_Timer.After(delay, Replace) end -- some addons build theirs late
end)
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
