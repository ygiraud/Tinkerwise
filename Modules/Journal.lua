-- Journal: keeps, for each character, the date of the zones seen for the first time, the levels, the
-- deaths and the bosses. Shown with /tw journal. Saved for the account, so that a lost Hardcore
-- character can still be read.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local MAX_ENTRIES = 2000
local ROW_H = 24

local KINDS = {
    zone = { icon = "Interface\\Icons\\INV_Misc_Map_01", text = L["Discovered %s"] },
    level = { icon = "Interface\\Icons\\Spell_Holy_BorrowedTime", text = L["Reached level %s"] },
    death = { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", text = L["Died in %s"] },
    boss = { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", text = L["Defeated %s"] },
}

local db -- nil while the module is off
local win, rows, shownKey = nil, {}, nil
local Refresh

local function Store()
    TinkerwiseDB.journal = TinkerwiseDB.journal or {}
    return TinkerwiseDB.journal
end

-- The character's record: { name, class, entries = { { kind, text, time } }, zones = { [name] = true } }.
local function Own()
    local key = ns.CharacterKey()
    local record = Store()[key]
    -- The realm sometimes reads empty on WoW Forever: the record already there is the same character's.
    if not record and key:sub(-3) == " - " then
        for other, r in pairs(Store()) do
            if other:sub(1, #key) == key then record, key = r, other break end
        end
    end
    if not record then
        record = { entries = {}, zones = {}, deaths = 0 }
        Store()[key] = record
    end
    record.name = TW:PlayerName()
    record.class = select(2, UnitClass("player"))
    return record, key
end

local function Add(kind, text)
    if not db or not db[kind] or type(text) ~= "string" or text == "" then return end
    local record = Own()
    local entries = record.entries
    entries[#entries + 1] = { kind, text, time() }
    if #entries > MAX_ENTRIES then table.remove(entries, 1) end
    Refresh()
end

local function ZoneName()
    local name = ns.Spells.Plain(GetRealZoneText())
    return name ~= "" and name or nil
end

local function NoteZone()
    local zone = ZoneName()
    if not db or not zone then return end
    local record = Own()
    if record.zones[zone] then return end
    record.zones[zone] = true
    Add("zone", zone)
end

local function NoteDeath()
    local record = Own()
    record.deaths = record.deaths + 1
    Add("death", ZoneName() or "?")
end

ns.Journal = {}

-- The character's deaths since the journal exists, and the time of their last level (or nil).
function ns.Journal.Deaths()
    return db and Own().deaths or nil
end

function ns.Journal.LevelTime(level)
    if not db then return end
    local entries = Own().entries
    for i = #entries, 1, -1 do
        if entries[i][1] == "level" and entries[i][2] == tostring(level) then return entries[i][3] end
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function SortedKeys()
    local keys = {}
    for key in pairs(Store()) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, win.child)
    r:SetSize(440, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", -120, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.date = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.date:SetPoint("RIGHT", -4, 0)
    rows[i] = r
    return r
end

local function Turn(step)
    local keys = SortedKeys()
    local at = 1
    for i, key in ipairs(keys) do
        if key == shownKey then at = i end
    end
    shownKey = keys[(at - 1 + step) % #keys + 1]
    Refresh()
end

local function Build()
    win = CreateFrame("Frame", "TinkerwiseJournalFrame", UIParent, "BackdropTemplate")
    win:SetSize(520, 480)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    TW:SkinDialog(win, L["Travel Journal"])
    tinsert(UISpecialFrames, "TinkerwiseJournalFrame")

    win.who = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.who:SetPoint("TOP", 0, -38)
    for _, side in ipairs({ { "Prev", -1, "RIGHT", "LEFT", -12 }, { "Next", 1, "LEFT", "RIGHT", 12 } }) do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(28, 28)
        b:SetPoint(side[3], win.who, side[4], side[5], 0)
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. side[1] .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. side[1] .. "Page-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function() Turn(side[2]) end)
        win[side[1]] = b
    end

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -72)
    scroll:SetPoint("BOTTOMRIGHT", -42, 46)
    win.child = CreateFrame("Frame", nil, scroll)
    win.child:SetSize(440, 1)
    scroll:SetScrollChild(win.child)

    win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.footer:SetPoint("BOTTOMLEFT", 26, 22)
end

function Refresh()
    if not win or not win:IsShown() then return end
    local store = Store()
    local record = store[shownKey]
    if not record then
        record, shownKey = Own()
    end
    local color = RAID_CLASS_COLORS[record.class]
    win.who:SetText(color and format("|c%s%s|r", color.colorStr, record.name) or record.name)
    local several = #SortedKeys() > 1
    win.Prev:SetShown(several)
    win.Next:SetShown(several)

    local entries = record.entries
    for i = 1, #entries do -- newest first
        local entry = entries[#entries + 1 - i]
        local kind = KINDS[entry[1]] or KINDS.zone
        local r = Row(i)
        r.icon:SetTexture(kind.icon)
        r.text:SetText(format(kind.text, entry[2]))
        r.date:SetText(date(L["%m/%d/%Y"], entry[3]) .. " " .. date("%H:%M", entry[3]))
        r:Show()
    end
    for i = #entries + 1, #rows do rows[i]:Hide() end
    win.child:SetHeight(math.max(#entries * ROW_H, 1))
    win.footer:SetText(format(L["%d entries, %d death(s)"], #entries, record.deaths or 0))
end

local function Toggle()
    if not win then Build() end
    if win:IsShown() then return win:Hide() end
    shownKey = select(2, Own())
    win:Show()
    Refresh()
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, arg2, _, _, arg5)
    if event == "PLAYER_LEVEL_UP" then
        Add("level", tostring(arg1))
    elseif event == "PLAYER_DEAD" then
        NoteDeath()
    elseif event == "ENCOUNTER_END" then
        if ns.Spells.Plain(arg5) == 1 then Add("boss", ns.Spells.Plain(arg2)) end
    else
        C_Timer.After(2, NoteZone) -- the name is not always ready at once
    end
end)

local mod = TW:NewModule("Journal", {
    title = L["Travel Journal"],
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    section = L["Character"],
    desc = L["Keeps the date of the zones you enter for the first time, your levels, your deaths and the bosses you defeat, for each character, from the day the module is on. Read it with /tw journal."],
    defaults = { zone = true, level = true, death = true, boss = true },
    options = {
        { type = "toggle", key = "zone", label = L["New zones"] },
        { type = "toggle", key = "level", label = L["Levels"] },
        { type = "toggle", key = "death", label = L["Deaths"] },
        { type = "toggle", key = "boss", label = L["Bosses"] },
        { type = "execute", label = L["Open the journal"], func = function() Toggle() end },
    },
})

TW.commands.journal = function()
    if mod.active then Toggle() else TW:Print(L["the Travel Journal module is off."]) end
end

function mod:OnEnable()
    db = self.db
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_DEAD", "ENCOUNTER_END" }) do
        pcall(events.RegisterEvent, events, e)
    end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if win then win:Hide() end
    db = nil
end
