-- Moments: black bands with a few words when you die or gain a level, then a fade back. The bands go
-- under the interface, which stays usable: both happen in combat, and the release button must show.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local ImmersionScene = ns.ImmersionScene

local FADE = 0.8
local DEATH_SECONDS, LEVEL_SECONDS = 8, 6

local db
local left -- seconds before the end of the scene

local scene = ImmersionScene.Create({
    name = "TinkerwiseMomentScene", bandHeight = 130, fadeTime = FADE, clickThrough = true, overlay = true,
})
scene.topBand:EnableMouse(false)
scene.bottomBand:EnableMouse(false)

local title = scene:CreateTitle(scene.topBand, 40)
title:SetPoint("CENTER", scene.topBand, "CENTER", 0, 14)
local line = scene.topBand:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
line:SetPoint("TOP", title, "BOTTOM", 0, -8)
line:SetTextColor(0.9, 0.84, 0.72)

scene.onUpdate = function(elapsed)
    if not left then return end
    left = left - elapsed
    if left <= 0 then
        left = nil
        scene:Stop()
    elseif left < FADE then
        scene.frame:SetAlpha(left / FADE)
    end
end

local function Play(heading, r, g, b, text, seconds)
    if ImmersionScene.AnyPlaying() then return end -- a quest, AFK or flight scene
    title:SetText(heading)
    title:SetTextColor(r, g, b)
    line:SetText(text)
    left = seconds
    if scene:IsPlaying() then
        scene.frame:SetAlpha(1) -- it may have been fading out
    else
        scene:Play()
    end
end

local function Duration(seconds)
    local hours = math.floor(seconds / 3600)
    if hours >= 24 then return format(L["%d d %d h"], math.floor(hours / 24), hours % 24) end
    if hours > 0 then return format(L["%d h %d min"], hours, math.floor(seconds / 60) % 60) end
    return format(L["%d min"], math.max(1, math.floor(seconds / 60)))
end

local function Join(parts)
    return table.concat(parts, "  \194\183  ")
end

local function PlayDeath()
    local parts = { ns.Spells.Plain(GetRealZoneText()) or "", format(L["level %d"], UnitLevel("player")) }
    local deaths = ns.Journal and ns.Journal.Deaths()
    if deaths and deaths > 0 then parts[#parts + 1] = format(L["death no. %d"], deaths) end
    Play(L["You died"], 0.85, 0.2, 0.15, Join(parts), DEATH_SECONDS)
end

local function PlayLevel(level)
    local parts = { ns.Spells.Plain(GetRealZoneText()) or "" }
    local before = ns.Journal and ns.Journal.LevelTime(level - 1)
    if before then parts[#parts + 1] = format(L["%s after level %d"], Duration(time() - before), level - 1) end
    Play(format(L["Level %d"], level), 1, 0.9, 0.7, Join(parts), LEVEL_SECONDS)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, level)
    if event == "PLAYER_DEAD" then
        -- A moment later: the journal has counted the death.
        if db.death then C_Timer.After(0.5, function() if db then PlayDeath() end end) end
    elseif event == "PLAYER_LEVEL_UP" then
        if db.level then PlayLevel(level) end
    else -- leaving the world, or alive again
        left = nil
        scene:Stop()
    end
end)

local mod = TW:NewModule("Moments", {
    title = L["Death and Level Scenes"],
    icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
    section = L["Ambiance"],
    desc = L["Black bands at the top and bottom of the screen with a few words when you die or gain a level, then a fade back. They go under the interface, which stays usable. The Travel Journal gives them the number of deaths and the time since the previous level."],
    defaults = { death = true, level = true },
    options = {
        { type = "toggle", key = "death", label = L["When I die"] },
        { type = "toggle", key = "level", label = L["When I gain a level"] },
        { type = "execute", label = L["Test the death"], func = PlayDeath },
        { type = "execute", label = L["Test the level"], func = function() PlayLevel(UnitLevel("player")) end },
    },
})

function mod:OnEnable()
    db = self.db
    for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_LEVEL_UP", "PLAYER_LEAVING_WORLD" }) do events:RegisterEvent(e) end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    db, left = nil, nil
    scene:Stop()
end
