-- WeaponSkills: follows weapon skills (they cap at level x 5) in a movable panel with skill bars.

local _, ns = ...
local TW = ns.TW

local DEFAULTS = {
    point = "CENTER", x = -300, y = 0,
}

-- Localized names of the weapon skills header.
local WEAPON_HEADERS = {
    ["Weapon Skills"] = true, ["Compétences d'arme"] = true, ["Armes"] = true,
    ["Waffenfertigkeiten"] = true, ["Habilidades con armas"] = true,
    ["Compétences d’arme"] = true, ["Compétences d'armes"] = true, ["Compétences d’armes"] = true,
}

-- Class skill lines also follow the level, but they are not weapons.
local CLASS_HEADERS = {
    ["Class Skills"] = true, ["Compétences de classe"] = true,
    ["Klassenfertigkeiten"] = true, ["Habilidades de clase"] = true,
}

-- Talent specs (Combat, Finesse...) appear as skill lines. The name is the first or
-- second value of GetTalentTabInfo depending on the game version.
local function TalentTabNames()
    local names = {}
    for i = 1, GetNumTalentTabs and GetNumTalentTabs() or 0 do
        local a, b = GetTalentTabInfo(i)
        if type(a) == "string" then names[a] = true end
        if type(b) == "string" then names[b] = true end
    end
    return names
end

local db

-- Returns { { name, rank, max } } for weapon skills (and Defense) visible in the skill list.
-- A skill counts as a weapon skill when it sits under a weapon header, or when its max is
-- level x 5 (weapon skills and Defense are the only ones following the level).
-- Skills unticked in the options are left out unless includeIgnored is set.
local function ReadSkills(includeIgnored)
    local ignored = not includeIgnored and db and db.ignored or {}
    local list = {}
    if not (GetNumSkillLines and GetSkillLineInfo) then return list end
    local cap = UnitLevel("player") * 5
    local underWeapons, underClass = false, false
    local specs = TalentTabNames()
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, temp, modifier, maxRank, isAbandonable = GetSkillLineInfo(i)
        if isHeader then
            underWeapons = WEAPON_HEADERS[name] or false
            underClass = CLASS_HEADERS[name] or false
        elseif name and maxRank and maxRank > 1 and not specs[name] and not underClass
            and (underWeapons or (maxRank == cap and not isAbandonable)) and not ignored[name] then
            list[#list + 1] = { name = name, rank = rank + (temp or 0), max = maxRank }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function Color(rank, max)
    if rank < max * 0.5 then return 1, 0.25, 0.25 end
    if rank < max then return 1, 0.63, 0.13 end
    return 0.3, 1, 0.3
end

local function Hex(r, g, b) return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local panel = CreateFrame("Frame", "TinkerwiseWeaponSkillsFrame", UIParent, "BackdropTemplate")
panel:SetSize(240, 60)
panel:SetFrameStrata("MEDIUM")
panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.06, 0.04, 0.02, 0.85)
panel:SetBackdropBorderColor(1, 0.82, 0, 0.9)
panel:Hide()
TW:CreateMover(panel, function() return db end, "Compétences d'arme", DEFAULTS)

local title = panel:CreateFontString(nil, "OVERLAY")
title:SetFont("Fonts\\MORPHEUS.TTF", 16, "")
title:SetTextColor(1, 0.9, 0.7)
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Compétences d'arme")

local bars = {}
local function Bar(i)
    if bars[i] then return bars[i] end
    local b = CreateFrame("StatusBar", nil, panel)
    b:SetSize(216, 14)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", 4, 0)
    b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.value:SetPoint("RIGHT", -4, 0)
    bars[i] = b
    return b
end

local function RefreshPanel()
    if not db then return end
    local skills = ReadSkills()
    local y = -34
    for i, s in ipairs(skills) do
        local b = Bar(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 12, y)
        b:SetMinMaxValues(0, math.max(s.max, 1))
        b:SetValue(s.rank)
        b:SetStatusBarColor(Color(s.rank, s.max))
        b.name:SetText(s.name)
        b.value:SetText(s.rank .. " / " .. s.max)
        b:Show()
        y = y - 17
    end
    for i = #skills + 1, #bars do bars[i]:Hide() end
    panel:SetHeight(-y + 10)
    panel:Show()
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local function PrintLagging(always)
    local lagging = {}
    for _, s in ipairs(ReadSkills()) do
        if s.rank < s.max then lagging[#lagging + 1] = s end
    end
    if #lagging == 0 then
        if always then TW:Print("toutes vos compétences d'arme sont au maximum.") end
        return
    end
    TW:Print(format("%d compétence(s) d'arme en retard :", #lagging))
    for _, s in ipairs(lagging) do
        print(format("   %s%s : %d / %d|r", Hex(Color(s.rank, s.max)), s.name, s.rank, s.max))
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", RefreshPanel)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local mod = TW:NewModule("WeaponSkills", {
    title = "Compétences d'arme",
    section = "Personnage",
    icon = "Interface\\Icons\\INV_Sword_04",
    desc = "Suit vos compétences d'arme (maximum = niveau × 5) : affiche un panneau déplaçable avec une barre par arme (rouge sous 50 %, orange en retard, vert au maximum). Si une catégorie de compétences est repliée dans la fenêtre du jeu, ses lignes ne sont pas lues.",
    defaults = DEFAULTS,
    options = {
        { type = "header", label = "Compétences suivies" },
        { type = "checklist", key = "ignored", items = function()
            local names = {}
            for _, s in ipairs(ReadSkills(true)) do names[#names + 1] = s.name end
            return names
        end },
        { type = "header", label = "Actions" },
        { type = "execute", label = "Lister dans le chat", func = function() PrintLagging(true) end },
        { type = "execute", label = "Déplacer / Verrouiller", func = function()
            panel:ToggleMover()
            if panel:IsUnlocked() then panel:Show() end
            RefreshPanel()
        end },
        { type = "execute", label = "Réinitialiser la position", func = function() panel:ResetPosition() end },
    },
})

function mod:OnEnable()
    db = self.db
    panel:ApplyPosition()
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("SKILL_LINES_CHANGED")
    events:RegisterEvent("CHAT_MSG_SKILL")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    RefreshPanel()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    panel:Lock()
    panel:Hide()
end

function mod:OnOptionChanged()
    RefreshPanel()
end

function mod:SetEditMode(on)
    panel:SetUnlocked(on)
    if on then panel:Show() end
    RefreshPanel()
end
