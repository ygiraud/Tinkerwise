-- ImmersionScene: what the full-screen scenes share (quest, AFK, flight, fishing). A frame with two
-- black bands, a fade that makes the interface transparent, the minimap hidden meanwhile and,
-- when closable, a cross and the Escape key. Also the slowly turning camera.
--
-- ns.ImmersionScene.Create(options) returns a scene:
--   options: name, bandHeight, fadeTime, closable, clickThrough (only the bands take the mouse),
--            overlay (bands drawn during the immersion mode: the interface is left to that mode)
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
        SetOverrideBindingClick(self.closeButton, true, "ESCAPE", self.closeButton:GetName())
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
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    for _, scene in ipairs(scenes) do
        if scene.closeButton then ClearOverrideBindings(scene.closeButton) end
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
