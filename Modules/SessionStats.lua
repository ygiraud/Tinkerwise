-- SessionStats: small panel with what this play session brought: time played, XP and XP per
-- hour, estimated time to level, gold won or lost, kills and quests turned in.

local _, ns = ...
local TW = ns.TW

local DEFAULTS = {
    showWindow = true,
    hideAtMax = true,   -- hide the XP lines at max level
    point = "TOPRIGHT", x = -200, y = -200,
}

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD = { 1, 0.82, 0 }

local db
local session = {}

local function ResetSession()
    session.start = GetTime()
    session.xp = 0
    session.lastXP = UnitXP("player")
    session.lastMax = UnitXPMax("player")
    session.money = GetMoney()
    session.kills = 0
    session.quests = 0
end

local function AtMaxLevel()
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    return UnitLevel("player") >= max
end

local function FormatTime(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then return "-" end
    seconds = math.floor(seconds)
    local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if h > 0 then return format("%d h %02d min", h, m) end
    return format("%d min %02d s", m, seconds % 60)
end

local function FormatNumber(n)
    local s = tostring(math.floor(n + 0.5))
    return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local panel = CreateFrame("Frame", "TinkerwiseSessionFrame", UIParent, "BackdropTemplate")
panel:SetSize(220, 60)
panel:SetFrameStrata("MEDIUM")
panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.06, 0.04, 0.02, 0.85)
panel:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
panel:Hide()
TW:CreateMover(panel, function() return db end, "Session", DEFAULTS)

local title = panel:CreateFontString(nil, "OVERLAY")
title:SetFont(TITLE_FONT, 17, "")
title:SetTextColor(1, 0.9, 0.7)
title:SetPoint("TOPLEFT", 12, -9)
title:SetText("Session")

local rule = panel:CreateTexture(nil, "ARTWORK")
rule:SetHeight(1)
rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
rule:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)

local lines = {}
local function Line(i)
    if lines[i] then return lines[i] end
    local l = {}
    l.label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.label:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 15)
    l.value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.value:SetPoint("TOPRIGHT", -12, -34 - (i - 1) * 15)
    l.value:SetJustifyH("RIGHT")
    lines[i] = l
    return l
end

local function Refresh()
    if not db or not panel:IsShown() then return end
    local elapsed = GetTime() - session.start
    local rows = { { "Durée", FormatTime(elapsed) } }

    if not (db.hideAtMax and AtMaxLevel()) then
        local perHour = elapsed > 0 and session.xp / elapsed * 3600 or 0
        local missing = UnitXPMax("player") - UnitXP("player")
        rows[#rows + 1] = { "XP gagnée", FormatNumber(session.xp) }
        rows[#rows + 1] = { "XP / heure", FormatNumber(perHour) }
        rows[#rows + 1] = { "Niveau suivant", session.xp > 0 and FormatTime(missing / session.xp * elapsed) or "-" }
    end

    local diff = GetMoney() - session.money
    local money = diff >= 0 and ("|cff33ff33+|r " .. GetCoinTextureString(diff))
        or ("|cffff4040-|r " .. GetCoinTextureString(-diff))
    rows[#rows + 1] = { "Or", money }
    rows[#rows + 1] = { "Monstres tués", session.kills }
    rows[#rows + 1] = { "Quêtes rendues", session.quests }

    for i, row in ipairs(rows) do
        local l = Line(i)
        l.label:SetText(row[1])
        l.value:SetText(row[2])
        l.label:Show()
        l.value:Show()
    end
    for i = #rows + 1, #lines do
        lines[i].label:Hide()
        lines[i].value:Hide()
    end
    panel:SetHeight(42 + #rows * 15)
end

C_Timer.NewTicker(1, Refresh)

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_XP_UPDATE" then
        local xp, max = UnitXP("player"), UnitXPMax("player")
        if max == session.lastMax then
            session.xp = session.xp + math.max(xp - session.lastXP, 0)
        else
            -- level up: rest of the previous level + progress in the new one
            session.xp = session.xp + (session.lastMax - session.lastXP) + xp
        end
        session.lastXP, session.lastMax = xp, max
    elseif event == "QUEST_TURNED_IN" then
        session.quests = session.quests + 1
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceGUID = CombatLogGetCurrentEventInfo()
        if subEvent == "PARTY_KILL" and sourceGUID == UnitGUID("player") then
            session.kills = session.kills + 1
        end
        return
    end
    Refresh()
end)

local function ApplyShown()
    panel:SetShown(db.showWindow or panel:IsUnlocked())
    Refresh()
end

local mod = TW:NewModule("SessionStats", {
    title = "Suivi de session",
    section = "Personnage",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    desc = "Petit panneau qui affiche depuis la connexion : durée de jeu, XP gagnée, XP par heure, temps estimé avant le niveau suivant, or gagné ou perdu, monstres tués et quêtes rendues.",
    defaults = DEFAULTS,
    defaultEnabled = false,
    options = {
        { type = "toggle", key = "showWindow", label = "Afficher le panneau" },
        { type = "toggle", key = "hideAtMax", label = "Masquer l'XP au niveau maximum" },
        { type = "execute", label = "Nouvelle session", func = function()
            ResetSession()
            Refresh()
            TW:Print("nouvelle session commencée.")
        end },
        { type = "execute", label = "Déplacer / Verrouiller", func = function()
            panel:ToggleMover()
            ApplyShown()
        end },
        { type = "execute", label = "Réinitialiser la position", func = function() panel:ResetPosition() end },
    },
})

function mod:OnEnable()
    db = self.db
    if not session.start then ResetSession() end
    panel:ApplyPosition()
    events:RegisterEvent("PLAYER_XP_UPDATE")
    events:RegisterEvent("PLAYER_MONEY")
    events:RegisterEvent("QUEST_TURNED_IN")
    events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ApplyShown()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    panel:Lock()
    panel:Hide()
end

function mod:OnOptionChanged()
    ApplyShown()
end

function mod:SetEditMode(on)
    panel:SetUnlocked(on)
    ApplyShown()
end
