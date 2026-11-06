-- CharacterGroups: sorts the characters of "Mes personnages" (see Bags.lua) into groups.
-- The game mode (PvE, PvP, Hardcore, RP, RP-PvP) is detected, and the player adds their own
-- groups inside each mode, so "PvE - Default group" and "PvP - Default group" stay apart.
-- All the data remains in the same saved table: groups only filter what is shown.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local UNKNOWN = "unknown" -- character not seen since modes are recorded, and no known one on its realm
local MODE_ORDER = { "pve", "pvp", "hardcore", "rp", "rppvp", UNKNOWN }
local MODE_LABELS = {
    pve = "PvE", pvp = "PvP", hardcore = "Hardcore", rp = "RP", rppvp = "RP-PvP",
    [UNKNOWN] = L["Not identified"],
}
local ROW_H, HEADER_H, LIST_W = 32, 24, 410

local G = {}
ns.CharacterGroups = G

local db, myKey
local gameMode
local viewedId -- group picked in the windows; nil = the current character's

local function RuleActive(name)
    local rule = Enum.GameRule and Enum.GameRule[name]
    if not (rule and C_GameRules and C_GameRules.IsGameRuleActive) then return false end
    local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
    return ok and active
end

function G.GameMode()
    if not gameMode then
        local rp, pvp = RuleActive("RPRuleset"), RuleActive("PvPRuleset")
        if RuleActive("HardcoreRuleset") then gameMode = "hardcore"
        elseif rp and pvp then gameMode = "rppvp"
        elseif rp then gameMode = "rp"
        elseif pvp then gameMode = "pvp"
        else gameMode = "pve" end
    end
    return gameMode
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------

local function GroupId(mode, name)
    return mode .. "\1" .. (name or "")
end

local function IdOf(key, c)
    return GroupId(c.mode or UNKNOWN, db.groupOf[key])
end

local function CurrentId()
    return GroupId(G.GameMode(), db.groupOf[myKey])
end

local function FullLabel(mode, name)
    return MODE_LABELS[mode] .. " - " .. (name or L["Default group"])
end

-- The picked group, unless its last character left it.
local function ViewedId()
    if viewedId then
        for key, c in pairs(db.chars) do
            if IdOf(key, c) == viewedId then return viewedId end
        end
        viewedId = nil
    end
    return CurrentId()
end

-- Tooltips only ever use the current group; the windows follow their menu.
function G.IsCurrentGroup(key, c)
    return key == myKey or IdOf(key, c) == CurrentId()
end

function G.IsViewed(key, c)
    return IdOf(key, c) == ViewedId()
end

-- Custom group names used in a mode, sorted.
local function NamesInMode(mode)
    local seen, names = {}, {}
    for key, c in pairs(db.chars) do
        local name = db.groupOf[key]
        if name and (c.mode or UNKNOWN) == mode and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- Every group holding a character: the current one first, then by mode.
local function ViewableGroups()
    local list = {}
    local current = CurrentId()
    local function Add(mode, name)
        local id = GroupId(mode, name)
        if id == current then
            table.insert(list, 1, { id = id, label = FullLabel(mode, name) })
        else
            for key, c in pairs(db.chars) do
                if IdOf(key, c) == id then
                    list[#list + 1] = { id = id, label = FullLabel(mode, name) }
                    break
                end
            end
        end
    end
    for _, mode in ipairs(MODE_ORDER) do
        Add(mode, nil)
        for _, name in ipairs(NamesInMode(mode)) do Add(mode, name) end
    end
    return list
end

function G.ViewedLabel()
    local id = ViewedId()
    for _, group in ipairs(ViewableGroups()) do
        if group.id == id then return group.label end
    end
    return ""
end

---------------------------------------------------------------------------
-- Management window
---------------------------------------------------------------------------

local win, info, listChild, bar, barLabel, barEdit
local rows, headers = {}, {}
local pendingKey

local function RefreshWindow()
    if not win or not win:IsShown() then return end
    local me = ns.CurrentCharacter()
    info:SetText(format(L["This character: %s (%s)"], ns.ClassColored(me), FullLabel(G.GameMode(), db.groupOf[myKey])))

    local byMode = {}
    for key, c in pairs(db.chars) do
        local mode = c.mode or UNKNOWN
        byMode[mode] = byMode[mode] or {}
        table.insert(byMode[mode], { key = key, c = c })
    end

    local y, rowCount, headerCount = 0, 0, 0
    local function AddSection(mode)
        local list = byMode[mode]
        if not list then return end
        byMode[mode] = nil
        table.sort(list, function(a, b) return a.key < b.key end)

        headerCount = headerCount + 1
        local header = headers[headerCount]
        if not header then
            header = listChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headers[headerCount] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 4, y - 6)
        header:SetText(mode == UNKNOWN and L["Not identified (log in with them once)"] or MODE_LABELS[mode])
        header:Show()
        y = y - HEADER_H

        for _, entry in ipairs(list) do
            rowCount = rowCount + 1
            local row = G.Row(rowCount)
            row.key, row.mode = entry.key, mode
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)
            row.name:SetText(ns.ClassColored(entry.c))
            -- The last login helps to spot a deleted character: the game does not tell.
            local seen = ""
            if entry.key == myKey then
                seen = L[" (you)"]
            elseif entry.c.time then
                seen = " · " .. ns.CharacterList.Ago(time() - entry.c.time)
            end
            row.realm:SetText((entry.c.realm or "") .. seen)
            UIDropDownMenu_SetText(row.menu, db.groupOf[entry.key] or L["Default group"])
            row.forget:SetShown(entry.key ~= myKey) -- the current character would come straight back
            row:Show()
            y = y - ROW_H
        end
    end
    AddSection(G.GameMode())
    for _, mode in ipairs(MODE_ORDER) do AddSection(mode) end

    for i = rowCount + 1, #rows do rows[i]:Hide() end
    for i = headerCount + 1, #headers do headers[i]:Hide() end
    listChild:SetHeight(math.max(-y, 1))
end

local function Changed()
    RefreshWindow()
    ns.RefreshCharacterViews()
end

local function SetGroup(key, name)
    db.groupOf[key] = name
    Changed()
end

local function AskNewGroup(key)
    local c = db.chars[key]
    if not c then return end
    pendingKey = key
    barLabel:SetText(format(L["New group for %s:"], ns.ClassColored(c)))
    bar:Show()
    barEdit:SetText("")
    barEdit:SetFocus()
end

local function CloseBar()
    pendingKey = nil
    barEdit:ClearFocus()
    bar:Hide()
end

local function ConfirmNewGroup()
    local typed = (barEdit:GetText() or ""):gsub("|", "") -- a "|" would start an escape sequence
    local name = strtrim(typed)
    local key, c = pendingKey, pendingKey and db.chars[pendingKey]
    CloseBar()
    if name == "" or not c then return end
    if name:lower() == L["Default group"]:lower() then return SetGroup(key, nil) end
    -- The same name typed differently is the same group.
    for _, existing in ipairs(NamesInMode(c.mode or UNKNOWN)) do
        if existing:lower() == name:lower() then name = existing end
    end
    SetGroup(key, name)
end

function G.Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Frame", nil, listChild)
    row:SetSize(LIST_W, ROW_H)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 4, -2)
    row.realm = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.realm:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)

    row.menu = CreateFrame("Frame", "TinkerwiseGroupRowDropDown" .. i, row, "UIDropDownMenuTemplate")
    row.menu:SetPoint("LEFT", 150, -2)
    UIDropDownMenu_SetWidth(row.menu, 130)
    UIDropDownMenu_Initialize(row.menu, function()
        local function Add(text, name)
            local item = UIDropDownMenu_CreateInfo()
            item.text = text
            item.checked = db.groupOf[row.key] == name
            item.func = function() SetGroup(row.key, name) end
            UIDropDownMenu_AddButton(item)
        end
        Add(L["Default group"], nil)
        for _, name in ipairs(NamesInMode(row.mode)) do Add(name, name) end
        local new = UIDropDownMenu_CreateInfo()
        new.text = L["New group…"]
        new.notCheckable = true
        new.func = function() AskNewGroup(row.key) end
        UIDropDownMenu_AddButton(new)
    end)

    row.forget = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.forget:SetSize(70, 22)
    row.forget:SetPoint("RIGHT", -4, 0)
    row.forget:SetText(L["Forget"])
    row.forget:SetScript("OnClick", function() ns.ForgetCharacter(row.key) end)

    rows[i] = row
    return row
end

local function Build()
    win = CreateFrame("Frame", "TinkerwiseCharacterGroupsFrame", UIParent, "BackdropTemplate")
    win:SetSize(480, 480)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetScript("OnHide", function() if bar then CloseBar() end end)
    win:Hide()
    TW:SkinDialog(win, L["Character groups"])
    tinsert(UISpecialFrames, "TinkerwiseCharacterGroupsFrame")

    local intro = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 26, -36)
    intro:SetWidth(428)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["The game mode is detected. Inside a mode, choose a group for each character: tooltips only count the current group, and the windows show it by default."])

    info = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8)

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -96)
    scroll:SetPoint("BOTTOMRIGHT", -40, 54)
    listChild = CreateFrame("Frame", nil, scroll)
    listChild:SetSize(LIST_W, 1)
    scroll:SetScrollChild(listChild)

    bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("BOTTOMLEFT", 26, 18)
    bar:SetPoint("BOTTOMRIGHT", -26, 18)
    bar:SetHeight(28)
    bar:Hide()
    barLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    barLabel:SetPoint("LEFT")
    local ok = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    ok:SetSize(50, 22)
    ok:SetPoint("RIGHT")
    ok:SetText("OK")
    ok:SetScript("OnClick", ConfirmNewGroup)
    barEdit = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    barEdit:SetSize(150, 22)
    barEdit:SetPoint("RIGHT", ok, "LEFT", -8, 0)
    barEdit:SetAutoFocus(false)
    barEdit:SetMaxLetters(24)
    barEdit:SetScript("OnEnterPressed", ConfirmNewGroup)
    barEdit:SetScript("OnEscapePressed", CloseBar)
end

function G.Toggle()
    if not win then Build() end
    if win:IsShown() then return win:Hide() end
    win:Show()
    RefreshWindow()
end

G.Refresh = RefreshWindow

---------------------------------------------------------------------------
-- Menu shared by the characters and bags windows
---------------------------------------------------------------------------

function G.CreateViewMenu(parent, name, width)
    local menu = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(menu, width)
    UIDropDownMenu_Initialize(menu, function()
        local current = ViewedId()
        for _, group in ipairs(ViewableGroups()) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = group.label
            item.checked = group.id == current
            item.func = function()
                viewedId = group.id
                Changed()
            end
            UIDropDownMenu_AddButton(item)
        end
    end)
    return menu
end

-- Opening a window always comes back to the current group.
function G.ResetView()
    if not viewedId then return end
    viewedId = nil
    ns.RefreshCharacterViews()
end

---------------------------------------------------------------------------

function G.Enable(moduleDB)
    db = moduleDB
    db.groupOf = db.groupOf or {} -- character key -> custom group; survives "Forget"
    myKey = ns.CharacterKey()
    -- Older saves have no mode: until they log in, characters take the one of their realm.
    local me = ns.CurrentCharacter()
    for _, c in pairs(db.chars) do
        if not c.mode and c.realm == me.realm then c.mode = me.mode end
    end
end

function G.Disable()
    viewedId = nil
    if win then win:Hide() end
end

TW.commands.groups = function()
    if TW.modules.Bags.active then G.Toggle() else TW:Print(L["the My Characters module is disabled (/tw)."]) end
end
