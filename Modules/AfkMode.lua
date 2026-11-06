-- AfkMode: while the player is flagged AFK, the interface fades away, the camera turns slowly and
-- black bands show the character, the time away and the whispers received in the meantime.
--
-- The interface is made transparent rather than hidden, like in the quest scene. Coming back
-- (moving, or sending a message) is detected by the game, which removes the AFK flag.

local _, ns = ...
local L = ns.L
local ImmersionScene = ns.ImmersionScene

local REFRESH_EVERY = 0.5

local db
local dismissed, testing = false, false
local afkSince, whispers = nil, 0
local sinceRefresh = 0

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local scene = ImmersionScene.Create({ name = "TinkerwiseAfkScene", bandHeight = 150, closable = true })
local topBand, bottomBand = scene.topBand, scene.bottomBand

local title = scene:CreateTitle(topBand, 38)
title:SetPoint("CENTER", topBand, "CENTER", 0, 0)
title:SetText(L["Away"])

local name = scene:CreateTitle(bottomBand, 26)
name:SetPoint("TOPLEFT", bottomBand, "TOPLEFT", 40, -24)

local details = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
details:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)

local zone = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
zone:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -6)

local timer = scene:CreateTitle(bottomBand, 26)
timer:SetPoint("TOPRIGHT", bottomBand, "TOPRIGHT", -40, -24)

local clock = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
clock:SetPoint("TOPRIGHT", timer, "BOTTOMRIGHT", 0, -6)

local whisperText = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
whisperText:SetPoint("TOPRIGHT", clock, "BOTTOMRIGHT", 0, -6)

local FACTION_LOGOS = {
    Alliance = "Interface\\Timer\\Alliance-Logo",
    Horde = "Interface\\Timer\\Horde-Logo",
}
local factionLogo = bottomBand:CreateTexture(nil, "ARTWORK")
factionLogo:SetSize(110, 110)
factionLogo:SetPoint("CENTER", bottomBand, "CENTER", 0, 10)

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function RefreshTime()
    timer:SetText(format(L["Away for %s"], ImmersionScene.FormatDuration(GetTime() - (afkSince or GetTime()))))
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

scene.onUpdate = function(elapsed)
    sinceRefresh = sinceRefresh + elapsed
    if sinceRefresh >= REFRESH_EVERY then
        sinceRefresh = 0
        RefreshTime()
    end
end

---------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------

local function StartCamera()
    if db.camera then ImmersionScene.StartCamera() end
end

local function Play()
    if scene:IsPlaying() then return end
    sinceRefresh = 0
    RefreshCharacter()
    RefreshTime()
    scene:Play()
    StartCamera()
end

local function Stop()
    if not scene:IsPlaying() then return end
    if testing then
        testing = false
        afkSince, whispers = nil, 0
    end
    scene:Stop()
    ImmersionScene.RestoreCamera()
end

-- The interface stays reachable while away, until the next time the player leaves.
scene.onClose = function()
    if not testing then dismissed = true end
    Stop()
end

-- Plays the scene with sample values, without touching the AFK flag.
local function StartTest()
    if scene:IsPlaying() or InCombatLockdown() or scene:OtherPlaying() then return end
    testing, afkSince, whispers = true, GetTime() - 125, 2
    Play()
    scene:EndTestAfter(function()
        if testing then Stop() end
    end)
end

local function Update()
    if testing then return end
    if not UnitIsAFK("player") then
        afkSince, whispers, dismissed = nil, 0, false
        Stop()
        return
    end
    afkSince = afkSince or GetTime()
    if dismissed or InCombatLockdown() or scene:OtherPlaying() then return end
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
            if scene:IsPlaying() then RefreshTime() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        Stop()
    else
        Update()
    end
end)

---------------------------------------------------------------------------
-- Interface for the module holding the options (AwayModes)
---------------------------------------------------------------------------

ns.AfkMode = {}

function ns.AfkMode.Enable(settings)
    db = settings
    events:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }) do
        events:RegisterEvent(e)
    end
    Update()
end

function ns.AfkMode.Disable()
    events:UnregisterAllEvents()
    afkSince, whispers, dismissed = nil, 0, false
    Stop()
end

function ns.AfkMode.Test(settings)
    db = settings
    StartTest()
end

function ns.AfkMode.OnCameraChanged()
    if not scene:IsPlaying() then return end
    if db.camera then StartCamera() else ImmersionScene.RestoreCamera() end
end
