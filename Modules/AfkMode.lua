-- AfkMode: while the player is flagged AFK, the interface fades away, the camera turns slowly and
-- black bands show the character, the time away and the whispers received in the meantime.
--
-- The interface is made transparent rather than hidden, like in the quest scene. Coming back
-- (moving, or sending a message) is detected by the game, which removes the AFK flag.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BAND_H = 150
local SAVED_VIEW = 5 -- camera view slot, also used by the quest scene (never at the same time)
local CAMERA_SPEED = 0.03
local FADE_TIME = 0.6
local REFRESH_EVERY = 0.5

local db
local playing, cameraMoved, dismissed = false, false, false
local afkSince, whispers = nil, 0
local fadeIn, sinceRefresh = 0, 0

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- No parent: the scene must stay visible while the interface is transparent.
local scene = CreateFrame("Frame", "TinkerwiseAfkScene")
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
title:SetFont(TITLE_FONT, 38, "")
title:SetTextColor(1, 0.9, 0.7)
title:SetPoint("CENTER", topBand, "CENTER", 0, 0)
title:SetText(L["Away"])

local name = scene:CreateFontString(nil, "OVERLAY")
name:SetFont(TITLE_FONT, 26, "")
name:SetPoint("TOPLEFT", bottomBand, "TOPLEFT", 40, -24)

local details = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
details:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)

local zone = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
zone:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -6)

local timer = scene:CreateFontString(nil, "OVERLAY")
timer:SetFont(TITLE_FONT, 26, "")
timer:SetTextColor(1, 0.9, 0.7)
timer:SetPoint("TOPRIGHT", bottomBand, "TOPRIGHT", -40, -24)

local clock = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
clock:SetPoint("TOPRIGHT", timer, "BOTTOMRIGHT", 0, -6)

local whisperText = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
whisperText:SetPoint("TOPRIGHT", clock, "BOTTOMRIGHT", 0, -6)

local FACTION_LOGOS = {
    Alliance = "Interface\\Timer\\Alliance-Logo",
    Horde = "Interface\\Timer\\Horde-Logo",
}
local factionLogo = scene:CreateTexture(nil, "ARTWORK")
factionLogo:SetSize(110, 110)
factionLogo:SetPoint("CENTER", bottomBand, "CENTER", 0, 10)

local hint = scene:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOM", bottomBand, "BOTTOM", 0, 12)
hint:SetText(L["Click: show the interface"])

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function FormatDuration(seconds)
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / 3600)
    if hours > 0 then return format("%d:%02d:%02d", hours, math.floor(seconds / 60) % 60, seconds % 60) end
    return format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function RefreshTime()
    timer:SetText(format(L["Away for %s"], FormatDuration(GetTime() - (afkSince or GetTime()))))
    clock:SetText(date("%H:%M"))
    whisperText:SetText(whispers > 0 and format(L["%d whisper(s) received"], whispers) or "")
end

local function RefreshCharacter()
    local className, classFile = UnitClass("player")
    local color = RAID_CLASS_COLORS[classFile]
    name:SetText(UnitName("player"))
    if color then name:SetTextColor(color.r, color.g, color.b) end
    details:SetText(format(L["Level %d %s"], UnitLevel("player"), className))
    zone:SetText(GetRealZoneText() or "")
    local logo = FACTION_LOGOS[UnitFactionGroup("player")]
    factionLogo:SetTexture(logo)
    factionLogo:SetShown(logo ~= nil)
end

scene:SetScript("OnUpdate", function(_, elapsed)
    if fadeIn < 1 then
        fadeIn = math.min(fadeIn + elapsed / FADE_TIME, 1)
        scene:SetAlpha(fadeIn)
        UIParent:SetAlpha(1 - fadeIn)
    end
    sinceRefresh = sinceRefresh + elapsed
    if sinceRefresh >= REFRESH_EVERY then
        sinceRefresh = 0
        RefreshTime()
    end
end)

---------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------

local function StartCamera()
    if not db.camera or cameraMoved then return end
    cameraMoved = true
    SaveView(SAVED_VIEW)
    MoveViewLeftStart(CAMERA_SPEED)
end

local function RestoreCamera()
    if not cameraMoved then return end
    cameraMoved = false
    MoveViewLeftStop()
    SetView(SAVED_VIEW)
end

local function Play()
    if playing then return end
    if ns.FinishImmersionFade then ns.FinishImmersionFade() end
    playing, fadeIn, sinceRefresh = true, 0, 0
    scene:ClearAllPoints()
    scene:SetAllPoints(WorldFrame)
    scene:SetScale(UIParent:GetEffectiveScale())
    scene:SetAlpha(0)
    RefreshCharacter()
    RefreshTime()
    scene:Show()
    StartCamera()
end

local function Stop()
    if not playing then return end
    playing = false
    scene:Hide()
    UIParent:SetAlpha(1)
    RestoreCamera()
end

-- The interface stays reachable while away, until the next time the player leaves.
scene:SetScript("OnMouseDown", function()
    dismissed = true
    Stop()
end)

local function Update()
    if not UnitIsAFK("player") then
        afkSince, whispers, dismissed = nil, 0, false
        Stop()
        return
    end
    afkSince = afkSince or GetTime()
    if dismissed or InCombatLockdown() or (ns.QuestScene and ns.QuestScene.IsPlaying()) then return end
    Play()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        if afkSince then
            whispers = whispers + 1
            if playing then RefreshTime() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        Stop()
    else
        Update()
    end
end)

local mod = TW:NewModule("AfkMode", {
    title = L["AFK Mode"],
    icon = "Interface\\Icons\\Spell_Nature_Sleep",
    section = "Immersion",
    desc = L["When you go AFK (/afk or after a while), the interface fades away and the camera turns slowly around your character. The screen shows the time away and the whispers received. Move or send a message to come back, or click the screen to get the interface back while staying AFK. Out of combat only. The camera uses the game's view slot 5."],
    defaults = { camera = true },
    options = {
        { type = "toggle", key = "camera", label = L["Camera movement"] },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }) do
        events:RegisterEvent(e)
    end
    Update()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    afkSince, whispers, dismissed = nil, 0, false
    Stop()
end

function mod:OnOptionChanged(key)
    if key ~= "camera" or not playing then return end
    if db.camera then StartCamera() else RestoreCamera() end
end
