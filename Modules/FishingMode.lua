-- FishingMode: with Fishing Buddy installed, the interface fades away and black bands show the
-- fishing skill and its statistics: the zone's catches and those of the session. The camera is left
-- alone and the middle of the screen takes no clicks, so the bobber stays clickable.
--
-- The mode starts by itself (when casting, or when a fishing pole is equipped) or with its key:
--   "cast"    ends when moving, entering combat or after a while without casting
--   "pole"    ends when the pole is unequipped; the scene pauses in combat
--   "manual"  ends with the key; the scene pauses in combat

local _, ns = ...
local L = ns.L
local TW = ns.TW

local issecretvalue = _G.issecretvalue

local CHECK_EVERY = 0.5
local IDLE_TIMEOUT = 30 -- seconds without a cast before a "cast" mode ends
local LINES_PER_COLUMN = 4
local COLUMN_GAP = 24
local LOOT_LINES, LOOT_LINE_H = 5, 26
local LOOT_HOLD, LOOT_FADE = 6, 1 -- seconds a loot line stays, then takes to disappear
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Fish_02"
local MODE_ICON = "Interface\\Icons\\INV_Fishingpole_02"
local MODE_ICON_SIZE = 64
local MODE_RING_SIZE = 74
local SKILL_BAR_W, SKILL_BAR_H = 280, 16
local FISHING_SPELLS = { [7620] = true, [131474] = true, [131490] = true }
local MAIN_HAND_SLOT = 16
local WEAPON_CLASS, FISHING_POLE_SUBCLASS = 2, 20
local ROUND_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local db, ticker, baseline, source, castStart, castEnd
local casting, dismissed, testing, hadPole = false, false, false, false
local lastCast = 0

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- Only the bands take the mouse: unlike the other scenes, the player has to click in the world.
local scene = ns.ImmersionScene.Create({
    name = "TinkerwiseFishingScene", bandHeight = 110, closable = true, clickThrough = true,
})
local topBand, bottomBand = scene.topBand, scene.bottomBand

local title = scene:CreateTitle(topBand, 34)
title:SetPoint("CENTER", 0, 14)

-- Fishing skill: a bar that fills up, its value written on it.
local skillBar = CreateFrame("StatusBar", nil, topBand)
skillBar:SetSize(SKILL_BAR_W, SKILL_BAR_H)
skillBar:SetPoint("TOP", title, "BOTTOM", 0, -8)
skillBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
skillBar:SetStatusBarColor(0.85, 0.65, 0.15)

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
-- Loot
---------------------------------------------------------------------------

-- Plain text above the bottom band, newest first: it takes no clicks, so the bobber stays reachable.
local lootEntries = {} -- { text, time }
local lootLines = {}
for i = 1, LOOT_LINES do
    local line = bottomBand:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    line:SetPoint("BOTTOM", bottomBand, "TOP", 0, 12 + (i - 1) * LOOT_LINE_H)
    line:Hide()
    lootLines[i] = line
end

local function RenderLoot()
    for i, line in ipairs(lootLines) do
        local entry = lootEntries[i]
        line:SetText(entry and entry.text or "")
        line:SetShown(entry ~= nil)
    end
end

local function RefreshLoot()
    local now, changed = GetTime(), false
    for i = #lootEntries, 1, -1 do
        local age = now - lootEntries[i].time
        if age > LOOT_HOLD + LOOT_FADE then
            table.remove(lootEntries, i)
            changed = true
        else
            lootLines[i]:SetAlpha(age > LOOT_HOLD and 1 - (age - LOOT_HOLD) / LOOT_FADE or 1)
        end
    end
    if changed then RenderLoot() end
end

local function AddLoot(icon, name, count)
    local text = format("|T%s:20|t %s", icon or DEFAULT_ICON, name)
    if count > 1 then text = text .. " x" .. count end
    table.insert(lootEntries, 1, { text = text, time = GetTime() })
    lootEntries[LOOT_LINES + 1] = nil
    RenderLoot()
end

local function OnLootMessage(message)
    local link, count = ns.ParseLootMessage(message)
    if link then AddLoot((select(5, ns.API.GetItemInfoInstant(link))), link, count) end
end

local function ClearLoot()
    wipe(lootEntries)
    RenderLoot()
end

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

-- Green with all the time left, yellow halfway, red at the end.
local function RefreshRingColor()
    if not castEnd then return end
    local left = math.max((castEnd - GetTime()) / (castEnd - castStart), 0)
    if left > 0.5 then
        swipe:SetSwipeColor((1 - left) * 2, 1, 0.1, 1)
    else
        swipe:SetSwipeColor(1, left * 2, 0.1, 1)
    end
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

-- Fishing Buddy doesn't expose its session counts: compare with the totals when the mode first starts.
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

local function RefreshSkill()
    local ok, rank, maxRank, bonus = pcall(ReadSkill)
    if not ok or not rank then
        if not testing then
            skillBar:Hide()
            return
        end
        rank, maxRank, bonus = 75, 150, 5
    end
    maxRank = maxRank or 0
    skillBar:SetMinMaxValues(0, math.max(maxRank, 1))
    skillBar:SetValue(rank)
    local line = format(L["Fishing skill: %d / %d"], rank, maxRank)
    if bonus and bonus > 0 then line = line .. format(" (+%d)", bonus) end
    skillText:SetText(line)
    skillBar:Show()
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

scene.onUpdate = function()
    RefreshRingColor()
    RefreshLoot()
end

local function Play()
    if scene:IsPlaying() then return end
    scene:Play()
    if castEnd and castEnd > GetTime() then ShowCountdown() end
end

local function Stop()
    if not scene:IsPlaying() then return end
    if testing then EndCountdown() end
    testing = false
    scene:Stop()
    ClearLoot()
end

---------------------------------------------------------------------------
-- Mode state
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

local function IsMoving()
    local speed = GetUnitSpeed("player")
    if issecretvalue and issecretvalue(speed) then return false end
    return speed > 0
end

local function Begin(kind)
    source, dismissed = kind, false
    baseline = baseline or ReadAll()
end

local function EndMode()
    source, casting, dismissed = nil, false, false
    Stop()
end

local function Update()
    if testing then
        if InCombatLockdown() then Stop() else Refresh() end
        return
    end
    if not source then return end
    if InCombatLockdown() then
        if source == "cast" then EndMode() else Stop() end
        return
    end
    if source == "cast" and (IsMoving() or (not casting and GetTime() - lastCast > IDLE_TIMEOUT)) then
        EndMode()
        return
    end
    if dismissed or scene:OtherPlaying() then
        Stop()
        return
    end
    Refresh()
    Play()
end

-- Starts when the pole goes on and only then: once dismissed, the mode doesn't come back by itself.
local function CheckPole()
    local hasPole = HasPole()
    if db.autoMode == "pole" and hasPole and not hadPole and not source and Holes() then
        Begin("pole")
    elseif not hasPole and source == "pole" then
        EndMode()
    end
    hadPole = hasPole
end

local function Dismiss()
    if testing or source == "manual" then
        if testing then Stop() else EndMode() end
    else
        dismissed = true
        Stop()
    end
end

scene.onClose = Dismiss

local function Toggle()
    if InCombatLockdown() then return end
    if scene:IsPlaying() then
        Dismiss()
    elseif source then
        dismissed = false
        Update()
    elseif Holes() then
        Begin("manual")
        Update()
    else
        TW:Print(L["the fishing mode needs Fishing Buddy."])
    end
end

-- Plays the scene with sample values when Fishing Buddy has nothing to show here.
local function StartTest()
    if scene:IsPlaying() or source or InCombatLockdown() or scene:OtherPlaying() then return end
    testing = true
    StartCountdown(GetTime(), GetTime() + ns.ImmersionScene.TEST_DURATION)
    Refresh()
    Play()
    AddLoot(nil, L["Test fish"] .. " A", 2)
    AddLoot(nil, L["Test fish"] .. " B", 1)
    scene:EndTestAfter(function()
        if testing then Stop() end
    end)
end

---------------------------------------------------------------------------
-- Key and events
---------------------------------------------------------------------------

local toggle = CreateFrame("Button", "TinkerwiseFishingToggle")
toggle:SetScript("OnClick", function() Toggle() end)

-- Bindings can't change in combat: PLAYER_REGEN_ENABLED applies them afterwards.
local function ApplyBinding()
    if InCombatLockdown() then return end
    ClearOverrideBindings(toggle)
    if ticker and db.shortcut and db.shortcut ~= "" then
        SetOverrideBindingClick(toggle, false, db.shortcut, "TinkerwiseFishingToggle")
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        if IsFishingSpell(spellID) then
            local start, finish = ReadChannel()
            if start then StartCountdown(start, finish) end
            if db.autoMode == "cast" and Holes() then
                if not source then Begin("cast") end
                if source == "cast" then
                    casting, lastCast = true, GetTime()
                    Update()
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if casting then casting, lastCast = false, GetTime() end
        if castEnd then EndCountdown() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == MAIN_HAND_SLOT then
            CheckPole()
            Update()
        end
    elseif event == "CHAT_MSG_LOOT" then
        if scene:IsPlaying() then OnLootMessage((...)) end
    elseif event == "LOOT_OPENED" then
        -- The loot window belongs to the faded interface: bring it back unless looting is automatic.
        local autoLoot = ...
        if scene:IsPlaying() and not autoLoot then scene:KeepInterface(true) end
    elseif event == "LOOT_CLOSED" then
        scene:KeepInterface(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ApplyBinding()
        if not ticker then self:UnregisterAllEvents() end -- disabled in combat (see OnDisable)
    else -- PLAYER_REGEN_DISABLED, PLAYER_LEAVING_WORLD
        if source == "cast" then EndMode() else Stop() end
    end
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local mod = TW:NewModule("FishingMode", {
    title = L["Fishing Mode"],
    icon = MODE_ICON,
    section = "Immersion",
    desc = L["Requires Fishing Buddy. The interface fades away and black bands show your fishing skill, the catches of the zone and of the session, and a ring showing the bobber's time left. The camera doesn't move and the bobber stays clickable. Start it automatically or with its key. Click the cross or press Escape to get the interface back. The scene pauses in combat."]
        .. " " .. L["What you pick up shows for a few seconds above the bottom band."],
    defaults = { autoMode = "cast", shortcut = "ALT-P" },
    options = {
        { type = "select", key = "autoMode", label = L["Automatic activation"], values = {
            { "never", L["Never"] },
            { "pole", L["Fishing pole equipped"] },
            { "cast", L["When fishing"] },
        } },
        { type = "keybind", key = "shortcut", label = L["Show or hide the fishing mode"] },
        { type = "execute", label = L["Test (15 s)"], func = StartTest },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "CHAT_MSG_LOOT", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "PLAYER_LEAVING_WORLD" }) do
        events:RegisterEvent(e)
    end
    ticker = C_Timer.NewTicker(CHECK_EVERY, Update)
    ApplyBinding()
    hadPole = false
    CheckPole()
    Update()
end

function mod:OnDisable()
    if ticker then ticker:Cancel() end
    ticker = nil
    EndMode()
    EndCountdown()
    if InCombatLockdown() then
        events:UnregisterAllEvents()
        events:RegisterEvent("PLAYER_REGEN_ENABLED") -- to remove the key after combat
    else
        events:UnregisterAllEvents()
        ClearOverrideBindings(toggle)
    end
end

function mod:OnOptionChanged(key)
    if key == "shortcut" then
        ApplyBinding()
    elseif key == "autoMode" then
        if source ~= "manual" then EndMode() end
        hadPole = false
        CheckPole()
        Update()
    end
end
