-- FlightMode: during a flight master trip, the interface fades away and black bands show the route,
-- the zone below and the time. The camera is left alone. Each route's duration is remembered, which
-- gives an estimate of the time left from the second flight on. When the scene doesn't play (turned
-- off, closed, combat), a progress bar at the top of the screen shows the time left. The flight map
-- tooltips show the duration of the routes already flown.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local ImmersionScene = ns.ImmersionScene

local issecretvalue = _G.issecretvalue

local CHECK_EVERY = 0.5
local MIN_RECORDED_FLIGHT = 5 -- seconds; shorter means the flight did not really happen

local db, ticker
local routes = {} -- "From > To" -> seconds, shared by all the characters of the account (TinkerwiseDB)
local flying, dismissed, testing = false, false, false
local startedAt, route, pendingRoute

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local scene = ImmersionScene.Create({ name = "TinkerwiseFlightScene", bandHeight = 110, closable = true, windows = true })
local topBand, bottomBand = scene.topBand, scene.bottomBand

local title = scene:CreateTitle(topBand, 34)
title:SetPoint("CENTER", topBand, "CENTER", 0, 0)

local origin = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
origin:SetPoint("TOPLEFT", bottomBand, "TOPLEFT", 40, -24)

local zone = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
zone:SetPoint("TOPLEFT", origin, "BOTTOMLEFT", 0, -6)

local timer = scene:CreateTitle(bottomBand, 24)
timer:SetPoint("TOPRIGHT", bottomBand, "TOPRIGHT", -40, -20)

local remaining = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
remaining:SetPoint("TOPRIGHT", timer, "BOTTOMRIGHT", 0, -6)

-- Progress bar shown when the scene doesn't play: the destination above, the time on the bar.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local mini = CreateFrame("Frame", "TinkerwiseFlightTimer", UIParent, "BackdropTemplate")
mini:SetSize(264, 20)
mini:SetPoint("TOP", UIParent, "TOP", 0, -120)
mini:SetFrameStrata("MEDIUM")
mini:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
mini:SetBackdropColor(0, 0, 0, 0.6)
mini:SetBackdropBorderColor(0, 0, 0, 1)
mini:Hide()

local miniBar = CreateFrame("StatusBar", nil, mini)
miniBar:SetPoint("TOPLEFT", 2, -2)
miniBar:SetPoint("BOTTOMRIGHT", -2, 2)
miniBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
miniBar:SetMinMaxValues(0, 1)
miniBar:SetValue(0)

local miniTitle = mini:CreateFontString(nil, "OVERLAY", "GameFontNormal")
miniTitle:SetPoint("BOTTOM", mini, "TOP", 0, 4)
miniTitle:SetShadowOffset(1, -1)

local miniText = miniBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
miniText:SetPoint("CENTER")
miniText:SetShadowOffset(1, -1)

-- The bar takes the color of the Tinkerwise windows (gold or class color), a little darker so
-- the white time stays readable.
TW:OnTheme(function(theme)
    local c = theme and theme.accent or { 1, 0.82, 0 }
    miniBar:SetStatusBarColor(c[1] * 0.75, c[2] * 0.75, c[3] * 0.75)
    miniTitle:SetTextColor(c[1], c[2], c[3])
end)

local miniDuration -- known duration of the current route, or nil
mini:SetScript("OnUpdate", function()
    if miniDuration and startedAt then
        miniBar:SetValue(math.min((GetTime() - startedAt) / miniDuration, 1))
    end
end)

---------------------------------------------------------------------------
-- Route and display
---------------------------------------------------------------------------

local FormatDuration = ImmersionScene.FormatDuration

local function RouteKey(r)
    return r and r.from and r.to and (r.from .. " > " .. r.to)
end

local function KnownDuration()
    local key = RouteKey(route)
    return route and route.known or (key and routes[key])
end

-- "About 01:20 left", "Landing soon", or nil when the route has never been flown.
local function TimeLeftText(elapsed)
    local known = KnownDuration()
    if not known then return nil end
    if known > elapsed then return format(L["About %s left"], FormatDuration(known - elapsed)) end
    return L["Landing soon"]
end

local function Refresh()
    local elapsed = GetTime() - startedAt
    title:SetText(route and route.to or L["In flight"])
    origin:SetText(route and route.from and format(L["From %s"], route.from) or "")
    zone:SetText(format(L["Flying over %s"], GetRealZoneText() or ""))
    timer:SetText(format(L["%s elapsed"], FormatDuration(elapsed)))
    remaining:SetText(TimeLeftText(elapsed) or "")
end

local function ShowMini(show)
    if not (show and db and db.flightTimer) then
        mini:Hide()
        return
    end
    local elapsed = GetTime() - startedAt
    -- An unknown route (first flight) leaves the bar empty and counts the time flown.
    miniDuration = KnownDuration()
    if not miniDuration then miniBar:SetValue(0) end
    miniTitle:SetText(route and route.to or L["In flight"])
    miniText:SetText(TimeLeftText(elapsed) or format(L["%s elapsed"], FormatDuration(elapsed)))
    mini:Show()
end

local function Stop()
    if not scene:IsPlaying() then return end
    if testing then
        testing = false
        route = nil
    end
    scene:Stop()
end

-- The interface stays reachable during the flight, until the next one.
scene.onClose = function()
    if not testing then dismissed = true end
    Stop()
end

---------------------------------------------------------------------------
-- Flight detection
---------------------------------------------------------------------------

-- nil when the game keeps the answer secret: the current state then stays as it is.
local function IsOnTaxi()
    local onTaxi = UnitOnTaxi("player")
    if issecretvalue and issecretvalue(onTaxi) then return nil end
    return onTaxi and true or false
end

local function Land()
    local key = RouteKey(route)
    local duration = GetTime() - startedAt
    if key and duration >= MIN_RECORDED_FLIGHT then routes[key] = math.floor(duration) end
    flying, dismissed, route = false, false, nil
end

local function Update()
    if testing then
        if InCombatLockdown() then Stop() else Refresh() end
        return
    end
    local onTaxi = IsOnTaxi()
    if onTaxi == nil then return end
    if not onTaxi then
        if flying then Land() end
        Stop()
        ShowMini(false)
        return
    end
    if not flying then
        flying, startedAt, route, pendingRoute = true, GetTime(), pendingRoute, nil
    end
    local otherScene = scene:OtherPlaying()
    if db.flight and not dismissed and not InCombatLockdown() and not otherScene then
        Refresh()
        scene:Play()
    else
        Stop()
    end
    ShowMini(not scene:IsPlaying() and not otherScene)
end

-- Plays the scene with a sample route. Nothing is recorded, since no real flight is under way.
local function StartTest()
    if scene:IsPlaying() or flying or InCombatLockdown() or scene:OtherPlaying() then return end
    testing, startedAt = true, GetTime() - 35
    route = { from = GetRealZoneText(), to = L["Test destination"], known = 90 }
    Refresh()
    scene:Play()
    scene:EndTestAfter(function()
        if testing then Stop() end
    end)
end

local function ReadRoute(slot)
    local found = {}
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()) or {}) do
        if node.slotIndex == slot then found.to = node.name end
        if node.state == Enum.FlightPathState.Current then found.from = node.name end
    end
    return found
end

-- Read while the flight map is still open: nothing tells the destination once in the air.
hooksecurefunc("TakeTaxiNode", function(slot)
    if not ticker then return end
    local ok, found = pcall(ReadRoute, slot)
    pendingRoute = ok and found or nil
end)

---------------------------------------------------------------------------
-- Flight map tooltips
---------------------------------------------------------------------------

-- The hovered destination: a pin of the recent flight map, or a button of the older one.
local function HoveredSlot(owner)
    if not owner then return end
    if owner.taxiNodeData then return owner.taxiNodeData.slotIndex end
    local name = owner.GetName and owner:GetName()
    if TaxiFrame and TaxiFrame:IsShown() and name and name:match("^TaxiButton%d+$") then
        return owner:GetID()
    end
end

local function OnTooltipShow(tooltip)
    if not (ticker and db and db.flightTooltip) then return end
    local slot = HoveredSlot(tooltip:GetOwner())
    if not slot then return end
    local ok, found = pcall(ReadRoute, slot)
    local key = ok and RouteKey(found)
    if not key or found.from == found.to then return end
    local known = routes[key]
    if known then
        tooltip:AddLine(format(L["Flight time: %s"], FormatDuration(known)), 1, 1, 1)
    else
        tooltip:AddLine(L["Flight time not known yet"], 0.6, 0.6, 0.6)
    end
    tooltip:Show()
end

local tooltipHooked = false
local function HookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    GameTooltip:HookScript("OnShow", OnTooltipShow)
end

---------------------------------------------------------------------------
-- Interface for the module holding the options (AwayModes)
---------------------------------------------------------------------------

ns.FlightMode = {}

function ns.FlightMode.Enable(settings)
    db = settings
    -- Durations used to be saved per character: each character brings its own into the account's
    -- list as it logs in (the longer one when two disagree: a flight cut short reads too short).
    TinkerwiseDB.flightRoutes = TinkerwiseDB.flightRoutes or {}
    routes = TinkerwiseDB.flightRoutes
    for key, seconds in pairs(settings.routes or {}) do
        if not routes[key] or seconds > routes[key] then routes[key] = seconds end
    end
    settings.routes = nil
    HookTooltip()
    ticker = C_Timer.NewTicker(CHECK_EVERY, Update)
    Update()
end

function ns.FlightMode.Disable()
    if ticker then ticker:Cancel() end
    ticker = nil
    flying, dismissed, route, pendingRoute = false, false, nil, nil
    Stop()
    mini:Hide()
end

function ns.FlightMode.Test(settings)
    db = settings
    StartTest()
end
