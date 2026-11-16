-- ImmersionScene: what the full-screen scenes share (quest, AFK, flight). A frame with two
-- black bands, a fade that makes the interface transparent, the minimap hidden meanwhile and,
-- when closable, a cross and the Escape key. Also the slowly turning camera.
--
-- ns.ImmersionScene.Create(options) returns a scene:
--   options: name, bandHeight, fadeTime, closable, clickThrough (only the bands take the mouse),
--            overlay (bands drawn during the immersion mode: the interface is left to that mode),
--            windows (the bags and the world map open above the scene with their usual keys)
--   scene.frame, scene.topBand, scene.bottomBand, scene.topRule, scene.closeButton
--   scene.onClose(), scene.onUpdate(elapsed), scene.onFade(progress)   set by the module
--
-- Anything shown in a scene goes on its bands: they cover the scene's own frame.

local _, ns = ...

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local DEFAULT_FADE_TIME = 0.6
local TEST_DURATION = 15
local SAVED_VIEW = 5 -- camera view slot
local CAMERA_SPEED = 0.03

local M = { TEST_DURATION = TEST_DURATION }
ns.ImmersionScene = M

local scenes = {}

local Scene = {}
Scene.__index = Scene

---------------------------------------------------------------------------
-- Windows opened during a scene
---------------------------------------------------------------------------

-- The interface stays shown during a scene, only transparent: the bag and map keys keep working, but
-- their windows would open invisible and under the scene. While shown, each one is lifted above the
-- scene with the tooltips, and put back when it closes or the scene ends.
local WINDOWS = { "ContainerFrameCombinedBags", "WorldMapFrame" }
for i = 1, NUM_CONTAINER_FRAMES or 13 do
    tinsert(WINDOWS, "ContainerFrame" .. i)
end
local TOOLTIPS = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
local LIFT_STRATA = "FULLSCREEN_DIALOG" -- the scene's
local LIFT_LEVEL = 500 -- above its bands, with room below for children drawn under their window

-- Stands in for the interface: same rectangle and scale, without its transparency.
local windowHolder = CreateFrame("Frame")
windowHolder:SetAllPoints(UIParent)

local windowScene -- the playing scene that takes windows
local lifted = {} -- frame -> { parent, strata, level, descendants }
local hookedWindows = {}

-- Each descendant with its strata and level. A child in its window's strata follows it.
local function Collect(frame, strata, list)
    for _, child in ipairs({ frame:GetChildren() }) do
        local childStrata = child:GetFrameStrata()
        list[#list + 1] = { frame = child, strata = childStrata, level = child:GetFrameLevel(), follows = childStrata == strata }
        Collect(child, strata, list) -- after its parent, so a level set on the parent can't undo its own
    end
end

-- With a strata, above the scene; without, as saved. The order inside stays, a bag's background
-- below its items: only the strata and the base level change.
local function Place(f, saved, strata)
    f:SetFrameStrata(strata or saved.strata)
    f:SetFrameLevel(strata and LIFT_LEVEL or saved.level)
    for _, d in ipairs(saved.descendants) do
        if strata and d.follows then
            d.frame:SetFrameStrata(strata)
            d.frame:SetFrameLevel(math.max(LIFT_LEVEL + d.level - saved.level, 0))
        else
            d.frame:SetFrameStrata(d.follows and saved.strata or d.strata)
            d.frame:SetFrameLevel(d.level)
        end
    end
end

-- Without a strata, the frame keeps its own: the tooltips are already above everything.
local function Lift(f, strata)
    if lifted[f] or InCombatLockdown() then return end
    local saved = { parent = f:GetParent(), strata = f:GetFrameStrata(), level = f:GetFrameLevel(), descendants = {} }
    Collect(f, saved.strata, saved.descendants)
    lifted[f] = saved
    windowHolder:SetScale(UIParent:GetEffectiveScale())
    f:SetParent(windowHolder)
    Place(f, saved, strata)
end

local function Drop(f)
    local saved = lifted[f]
    if not saved or InCombatLockdown() then return end
    lifted[f] = nil
    f:SetParent(saved.parent)
    Place(f, saved)
end

local function AnyWindowLifted()
    for _, name in ipairs(WINDOWS) do
        if _G[name] and lifted[_G[name]] then return true end
    end
    return false
end

local function LiftTooltips()
    for _, name in ipairs(TOOLTIPS) do
        if _G[name] then Lift(_G[name]) end
    end
end

local function DropTooltips()
    for _, name in ipairs(TOOLTIPS) do
        if _G[name] then Drop(_G[name]) end
    end
end

local function LiftWindow(f)
    if not windowScene or not f:IsShown() then return end
    Lift(f, LIFT_STRATA)
    LiftTooltips()
end

local function DropWindow(f)
    Drop(f)
    if not AnyWindowLifted() then DropTooltips() end
end

local function HookWindows()
    for _, name in ipairs(WINDOWS) do
        local f = _G[name]
        if f and not hookedWindows[f] then
            hookedWindows[f] = true
            f:HookScript("OnShow", LiftWindow)
            f:HookScript("OnHide", DropWindow)
        end
    end
    -- The map sets its own strata when it is maximized or minimized, which would put it under the scene.
    local map = _G.WorldMapFrame
    if map and map.SynchronizeDisplayState and not hookedWindows.mapDisplay then
        hookedWindows.mapDisplay = true
        hooksecurefunc(map, "SynchronizeDisplayState", function(self)
            local saved = lifted[self]
            if not saved or InCombatLockdown() then return end
            saved.strata = self:GetFrameStrata() -- the one to go back to
            Place(self, saved, LIFT_STRATA)
        end)
    end
end

local function LiftShownWindows()
    HookWindows()
    for _, name in ipairs(WINDOWS) do
        if _G[name] then LiftWindow(_G[name]) end
    end
end

local function DropAllWindows()
    for f in pairs(lifted) do Drop(f) end
end

-- Escape closes the windows first, then the scene.
local function CloseWindows()
    local closed = false
    if IsAnyBagOpen and IsAnyBagOpen() then
        CloseAllBags()
        closed = true
    end
    local map = _G.WorldMapFrame
    if map and map:IsShown() then
        HideUIPanel(map)
        closed = true
    end
    return closed
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------

function Scene:IsPlaying()
    return self.playing
end

function Scene:OtherPlaying()
    for _, other in ipairs(scenes) do
        if other ~= self and other.playing and not other.overlay then return true end
    end
    return false
end

function Scene:Play()
    if self.playing then return end
    if ns.FinishImmersionFade and not self.overlay then ns.FinishImmersionFade() end
    self.playing, self.fadeIn = true, 0
    local frame = self.frame
    frame:ClearAllPoints()
    frame:SetAllPoints(WorldFrame)
    frame:SetScale(UIParent:GetEffectiveScale())
    frame:SetAlpha(0)
    frame:Show()
    if self.closeButton and not InCombatLockdown() then
        SetOverrideBindingClick(self.closeButton, true, "ESCAPE", self.escapeButton:GetName())
    end
    if self.windows then
        windowScene = self
        LiftShownWindows()
    end
end

function Scene:Stop()
    if not self.playing then return end
    self.playing = false
    self.frame:Hide()
    if self.minimapHidden then
        self.minimapHidden = false
        Minimap:Show()
    end
    if not self.overlay then UIParent:SetAlpha(1) end
    if self.closeButton and not InCombatLockdown() then ClearOverrideBindings(self.closeButton) end
    if windowScene == self then
        windowScene = nil
        DropAllWindows()
    end
end

-- Calls stop at the end of a test, unless another test started meanwhile.
function Scene:EndTestAfter(stop)
    self.testToken = (self.testToken or 0) + 1
    local token = self.testToken
    C_Timer.After(TEST_DURATION, function()
        if token == self.testToken then stop() end
    end)
end

function Scene:SetBandOpacity(opacity)
    self.topBand.background:SetColorTexture(0, 0, 0, opacity)
    self.bottomBand.background:SetColorTexture(0, 0, 0, opacity)
end

function Scene:CreateTitle(band, size)
    local title = band:CreateFontString(nil, "OVERLAY")
    title:SetFont(TITLE_FONT, size, "")
    title:SetTextColor(1, 0.9, 0.7)
    return title
end

local function OnUpdate(scene, elapsed)
    if scene.fadeIn < 1 then
        scene.fadeIn = math.min(scene.fadeIn + elapsed / scene.fadeTime, 1)
        scene.frame:SetAlpha(scene.fadeIn)
        if not scene.overlay then UIParent:SetAlpha(1 - scene.fadeIn) end
        if scene.onFade then scene.onFade(scene.fadeIn) end
        -- The minimap's arrow ignores the interface's transparency: it has to be hidden for real.
        if scene.fadeIn >= 1 and not scene.overlay and Minimap:IsShown() then
            scene.minimapHidden = true
            Minimap:Hide()
        end
    end
    if scene.onUpdate then scene.onUpdate(elapsed) end
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function Band(frame, point, height, takesMouse)
    local band = CreateFrame("Frame", nil, frame)
    band:SetPoint(point .. "LEFT")
    band:SetPoint(point .. "RIGHT")
    band:SetHeight(height)
    band:EnableMouse(takesMouse and true or false)
    band.background = band:CreateTexture(nil, "BACKGROUND")
    band.background:SetAllPoints()
    band.background:SetColorTexture(0, 0, 0, 0.92)
    return band
end

local function Rule(band, point, relativePoint)
    local rule = band:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetColorTexture(1, 0.82, 0, 0.6)
    rule:SetPoint(point .. "LEFT", band, relativePoint .. "LEFT")
    rule:SetPoint(point .. "RIGHT", band, relativePoint .. "RIGHT")
    return rule
end

function M.Create(options)
    -- No parent: the scene must stay visible while the interface is transparent.
    local frame = CreateFrame("Frame", options.name)
    if options.overlay then
        -- Over the immersion mode's black bars, under the elements it keeps on screen.
        frame:SetFrameStrata("BACKGROUND")
        frame:SetFrameLevel(20)
    else
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    frame:EnableMouse(not options.clickThrough) -- the invisible interface must take no clicks
    frame:Hide()

    local scene = setmetatable({
        frame = frame,
        overlay = options.overlay,
        windows = options.windows,
        fadeTime = options.fadeTime or DEFAULT_FADE_TIME,
        playing = false,
        fadeIn = 0,
    }, Scene)
    scene.topBand = Band(frame, "TOP", options.bandHeight, options.clickThrough)
    scene.bottomBand = Band(frame, "BOTTOM", options.bandHeight, options.clickThrough)
    scene.topRule = Rule(scene.topBand, "TOP", "BOTTOM")
    Rule(scene.bottomBand, "BOTTOM", "TOP")

    if options.closable then
        local close = CreateFrame("Button", options.name .. "Close", scene.topBand, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", scene.topBand, "TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() scene.onClose() end)
        scene.closeButton = close
        local escape = CreateFrame("Button", options.name .. "Escape")
        escape:SetScript("OnClick", function()
            if not (scene.windows and CloseWindows()) then scene.onClose() end
        end)
        scene.escapeButton = escape
    end

    frame:SetScript("OnUpdate", function(_, elapsed) OnUpdate(scene, elapsed) end)
    scenes[#scenes + 1] = scene
    return scene
end

function M.AnyPlaying()
    for _, scene in ipairs(scenes) do
        if scene.playing and not scene.overlay then return true end
    end
    return false
end

-- Escape must work normally in combat, and bindings can't change once it has started.
-- The windows go back too, while frames can still change: the scenes end in combat.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED") -- the world map may load after this addon
events:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then
        if windowScene then LiftShownWindows() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not windowScene then DropAllWindows() end -- missed when combat started
    else
        windowScene = nil
        DropAllWindows()
        for _, scene in ipairs(scenes) do
            if scene.closeButton then ClearOverrideBindings(scene.closeButton) end
        end
    end
end)

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

function M.FormatDuration(seconds)
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / 3600)
    if hours > 0 then return format("%d:%02d:%02d", hours, math.floor(seconds / 60) % 60, seconds % 60) end
    return format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local cameraMoved = false

function M.StartCamera(zoom)
    if cameraMoved then return end
    cameraMoved = true
    SaveView(SAVED_VIEW)
    if zoom then CameraZoomIn(zoom) end
    MoveViewLeftStart(CAMERA_SPEED)
end

function M.RestoreCamera()
    if not cameraMoved then return end
    cameraMoved = false
    MoveViewLeftStop()
    SetView(SAVED_VIEW)
end
