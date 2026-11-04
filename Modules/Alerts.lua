-- Alerts: low health (red heartbeat on the screen edges), aggro (slow amber pulse) and
-- low armor (pulsing message). Each alert can be turned on or off on its own.

local _, ns = ...
local TW = ns.TW

local DEFAULTS = {
    lowOn = true,
    lowThreshold = 30,     -- % of max health
    lowVignette = true,
    lowSound = true,
    lowSoundChoice = 8959,
    lowPotion = true,      -- flash the potion reminder
    aggroOn = true,
    aggroGroupOnly = true, -- only warn while in a party / raid
    aggroIgnoreTanks = true, -- no warning for warriors and druids (likely tanks)
    aggroSound = true,
    aggroSoundChoice = 8174,
    armorOn = true,
    armorRatio = 30,       -- alert when armor <= ratio % of normal armor
    armorSound = true,
    armorAlarm = 12889,
    point = "CENTER", x = 0, y = 200,
}

local SOUND_CHOICES = {
    { 12867, "Alarme" },
    { 12889, "Alarme aiguë" },
    { 416, "Cri de murloc" },
    { 847, "Échec de quête" },
    { 8174, "Drapeau JcJ" },
    { 8959, "Alerte de raid" },
    { 3175, "Ping de la minicarte" },
}
local LOW_REPEAT = 3   -- seconds between low health sounds
local FLASH_EVERY = 1  -- seconds between potion reminder flashes
local TICK = 0.3

local db
local lastLowSound, lastFlash, lowTestUntil = 0, 0, 0
local aggroActive, aggroTestUntil = false, 0
local armorActive, armorTestUntil = false, 0

local function CreateVignette(name, r, g, b)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:Hide()
    f.tex = f:CreateTexture(nil, "BACKGROUND")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    f.tex:SetBlendMode("ADD")
    f.tex:SetVertexColor(r, g, b)
    f.t = 0
    return f
end

---------------------------------------------------------------------------
-- Low health
---------------------------------------------------------------------------

local lowVignette = CreateVignette("TinkerwiseLowHealthVignette", 1, 0, 0)

-- Heartbeat-like pulse: two quick beats then a pause.
lowVignette:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    local phase = self.t % 1.1
    local beat = (phase < 0.15 and phase / 0.15) or (phase < 0.3 and 1 - (phase - 0.15) / 0.15)
        or (phase < 0.4 and (phase - 0.3) / 0.1 * 0.7) or (phase < 0.6 and 0.7 * (1 - (phase - 0.4) / 0.2)) or 0
    self.tex:SetAlpha(0.25 + 0.6 * beat)
end)

local function CheckLow()
    local max = UnitHealthMax("player")
    local pct = max > 0 and UnitHealth("player") / max * 100 or 100
    local now = GetTime()
    local isLow = (db.lowOn and pct <= db.lowThreshold and not UnitIsDeadOrGhost("player")) or now < lowTestUntil

    lowVignette:SetShown(isLow and db.lowVignette)
    if not isLow then return end
    if db.lowSound and now - lastLowSound >= LOW_REPEAT then
        lastLowSound = now
        PlaySound(db.lowSoundChoice, "Master")
    end
    if db.lowPotion and ns.FlashPotion and now - lastFlash >= FLASH_EVERY then
        lastFlash = now
        ns.FlashPotion(1.5, now < lowTestUntil)
    end
end

---------------------------------------------------------------------------
-- Aggro
---------------------------------------------------------------------------

local aggroVignette = CreateVignette("TinkerwiseAggroVignette", 1, 0.55, 0)

aggroVignette:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    self.tex:SetAlpha(0.35 + 0.25 * math.sin(self.t * 3))
end)

-- Units worth checking: target, mouseover, nameplates and group members' targets.
local function BuildCandidates(prefix, count)
    local list = { "target", "mouseover" }
    for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
    for i = 1, count do list[#list + 1] = prefix .. i .. "target" end
    return list
end
local RAID_CANDIDATES = BuildCandidates("raid", 40)
local PARTY_CANDIDATES = BuildCandidates("party", 4)

local function Candidates()
    return IsInRaid() and RAID_CANDIDATES or PARTY_CANDIDATES
end

local function HasAggro()
    if UnitThreatSituation then
        local status = UnitThreatSituation("player")
        if status and status >= 2 then return true end
    end
    for _, unit in ipairs(Candidates()) do
        if UnitExists(unit) and UnitCanAttack("player", unit) and UnitAffectingCombat(unit)
            and UnitIsUnit(unit .. "target", "player") then
            return true
        end
    end
    return false
end

local function CheckAggro()
    local _, class = UnitClass("player")
    local skip = not db.aggroOn
        or (db.aggroGroupOnly and not IsInGroup())
        or (db.aggroIgnoreTanks and (class == "WARRIOR" or class == "DRUID"))
        or not UnitAffectingCombat("player")
    local aggro = (not skip and HasAggro()) or GetTime() < aggroTestUntil
    if aggro and not aggroActive and db.aggroSound then
        PlaySound(db.aggroSoundChoice, "Master")
    end
    aggroActive = aggro
    aggroVignette:SetShown(aggro)
end

---------------------------------------------------------------------------
-- Low armor
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "TinkerwiseArmorAlertFrame", UIParent)
frame:SetSize(260, 64)
frame:SetFrameStrata("HIGH")
frame:Hide()
TW:CreateMover(frame, function() return db end, "Alerte armure", DEFAULTS)

local glow = frame:CreateTexture(nil, "BACKGROUND")
glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
glow:SetBlendMode("ADD")
glow:SetVertexColor(1, 0.1, 0.1)
glow:SetPoint("TOPLEFT", -30, 20)
glow:SetPoint("BOTTOMRIGHT", 30, -20)

local icon = frame:CreateTexture(nil, "OVERLAY")
icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
icon:SetSize(34, 34)
icon:SetPoint("LEFT", 10, 0)

local title = frame:CreateFontString(nil, "OVERLAY")
title:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
title:SetTextColor(1, 0.2, 0.2)
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
title:SetText("ARMURE CRITIQUE")

local value = frame:CreateFontString(nil, "OVERLAY")
value:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
value:SetTextColor(1, 0.6, 0.6)
value:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

local armorT = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    armorT = armorT + elapsed
    local pulse = 0.65 + 0.35 * math.sin(armorT * 9)
    glow:SetAlpha(0.3 + 0.4 * pulse)
    -- small shake every second or so
    local shake = (armorT % 1.2 < 0.3) and 1.5 or 0
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8 + math.sin(armorT * 61) * shake, 2 + math.cos(armorT * 53) * shake)
    frame:SetAlpha(0.75 + 0.25 * pulse)
end)

local function SetArmorValue(eff, base)
    value:SetText(format("Armure : %d / %d (%d %%)", eff, base, base > 0 and math.floor(eff / base * 100 + 0.5) or 0))
end

local function CheckArmor()
    local base, eff = UnitArmor("player")
    local low = db.armorOn and base and base > 0 and eff <= base * db.armorRatio / 100 and not UnitIsDeadOrGhost("player")

    if low then
        SetArmorValue(eff, base)
        if not armorActive and db.armorSound then PlaySound(db.armorAlarm, "Master") end
        armorActive = true
        frame:Show()
    else
        armorActive = false
        if GetTime() < armorTestUntil or frame:IsUnlocked() then
            SetArmorValue(math.floor((base or 0) * 0.2), base or 0)
            frame:Show()
        else
            frame:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local function CheckAll()
    if not db then return end
    CheckLow()
    CheckAggro()
    CheckArmor()
end

local ticker

local mod = TW:NewModule("Alerts", {
    title = "Alertes",
    section = "Combat",
    icon = "Interface\\Icons\\Ability_Warrior_Challange",
    desc = "Vie basse : le bord de l'écran bat en rouge comme un cœur, avec une alarme répétée. Aggro : le bord pulse lentement en orange, avec un son unique. Armure : message rouge quand un effet fait tomber votre armure.",
    defaults = DEFAULTS,
    options = {
        { type = "header", label = "Vie basse" },
        { type = "toggle", key = "lowOn", label = "Activer" },
        { type = "slider", key = "lowThreshold", label = "Seuil de vie (%)", min = 10, max = 60, step = 5 },
        { type = "toggle", key = "lowVignette", label = "Bord de l'écran rouge" },
        { type = "toggle", key = "lowSound", label = "Son d'alerte répété" },
        { type = "select", key = "lowSoundChoice", label = "Son (joué quand vous le choisissez)", values = SOUND_CHOICES },
        { type = "toggle", key = "lowPotion", label = "Faire clignoter le Rappel potion" },
        { type = "execute", label = "Tester (4 s)", func = function()
            lowTestUntil = GetTime() + 4
            CheckAll()
        end },
        { type = "header", label = "Aggro" },
        { type = "toggle", key = "aggroOn", label = "Activer" },
        { type = "toggle", key = "aggroGroupOnly", label = "Seulement en groupe / raid" },
        { type = "toggle", key = "aggroIgnoreTanks", label = "Désactiver pour les guerriers et druides (tanks)" },
        { type = "toggle", key = "aggroSound", label = "Jouer un son d'alerte" },
        { type = "select", key = "aggroSoundChoice", label = "Son (joué quand vous le choisissez)", values = SOUND_CHOICES },
        { type = "execute", label = "Tester (3 s)", func = function()
            aggroTestUntil = GetTime() + 3
            CheckAll()
        end },
        { type = "header", label = "Armure" },
        { type = "toggle", key = "armorOn", label = "Activer" },
        { type = "slider", key = "armorRatio", label = "Seuil d'alerte (% de l'armure normale)", min = 10, max = 90, step = 5 },
        { type = "toggle", key = "armorSound", label = "Jouer un son d'alerte" },
        { type = "select", key = "armorAlarm", label = "Son (joué quand vous le choisissez)", values = SOUND_CHOICES },
        { type = "execute", label = "Tester (4 s)", func = function()
            armorTestUntil = GetTime() + 4
            if db and db.armorSound then PlaySound(db.armorAlarm, "Master") end
            CheckAll()
        end },
        { type = "execute", label = "Déplacer / Verrouiller", func = function()
            frame:ToggleMover()
            CheckAll()
        end },
        { type = "execute", label = "Réinitialiser la position", func = function() frame:ResetPosition() end },
    },
})

function mod:OnEnable()
    db = self.db
    frame:ApplyPosition()
    ticker = C_Timer.NewTicker(TICK, CheckAll)
    CheckAll()
end

function mod:OnDisable()
    if ticker then ticker:Cancel(); ticker = nil end
    aggroActive, armorActive = false, false
    lowVignette:Hide()
    aggroVignette:Hide()
    frame:Lock()
    frame:Hide()
end

function mod:OnOptionChanged(key)
    if key == "aggroSoundChoice" or key == "lowSoundChoice" or key == "armorAlarm" then PlaySound(db[key], "Master") end
    CheckAll()
end

function mod:SetEditMode(on)
    frame:SetUnlocked(on)
    CheckAll()
end
