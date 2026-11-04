-- Alerts: low health (red heartbeat on the screen edges), aggro (slow amber pulse) and
-- low armor (pulsing message). Each alert can be turned on or off on its own.

local _, ns = ...
local L = ns.L
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
    { 12867, L["Alarm"] },
    { 12889, L["High-pitched alarm"] },
    { 416, L["Murloc cry"] },
    { 847, L["Quest failed"] },
    { 8174, L["PvP flag"] },
    { 8959, L["Raid warning"] },
    { 3175, L["Minimap ping"] },
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
TW:CreateMover(frame, function() return db end, L["Armor alert"], DEFAULTS)

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
title:SetText(L["CRITICAL ARMOR"])

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
    value:SetText(format(L["Armor: %d / %d (%d %%)"], eff, base, base > 0 and math.floor(eff / base * 100 + 0.5) or 0))
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
    title = L["Alerts"],
    section = "Combat",
    icon = "Interface\\Icons\\Ability_Warrior_Challange",
    desc = L["Low health: the screen edge beats red like a heart, with a repeating alarm. Aggro: the edge slowly pulses orange, with a single sound. Armor: a red message when an effect drops your armor."],
    defaults = DEFAULTS,
    options = {
        { type = "header", label = L["Low health"] },
        { type = "toggle", key = "lowOn", label = L["Enable"] },
        { type = "slider", key = "lowThreshold", label = L["Health threshold (%)"], min = 10, max = 60, step = 5 },
        { type = "toggle", key = "lowVignette", label = L["Red screen edge"] },
        { type = "toggle", key = "lowSound", label = L["Repeating alert sound"] },
        { type = "select", key = "lowSoundChoice", label = L["Sound (plays when you choose it)"], values = SOUND_CHOICES },
        { type = "toggle", key = "lowPotion", label = L["Flash the Potion Reminder (requires the Potion Reminder module)"] },
        { type = "execute", label = L["Test (4 s)"], func = function()
            lowTestUntil = GetTime() + 4
            CheckAll()
        end },
        { type = "header", label = "Aggro" },
        { type = "toggle", key = "aggroOn", label = L["Enable"] },
        { type = "toggle", key = "aggroGroupOnly", label = L["Only in a group / raid"] },
        { type = "toggle", key = "aggroIgnoreTanks", label = L["Disable for warriors and druids (tanks)"] },
        { type = "toggle", key = "aggroSound", label = L["Play an alert sound"] },
        { type = "select", key = "aggroSoundChoice", label = L["Sound (plays when you choose it)"], values = SOUND_CHOICES },
        { type = "execute", label = L["Test (3 s)"], func = function()
            aggroTestUntil = GetTime() + 3
            CheckAll()
        end },
        { type = "header", label = L["Armor"] },
        { type = "toggle", key = "armorOn", label = L["Enable"] },
        { type = "slider", key = "armorRatio", label = L["Alert threshold (% of normal armor)"], min = 10, max = 90, step = 5 },
        { type = "toggle", key = "armorSound", label = L["Play an alert sound"] },
        { type = "select", key = "armorAlarm", label = L["Sound (plays when you choose it)"], values = SOUND_CHOICES },
        { type = "execute", label = L["Test (4 s)"], func = function()
            armorTestUntil = GetTime() + 4
            if db and db.armorSound then PlaySound(db.armorAlarm, "Master") end
            CheckAll()
        end },
        { type = "execute", label = L["Move / Lock"], func = function()
            frame:ToggleMover()
            CheckAll()
        end },
        { type = "execute", label = L["Reset position"], func = function() frame:ResetPosition() end },
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
