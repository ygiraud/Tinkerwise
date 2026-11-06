-- FishingDisplay: part of the immersion mode. With Fishing Buddy installed and a fishing pole equipped,
-- black bands show the fishing skill and its statistics: the zone's catches and those of the session.
-- The middle of the screen takes no clicks, so the bobber stays clickable.
--
-- Equipping the pole can start the immersion mode, and unequipping it then ends the mode. Started with
-- its key, the mode outlives the pole and only loses these bands.

local _, ns = ...
local L = ns.L

local issecretvalue = _G.issecretvalue

local CHECK_EVERY = 0.5
local BAND_HEIGHT = 110
local LINES_PER_COLUMN = 4
local COLUMN_GAP = 24
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Fish_02"
local MODE_ICON = "Interface\\Icons\\INV_Fishingpole_02"
local MODE_ICON_SIZE = 64
local MODE_RING_SIZE = 74
local SKILL_BAR_W, SKILL_BAR_H = 280, 16
local MAX_SKILL = 300 -- Artisan, the highest rank in WoW Forever
local FISHING_SPELLS = { [7620] = true, [131474] = true, [131490] = true }
local MAIN_HAND_SLOT = 16
local WEAPON_CLASS, FISHING_POLE_SUBCLASS = 2, 20
local ROUND_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local db, ticker, baseline, castStart, castEnd
local testing, testEntered, hadPole, autoStarted = false, false, false, false

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- Only the bands take the mouse: unlike the other scenes, the player has to click in the world.
local scene = ns.ImmersionScene.Create({
    name = "TinkerwiseFishingScene", bandHeight = BAND_HEIGHT, closable = true, clickThrough = true, overlay = true,
})
local topBand, bottomBand = scene.topBand, scene.bottomBand

local title = scene:CreateTitle(topBand, 34)
title:SetPoint("CENTER", 0, 14)

-- Fishing skill: a bar that fills up, its value written on it.
local skillBar = CreateFrame("StatusBar", nil, topBand)
skillBar:SetSize(SKILL_BAR_W, SKILL_BAR_H)
skillBar:SetPoint("TOP", title, "BOTTOM", 0, -8)
skillBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

local skillBorder = skillBar:CreateTexture(nil, "BACKGROUND", nil, -1)
skillBorder:SetPoint("TOPLEFT", -1, 1)
skillBorder:SetPoint("BOTTOMRIGHT", 1, -1)
skillBorder:SetColorTexture(1, 0.82, 0, 0.6)

local skillBackground = skillBar:CreateTexture(nil, "BACKGROUND")
skillBackground:SetAllPoints()
skillBackground:SetColorTexture(0.1, 0.08, 0.04)

local skillText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
skillText:SetPoint("CENTER")

-- The mode's icon, at the left of the band. Its ring is a disc behind it, white when not fishing: during
-- a cast, a colored disc empties over a dark one like a cast bar, going from green to red.
local modeRing = topBand:CreateTexture(nil, "ARTWORK")
modeRing:SetSize(MODE_RING_SIZE, MODE_RING_SIZE)
modeRing:SetPoint("LEFT", topBand, "LEFT", 33, 0)
modeRing:SetTexture(ROUND_TEXTURE)
modeRing:SetVertexColor(1, 1, 1)

local swipe = CreateFrame("Cooldown", nil, topBand, "CooldownFrameTemplate")
swipe:SetAllPoints(modeRing)
swipe:SetHideCountdownNumbers(true)
swipe:SetDrawBling(false)
swipe:SetDrawEdge(false)
swipe:SetSwipeTexture(ROUND_TEXTURE)
swipe:SetSwipeColor(1, 0.82, 0.2, 1)

local iconFrame = CreateFrame("Frame", nil, topBand)
iconFrame:SetSize(MODE_ICON_SIZE, MODE_ICON_SIZE)
iconFrame:SetPoint("CENTER", modeRing)
iconFrame:SetFrameLevel(swipe:GetFrameLevel() + 2)
local modeIcon = iconFrame:CreateTexture(nil, "ARTWORK")
modeIcon:SetAllPoints()
modeIcon:SetTexture(MODE_ICON)
modeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local modeMask = iconFrame:CreateMaskTexture()
modeMask:SetTexture(ROUND_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
modeMask:SetAllPoints(modeIcon)
modeIcon:AddMaskTexture(modeMask)

-- A heading and its fish, on as many columns as allowed, going towards the middle of the screen.
local function FishBlock(side, x, columns)
    local heading = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOP" .. side, bottomBand, "TOP" .. side, x, -14)
    local lists = {}
    for i = 1, columns do
        local list = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if i == 1 then
            list:SetPoint("TOP" .. side, heading, "BOTTOM" .. side, 0, -5)
        elseif side == "LEFT" then
            list:SetPoint("TOPLEFT", lists[i - 1], "TOPRIGHT", COLUMN_GAP, 0)
        else
            list:SetPoint("TOPRIGHT", lists[i - 1], "TOPLEFT", -COLUMN_GAP, 0)
        end
        list:SetJustifyH(side)
        list:SetSpacing(3)
        lists[i] = list
    end
    return heading, lists
end
local zoneHeading, zoneLists = FishBlock("LEFT", 40, 3)
local sessionHeading, sessionLists = FishBlock("RIGHT", -40, 2)

---------------------------------------------------------------------------
-- Bobber countdown
---------------------------------------------------------------------------

local function ShowCountdown()
    swipe:SetCooldown(castStart, castEnd - castStart)
    modeRing:SetVertexColor(0.25, 0.2, 0.1)
end

local function StartCountdown(start, finish)
    castStart, castEnd = start, finish
    ShowCountdown()
end

local function EndCountdown()
    castStart, castEnd = nil, nil
    swipe:SetCooldown(0, 0)
    modeRing:SetVertexColor(1, 1, 1)
end

-- Red at 0, yellow halfway, green at 1.
local function ProgressColor(progress)
    if progress > 0.5 then return (1 - progress) * 2, 1, 0.1 end
    return 1, progress * 2, 0.1
end

local function RefreshRingColor()
    if not castEnd then return end
    local r, g, b = ProgressColor(math.max((castEnd - GetTime()) / (castEnd - castStart), 0))
    swipe:SetSwipeColor(r, g, b, 1)
end

-- Nil when the game keeps the times secret.
local function ReadChannel()
    local _, _, _, startMS, endMS = UnitChannelInfo("player")
    if not startMS or not endMS then return nil end
    if issecretvalue and (issecretvalue(startMS) or issecretvalue(endMS)) then return nil end
    return startMS / 1000, endMS / 1000
end

---------------------------------------------------------------------------
-- Fishing Buddy data
---------------------------------------------------------------------------

-- FishingHoles[mapId * 1000 + subzone index][fish id] = number caught
local function Holes()
    local info = _G.FishingBuddy_Info
    return type(info) == "table" and type(info.FishingHoles) == "table" and info.FishingHoles or nil
end

local function CurrentMapId()
    local lib = LibStub and LibStub("LibFishing-1.0", true)
    if not lib then return nil end
    local ok, mapId = pcall(lib.GetCurrentMapId, lib)
    return ok and mapId or nil
end

local function AddCounts(counts, hole)
    for id, count in pairs(hole) do
        if type(count) == "number" then counts[id] = (counts[id] or 0) + count end
    end
end

local function ReadZone()
    local counts, holes = {}, Holes()
    local mapId = CurrentMapId()
    if not holes or not mapId then return counts end
    local zoneKey = mapId * 1000
    local subZones = _G.FishingBuddy_Info.SubZones
    local count = type(subZones) == "table" and subZones[zoneKey]
    for s = 0, type(count) == "number" and count or 0 do
        if holes[zoneKey + s] then AddCounts(counts, holes[zoneKey + s]) end
    end
    return counts
end

local function ReadAll()
    local counts, holes = {}, Holes()
    if holes then
        for _, hole in pairs(holes) do
            if type(hole) == "table" then AddCounts(counts, hole) end
        end
    end
    return counts
end

-- Fishing Buddy doesn't expose its session counts: compare with the totals when the bands first show.
local function ReadSession()
    local counts = {}
    if not baseline then return counts end
    for id, count in pairs(ReadAll()) do
        local caught = count - (baseline[id] or 0)
        if caught > 0 then counts[id] = caught end
    end
    return counts
end

local function Total(counts)
    local total = 0
    for _, count in pairs(counts) do total = total + count end
    return total
end

local function FishLine(id, count)
    local info = _G.FishingBuddy_Info
    local fish = type(info) == "table" and type(info.Fishies) == "table" and info.Fishies[id]
    local name = fish and fish[GetLocale()] or (type(id) == "string" and id) or UNKNOWN
    local color = fish and type(fish.color) == "string" and fish.color:match("^%x%x%x%x%x%x%x%x$")
    if color then name = "|c" .. color .. name .. "|r" end
    return format("|T%s:14|t %s x%d", fish and fish.texture or DEFAULT_ICON, name, count)
end

-- Most caught first. Whatever doesn't fit in the columns stays counted in the heading's total.
local function FillLists(lists, counts)
    local ids = {}
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return tostring(a) < tostring(b)
    end)
    for column, list in ipairs(lists) do
        local lines = {}
        for i = (column - 1) * LINES_PER_COLUMN + 1, math.min(#ids, column * LINES_PER_COLUMN) do
            lines[#lines + 1] = FishLine(ids[i], counts[ids[i]])
        end
        list:SetText(table.concat(lines, "\n"))
    end
    if #ids == 0 then lists[1]:SetText(L["No catch yet"]) end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function SampleCounts(first, second, third)
    return {
        [L["Test fish"] .. " A"] = first,
        [L["Test fish"] .. " B"] = second,
        [L["Test fish"] .. " C"] = third,
    }
end

-- Returns nil when the character hasn't learned fishing.
local function ReadSkill()
    local _, _, _, fishing = GetProfessions()
    if not fishing then return nil end
    local _, _, rank, maxRank, _, _, _, bonus = GetProfessionInfo(fishing)
    return rank, maxRank, bonus
end

-- Without the bar, the title takes the middle of the band.
local function ShowSkillBar(shown)
    skillBar:SetShown(shown)
    title:SetPoint("CENTER", 0, shown and 14 or 0)
end

local function RefreshSkill()
    local ok, rank, maxRank, bonus = pcall(ReadSkill)
    if not ok or not rank then
        if not testing then
            ShowSkillBar(false)
            return
        end
        rank, maxRank, bonus = 75, 150, 5
    end
    -- The bonus of the gear doesn't count: only the skill itself can be maxed out.
    if rank >= MAX_SKILL and not testing then
        ShowSkillBar(false)
        return
    end
    maxRank = maxRank or 0
    skillBar:SetMinMaxValues(0, math.max(maxRank, 1))
    skillBar:SetValue(rank)
    skillBar:SetStatusBarColor(ProgressColor(math.min(rank / MAX_SKILL, 1)))
    local line = format(L["Fishing skill: %d / %d"], rank, maxRank)
    if bonus and bonus > 0 then line = line .. format(" (+%d)", bonus) end
    skillText:SetText(line)
    ShowSkillBar(true)
end

local function Refresh()
    local zoneName = GetRealZoneText() or ""
    local subZone = GetSubZoneText()
    title:SetText(subZone and subZone ~= "" and subZone or zoneName)
    RefreshSkill()

    local zoneCounts, sessionCounts = ReadZone(), ReadSession()
    if testing then
        if not next(zoneCounts) then zoneCounts = SampleCounts(84, 31, 9) end
        if not next(sessionCounts) then sessionCounts = SampleCounts(7, 3, 1) end
    end
    zoneHeading:SetText(format(L["%s: %d caught"], zoneName, Total(zoneCounts)))
    FillLists(zoneLists, zoneCounts)
    sessionHeading:SetText(format(L["Session: %d caught"], Total(sessionCounts)))
    FillLists(sessionLists, sessionCounts)
end

scene.onUpdate = RefreshRingColor

local function Play()
    if scene:IsPlaying() then return end
    scene:Play()
    -- At least as high as the immersion mode's black bars, which they cover.
    local bars = db.letterbox and WorldFrame:GetHeight() * WorldFrame:GetEffectiveScale() * db.letterboxSize / 100 or 0
    local height = math.max(BAND_HEIGHT, bars / scene.frame:GetEffectiveScale())
    topBand:SetHeight(height)
    bottomBand:SetHeight(height)
    scene:SetBandOpacity(db.letterboxTranslucent and 0.92 or 1)
    if castEnd and castEnd > GetTime() then ShowCountdown() end
end

local function Stop()
    if testing then EndCountdown() end
    testing = false
    scene:Stop()
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function IsFishingSpell(spellID)
    if not spellID or (issecretvalue and issecretvalue(spellID)) then return false end
    if FISHING_SPELLS[spellID] then return true end
    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    return name ~= nil and name == _G.PROFESSIONS_FISHING
end

local function HasPole()
    local itemID = GetInventoryItemID("player", MAIN_HAND_SLOT)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE_SUBCLASS
end

local function Update()
    if not ticker then return end
    if InCombatLockdown() then
        Stop()
        return
    end
    local on = ns.ImmersionMode.IsOn()
    if not on and not ns.ImmersionMode.IsResuming() then autoStarted = false end
    if on and (testing or (HasPole() and Holes())) and not scene:OtherPlaying() then
        baseline = baseline or ReadAll()
        Refresh()
        Play()
    else
        Stop()
    end
end

-- Starts when the pole goes on and only then: once dismissed, the mode doesn't come back by itself.
local function CheckPole()
    local hasPole = HasPole()
    if hasPole and not hadPole and db.fishingAuto and Holes() and not ns.ImmersionMode.IsOn() then
        autoStarted = ns.ImmersionMode.Enter()
    elseif not hasPole and autoStarted then
        autoStarted = false
        ns.ImmersionMode.Leave()
    end
    hadPole = hasPole
end

scene.onClose = function() ns.ImmersionMode.Leave() end

-- Plays the bands with sample values when Fishing Buddy has nothing to show here.
local function Test()
    if not ticker or testing or InCombatLockdown() or scene:OtherPlaying() then return end
    testEntered = ns.ImmersionMode.Enter(true)
    if not ns.ImmersionMode.IsOn() then return end
    testing = true
    StartCountdown(GetTime(), GetTime() + ns.ImmersionScene.TEST_DURATION)
    Update()
    scene:EndTestAfter(function()
        if not testing then return end
        Stop()
        if testEntered then ns.ImmersionMode.Leave() end
        Update()
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        if IsFishingSpell(spellID) then
            local start, finish = ReadChannel()
            if start then StartCountdown(start, finish) end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if castEnd then EndCountdown() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == MAIN_HAND_SLOT then
            CheckPole()
            Update()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Stop()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Update()
    end
end)

---------------------------------------------------------------------------
-- Interface for the immersion mode, which holds the options
---------------------------------------------------------------------------

ns.FishingDisplay = { Update = Update, Test = Test }

function ns.FishingDisplay.Enable(settings)
    db = settings
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(e)
    end
    ticker = C_Timer.NewTicker(CHECK_EVERY, Update)
    hadPole = false
    CheckPole()
    Update()
end

function ns.FishingDisplay.Disable()
    if not ticker then return end
    ticker:Cancel()
    ticker = nil
    events:UnregisterAllEvents()
    Stop()
    EndCountdown()
    autoStarted = false
end
