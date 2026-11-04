-- Characters: gold, level, rested XP and last login of every character of the account.
-- A character's data is saved while it is played; rested XP is then estimated from the elapsed time.

local _, ns = ...
local TW = ns.TW

local HOURS_PER_REST_STEP = 8
local REST_STEP = 0.05        -- 5 % of a level per 8 hours in an inn
local OUTSIDE_FACTOR = 0.25   -- rest is four times slower outside an inn
local REST_CAP = 1.5          -- 150 % of a level

local db

local function Save()
    if not db then return end
    local key = UnitName("player") .. " - " .. GetRealmName()
    db.chars[key] = {
        name = UnitName("player"),
        class = select(2, UnitClass("player")),
        level = UnitLevel("player"),
        money = GetMoney(),
        rested = GetXPExhaustion() or 0,
        xpMax = UnitXPMax("player"),
        resting = IsResting(),
        time = time(),
    }
end

local function RestedPercent(c)
    if c.xpMax <= 0 then return 0 end
    local steps = (time() - c.time) / 3600 / HOURS_PER_REST_STEP
    local gain = steps * REST_STEP * c.xpMax * (c.resting and 1 or OUTSIDE_FACTOR)
    return math.min(c.rested + gain, c.xpMax * REST_CAP) / c.xpMax * 100
end

local function Ago(seconds)
    if seconds < 3600 then return "à l'instant" end
    if seconds < 86400 then return format("il y a %d h", seconds / 3600) end
    return format("il y a %d j", seconds / 86400)
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
    TW:SkinDialog(win, "Mes personnages")
    tinsert(UISpecialFrames, "TinkerwiseCharactersFrame")

    local head = CreateFrame("Frame", nil, win)
    head:SetSize(560, ROW_H)
    head:SetPoint("TOPLEFT", 24, -48)
    for i, text in ipairs({ "Personnage", "Niv.", "Or", "Repos (≈)", "Vu" }) do
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
        list[#list + 1] = c
        gold = gold + c.money
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    for i, c in ipairs(list) do
        local row = Row(i)
        local color = RAID_CLASS_COLORS[c.class]
        row.cells[1]:SetText(color and format("|c%s%s|r", color.colorStr, c.name) or c.name)
        row.cells[2]:SetText(c.level)
        row.cells[3]:SetText(GetCoinTextureString(c.money))
        row.cells[4]:SetText(format("%d %%", RestedPercent(c)))
        row.cells[5]:SetText(Ago(time() - c.time))
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    total:SetText("Total : " .. GetCoinTextureString(gold))
    win:SetHeight(120 + #list * ROW_H)
end

local function Toggle()
    if win and win:IsShown() then return win:Hide() end
    Refresh()
    win:Show()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Save)

local mod = TW:NewModule("Characters", {
    title = "Mes personnages",
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    section = "Personnage",
    accountWide = true,
    desc = "Résume l'or, le niveau, l'XP reposée et la dernière connexion de vos personnages. Un personnage apparaît après sa première connexion et ses données datent de sa dernière session ; seul le repos est estimé d'après le temps écoulé. /twperso pour ouvrir.",
    options = {
        { type = "execute", label = "Afficher", func = Toggle },
    },
})

function mod:OnEnable()
    db = self.db
    db.chars = db.chars or {}
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE",
                         "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "PLAYER_LOGOUT" }) do
        events:RegisterEvent(e)
    end
    if IsLoggedIn() then Save() end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if win then win:Hide() end
end

SLASH_TINKERWISEPERSO1 = "/twperso"
SlashCmdList.TINKERWISEPERSO = function()
    if mod.active then Toggle() else TW:Print("le module Mes personnages est désactivé (/tw).") end
end
