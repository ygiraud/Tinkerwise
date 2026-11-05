-- FlightMode: during a flight master trip, the interface fades away and black bands show the route,
-- the zone below and the time. The camera is left alone. Each route's duration is remembered, which
-- gives an estimate of the time left from the second flight on.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local issecretvalue = _G.issecretvalue

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BAND_H = 110
local FADE_TIME = 0.6
local CHECK_EVERY = 0.5
local MIN_RECORDED_FLIGHT = 5 -- seconds; shorter means the flight did not really happen
local TEST_DURATION = 15

local db, ticker
local playing, flying, dismissed, testing = false, false, false, false
local fadeIn, testId = 0, 0
local startedAt, route, pendingRoute

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- No parent: the scene must stay visible while the interface is transparent.
local scene = CreateFrame("Frame", "TinkerwiseFlightScene")
scene:SetFrameStrata("FULLSCREEN_DIALOG")
scene:EnableMouse(true) -- the invisible interface must take no clicks
scene:Hide()

local function Band(point)
    local band = scene:CreateTexture(nil, "BACKGROUND")
    band:SetColorTexture(0, 0, 0, 0.92)
    band:SetPoint(point .. "LEFT")
    band:SetPoint(point .. "RIGHT")
    band:SetHeight(BAND_H)
    return band
end
local topBand = Band("TOP")
local bottomBand = Band("BOTTOM")

local function Rule(point, relativePoint, band)
    local rule = scene:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetColorTexture(1, 0.82, 0, 0.6)
    rule:SetPoint(point .. "LEFT", band, relativePoint .. "LEFT")
    rule:SetPoint(point .. "RIGHT", band, relativePoint .. "RIGHT")
end
Rule("TOP", "BOTTOM", topBand)
Rule("BOTTOM", "TOP", bottomBand)

local title = scene:CreateFontString(nil, "OVERLAY")
title:SetFont(TITLE_FONT, 34, "")
title:SetTextColor(1, 0.9, 0.7)
title:SetPoint("CENTER", topBand, "CENTER", 0, 0)

local origin = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
origin:SetPoint("TOPLEFT", bottomBand, "TOPLEFT", 40, -24)

local zone = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
zone:SetPoint("TOPLEFT", origin, "BOTTOMLEFT", 0, -6)

local timer = scene:CreateFontString(nil, "OVERLAY")
timer:SetFont(TITLE_FONT, 24, "")
timer:SetTextColor(1, 0.9, 0.7)
timer:SetPoint("TOPRIGHT", bottomBand, "TOPRIGHT", -40, -20)

local remaining = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
remaining:SetPoint("TOPRIGHT", timer, "BOTTOMRIGHT", 0, -6)

local hint = scene:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOM", bottomBand, "BOTTOM", 0, 12)
hint:SetText(L["Click: show the interface"])

---------------------------------------------------------------------------
-- Route and display
---------------------------------------------------------------------------

local function FormatDuration(seconds)
    seconds = math.floor(seconds)
    return format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function RouteKey()
    return route and route.from and route.to and (route.from .. " > " .. route.to)
end

local function Refresh()
    local elapsed = GetTime() - startedAt
    title:SetText(route and route.to or L["In flight"])
    origin:SetText(route and route.from and format(L["From %s"], route.from) or "")
    zone:SetText(format(L["Flying over %s"], GetRealZoneText() or ""))
    timer:SetText(format(L["%s elapsed"], FormatDuration(elapsed)))

    local key = RouteKey()
    local known = route and route.known or (key and db.routes[key])
    if not known then
        remaining:SetText("")
    elseif known > elapsed then
        remaining:SetText(format(L["About %s left"], FormatDuration(known - elapsed)))
    else
        remaining:SetText(L["Landing soon"])
    end
end

scene:SetScript("OnUpdate", function(_, elapsed)
    if fadeIn < 1 then
        fadeIn = math.min(fadeIn + elapsed / FADE_TIME, 1)
        scene:SetAlpha(fadeIn)
        UIParent:SetAlpha(1 - fadeIn)
    end
end)

local function Play()
    if playing then return end
    if ns.FinishImmersionFade then ns.FinishImmersionFade() end
    playing, fadeIn = true, 0
    scene:ClearAllPoints()
    scene:SetAllPoints(WorldFrame)
    scene:SetScale(UIParent:GetEffectiveScale())
    scene:SetAlpha(0)
    scene:Show()
end

local function Stop()
    if not playing then return end
    playing = false
    if testing then
        testing = false
        route = nil
    end
    scene:Hide()
    UIParent:SetAlpha(1)
end

-- The interface stays reachable during the flight, until the next one.
scene:SetScript("OnMouseDown", function()
    if not testing then dismissed = true end
    Stop()
end)

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
    local key = RouteKey()
    local duration = GetTime() - startedAt
    if key and duration >= MIN_RECORDED_FLIGHT then db.routes[key] = math.floor(duration) end
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
        return
    end
    if not flying then
        flying, startedAt, route, pendingRoute = true, GetTime(), pendingRoute, nil
    end
    if dismissed or InCombatLockdown() or (ns.QuestScene and ns.QuestScene.IsPlaying()) then
        Stop()
        return
    end
    Refresh()
    Play()
end

-- Plays the scene with a sample route. Nothing is recorded, since no real flight is under way.
local function StartTest()
    if playing or flying or InCombatLockdown() or (ns.QuestScene and ns.QuestScene.IsPlaying()) then return end
    testing, startedAt = true, GetTime() - 35
    route = { from = GetRealZoneText(), to = L["Test destination"], known = 90 }
    Refresh()
    Play()
    testId = testId + 1
    local id = testId
    C_Timer.After(TEST_DURATION, function()
        if testing and id == testId then Stop() end
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
-- Module
---------------------------------------------------------------------------

ns.FlightMode = {}

function ns.FlightMode.IsPlaying()
    return playing
end

local mod = TW:NewModule("FlightMode", {
    title = L["Flight Mode"],
    icon = "Interface\\Icons\\Ability_Mount_Wyvern_01",
    section = "Immersion",
    desc = L["During a flight master trip, the interface fades away and the screen shows the destination, the zone below and the flight time. The time left appears once you have flown that route. The camera doesn't move. Click the screen to get the interface back. Out of combat only."],
    defaults = { routes = {} },
    options = {
        { type = "execute", label = L["Test (15 s)"], func = StartTest },
    },
})

function mod:OnEnable()
    db = self.db
    ticker = C_Timer.NewTicker(CHECK_EVERY, Update)
    Update()
end

function mod:OnDisable()
    if ticker then ticker:Cancel() end
    ticker = nil
    flying, dismissed, route, pendingRoute = false, false, nil, nil
    Stop()
end
