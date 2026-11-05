-- Characters: gold, level, rested XP and last login of every character of the account.
-- A character's data is saved while it is played; rested XP is then estimated from the elapsed time.
-- Part of the "Mes personnages" module (see Bags.lua), whose saved table it shares.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetCoinTextureString = ns.API.GetCoinTextureString

local HOURS_PER_REST_STEP = 8
local REST_STEP = 0.05        -- 5 % of a level per 8 hours in an inn
local OUTSIDE_FACTOR = 0.25   -- rest is four times slower outside an inn
local REST_CAP = 1.5          -- 150 % of a level

local db

local function Save()
    if not db then return end
    local c = ns.CurrentCharacter()
    c.level = UnitLevel("player")
    c.rested = GetXPExhaustion() or 0
    c.xpMax = UnitXPMax("player")
    c.resting = IsResting()
    c.time = time()
end

local function RestedPercent(c)
    if c.xpMax <= 0 then return 0 end
    local steps = (time() - c.time) / 3600 / HOURS_PER_REST_STEP
    local gain = steps * REST_STEP * c.xpMax * (c.resting and 1 or OUTSIDE_FACTOR)
    return math.min(c.rested + gain, c.xpMax * REST_CAP) / c.xpMax * 100
end

local function Ago(seconds)
    if seconds < 3600 then return L["just now"] end
    if seconds < 86400 then return format(L["%d h ago"], seconds / 3600) end
    return format(L["%d d ago"], seconds / 86400)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local ROW_H, COLUMNS = 22, { 24, 170, 220, 370, 460 }
local win, total
local rows = {}

local function Cell(row, i, font)
    local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("LEFT", COLUMNS[i] - 24, 0)
    return fs
end

local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Frame", nil, win)
    row:SetSize(560, ROW_H)
    row:SetPoint("TOPLEFT", 24, -74 - (i - 1) * ROW_H)
    row.cells = { Cell(row, 1), Cell(row, 2), Cell(row, 3), Cell(row, 4), Cell(row, 5) }
    rows[i] = row
    return row
end

local function Build()
    win = CreateFrame("Frame", "TinkerwiseCharactersFrame", UIParent, "BackdropTemplate")
    win:SetSize(620, 200)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    TW:SkinDialog(win, L["My Characters"])
    tinsert(UISpecialFrames, "TinkerwiseCharactersFrame")

    local head = CreateFrame("Frame", nil, win)
    head:SetSize(560, ROW_H)
    head:SetPoint("TOPLEFT", 24, -48)
    for i, text in ipairs({ L["Character"], L["Lvl"], L["Gold"], L["Rested (≈)"], L["Seen"] }) do
        Cell(head, i, "GameFontNormal"):SetText(text)
    end
    total = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    total:SetPoint("BOTTOMRIGHT", -26, 20)
end

local function Refresh()
    Save()
    if not win then Build() end
    local list = {}
    local gold = 0
    for _, c in pairs(db.chars) do
        if c.level then -- not seen since this list exists: only its bags are known
            list[#list + 1] = c
            gold = gold + c.money
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    for i, c in ipairs(list) do
        local row = Row(i)
        row.cells[1]:SetText(ns.ClassColored(c))
        row.cells[2]:SetText(c.level)
        row.cells[3]:SetText(GetCoinTextureString(c.money))
        row.cells[4]:SetText(c.level >= GetMaxPlayerLevel() and "----" or format("%d %%", RestedPercent(c)))
        row.cells[5]:SetText(Ago(time() - c.time))
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    total:SetText(L["Total: "] .. GetCoinTextureString(gold))
    win:SetHeight(120 + #list * ROW_H)
end

local function Toggle()
    if win and win:IsShown() then return win:Hide() end
    Refresh()
    win:Show()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Save)

ns.CharacterList = { Toggle = Toggle }

function ns.CharacterList.Enable(moduleDB)
    db = moduleDB
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE",
                         "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "PLAYER_LOGOUT" }) do
        events:RegisterEvent(e)
    end
    if IsLoggedIn() then Save() end
end

function ns.CharacterList.Disable()
    events:UnregisterAllEvents()
    if win then win:Hide() end
end

TW.commands.chars = function()
    if TW.modules.Bags.active then Toggle() else TW:Print(L["the My Characters module is disabled (/tw)."]) end
end
