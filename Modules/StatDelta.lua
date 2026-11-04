-- StatDelta: shows stat changes (+/-) when gear, buffs, forms, talents or level change.

local _, ns = ...
local TW = ns.TW

local DEFAULTS = {
    point = "CENTER", x = 250, y = 50,
    hold = 4,        -- seconds a line stays fully visible
    fade = 1,        -- seconds of fade out
    size = 16,       -- font size
    maxLines = 14,
    chat = false,    -- also print changes to chat
    hidePrimary = false,   -- only show derived stats (no strength, agility...)
    muteSwap = true,       -- weapon swaps in combat show nothing
}

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------

local L = {
    STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
    HEALTH = "Health", MANA = "Mana", ARMOR = "Armor", DEFENSE = "Defense",
    AP = "Attack Power", RAP = "Ranged Attack Power", DPS = "Main Hand DPS",
    CRIT = "Crit", RCRIT = "Ranged Crit", SCRIT = "Spell Crit",
    HIT = "Hit", SHIT = "Spell Hit",
    DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", BLOCKV = "Block Value",
    SPEED = "Attack Speed", OSPEED = "Off Hand Speed", RSPEED = "Ranged Speed", RUN = "Movement Speed",
    SPELLDMG = "Spell Damage", HEAL = "Healing", MP5 = "Mana per 5s",
    HOLY = "Holy", FIRE = "Fire", NATURE = "Nature", FROST = "Frost", SHADOW = "Shadow", ARCANE = "Arcane",
    RESIST = "%s Resistance", SCHOOLDMG = "%s Damage",
}

if GetLocale() == "frFR" then
    L = {
        STR = "Force", AGI = "Agilité", STA = "Endurance", INT = "Intelligence", SPI = "Esprit",
        HEALTH = "Vie", MANA = "Mana", ARMOR = "Armure", DEFENSE = "Défense",
        AP = "Puissance d'attaque", RAP = "Puissance d'attaque à distance", DPS = "DPS main droite",
        CRIT = "Critique", RCRIT = "Critique à distance", SCRIT = "Critique des sorts",
        HIT = "Toucher", SHIT = "Toucher des sorts",
        DODGE = "Esquive", PARRY = "Parade", BLOCK = "Blocage", BLOCKV = "Valeur de blocage",
        SPEED = "Vitesse d'attaque", OSPEED = "Vitesse main gauche", RSPEED = "Vitesse à distance",
        RUN = "Vitesse de déplacement",
        SPELLDMG = "Dégâts des sorts", HEAL = "Soins", MP5 = "Mana toutes les 5 s",
        HOLY = "Sacré", FIRE = "Feu", NATURE = "Nature", FROST = "Givre", SHADOW = "Ombre", ARCANE = "Arcanes",
        RESIST = "Résistance (%s)", SCHOOLDMG = "Dégâts (%s)",
    }
end

---------------------------------------------------------------------------
-- Stat definitions (display order). pct = shown as a percentage, primary = base attribute,
-- inverse = lower is better (attack speeds, in seconds between swings), unit = suffix.
---------------------------------------------------------------------------

local SCHOOLS = { "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" } -- spell schools 2..7, resist ids 1..6

local STATS = {
    { key = "STR", primary = true }, { key = "AGI", primary = true }, { key = "STA", primary = true },
    { key = "INT", primary = true }, { key = "SPI", primary = true },
    { key = "HEALTH" }, { key = "MANA" }, { key = "ARMOR" }, { key = "DEFENSE" },
    { key = "AP" }, { key = "RAP" }, { key = "DPS", dec = true },
    { key = "SPEED", dec2 = true, inverse = true, unit = " s" },
    { key = "OSPEED", dec2 = true, inverse = true, unit = " s" },
    { key = "RSPEED", dec2 = true, inverse = true, unit = " s" },
    { key = "CRIT", pct = true }, { key = "RCRIT", pct = true }, { key = "HIT", pct = true },
    { key = "SPELLDMG" }, { key = "HEAL" }, { key = "SCRIT", pct = true }, { key = "SHIT", pct = true },
    { key = "MP5", dec = true },
    { key = "DODGE", pct = true }, { key = "PARRY", pct = true }, { key = "BLOCK", pct = true },
    { key = "BLOCKV" },
    { key = "RUN", unit = " %", noRel = true },
}
for i, school in ipairs(SCHOOLS) do
    STATS[#STATS + 1] = { key = "DMG_" .. school, label = format(L.SCHOOLDMG, L[school]) }
end
for i, school in ipairs(SCHOOLS) do
    if school ~= "HOLY" then
        STATS[#STATS + 1] = { key = "RES_" .. school, label = format(L.RESIST, L[school]) }
    end
end

-- Call a possibly missing API safely.
local function try(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function Snapshot()
    local s = {}
    local primary = { "STR", "AGI", "STA", "INT", "SPI" }
    for i = 1, 5 do
        local _, effective = UnitStat("player", i)
        s[primary[i]] = effective
    end

    s.HEALTH = UnitHealthMax("player")
    s.MANA = UnitPowerMax("player", 0)
    s.ARMOR = select(2, UnitArmor("player"))
    local defBase, defMod = try(UnitDefense, "player")
    if defBase then s.DEFENSE = defBase + (defMod or 0) end

    local base, pos, neg = UnitAttackPower("player")
    s.AP = base + pos + neg
    base, pos, neg = try(UnitRangedAttackPower, "player")
    if base then s.RAP = base + pos + neg end

    local minDmg, maxDmg = UnitDamage("player")
    local speed, offSpeed = UnitAttackSpeed("player")
    if minDmg and speed and speed > 0 then s.DPS = (minDmg + maxDmg) / 2 / speed end
    s.SPEED = speed
    if offSpeed and offSpeed > 0 then s.OSPEED = offSpeed end
    local rangedSpeed, _, rangedHi = try(UnitRangedDamage, "player")
    if rangedHi and rangedHi > 0 then s.RSPEED = rangedSpeed end

    s.BLOCKV = try(GetShieldBlock)
    -- Max run speed (mounts, Sprint...) as % of normal speed (7 yd/s).
    local _, runSpeed = try(GetUnitSpeed, "player")
    if runSpeed and runSpeed > 0 then s.RUN = math.floor(runSpeed / 7 * 100 + 0.5) end

    s.CRIT = try(GetCritChance)
    s.RCRIT = try(GetRangedCritChance)
    s.HIT = try(GetHitModifier) or 0
    s.SHIT = try(GetSpellHitModifier) or 0
    s.DODGE = try(GetDodgeChance)
    s.PARRY = try(GetParryChance)
    s.BLOCK = try(GetBlockChance)
    s.HEAL = try(GetSpellBonusHealing)

    -- Generic spell damage = lowest school bonus; per-school extra shown separately.
    local minSchool, maxCrit
    local dmg = {}
    for i, school in ipairs(SCHOOLS) do
        dmg[school] = try(GetSpellBonusDamage, i + 1) or 0
        minSchool = math.min(minSchool or dmg[school], dmg[school])
        local crit = try(GetSpellCritChance, i + 1)
        if crit then maxCrit = math.max(maxCrit or crit, crit) end
    end
    s.SPELLDMG = minSchool
    s.SCRIT = maxCrit
    for _, school in ipairs(SCHOOLS) do
        s["DMG_" .. school] = dmg[school] - minSchool
    end

    for i, school in ipairs(SCHOOLS) do
        if school ~= "HOLY" then
            s["RES_" .. school] = select(2, UnitResistance("player", i))
        end
    end

    local _, casting = try(GetManaRegen)
    if casting then s.MP5 = casting * 5 end

    return s
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local db
local frame = CreateFrame("Frame", "TinkerwiseStatDeltaFrame", UIParent)
frame:Hide()
frame:SetSize(220, 20)
TW:CreateMover(frame, function() return db end, "StatDelta - drag me", DEFAULTS)

-- Gold "STATISTICS" header with a fading underline, shown while lines are visible.
local header = frame:CreateFontString(nil, "OVERLAY")
header:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE") -- a font must be set before SetText
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, 0)
header:SetTextColor(1, 0.82, 0)
header:SetText(GetLocale() == "frFR" and "STATISTIQUES" or "STATISTICS")
header:Hide()

local rule = frame:CreateTexture(nil, "ARTWORK")
rule:SetHeight(1)
rule:SetWidth(260)
rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -4)
rule:SetColorTexture(1, 0.82, 0, 0.7)
if CreateColor then
    pcall(rule.SetGradient, rule, "HORIZONTAL", CreateColor(1, 0.82, 0, 0.9), CreateColor(1, 0.82, 0, 0))
end
rule:Hide()

local pool, active = {}, {}

local function Layout()
    header:SetFont(STANDARD_TEXT_FONT, math.floor(db.size * 0.8), "OUTLINE")
    local top = -(db.size * 0.8 + 12)
    for i, line in ipairs(active) do
        line.num:ClearAllPoints()
        line.num:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, top - (i - 1) * (db.size + 6))
    end
end

local function SetLineAlpha(line, a)
    line.num:SetAlpha(a)
    line.label:SetAlpha(a)
end

local function Release(index)
    local line = table.remove(active, index)
    line.num:Hide()
    line.label:Hide()
    pool[#pool + 1] = line
end

local function AddLine(numText, labelText, r, g, b)
    local line = table.remove(pool)
    if not line then
        line = { num = frame:CreateFontString(nil, "OVERLAY"), label = frame:CreateFontString(nil, "OVERLAY") }
        line.label:SetPoint("BOTTOMLEFT", line.num, "BOTTOMRIGHT", 6, 1)
    end
    line.num:SetFont(STANDARD_TEXT_FONT, db.size + 4, "OUTLINE")
    line.label:SetFont(STANDARD_TEXT_FONT, db.size - 2, "OUTLINE")
    line.num:SetText(numText)
    line.num:SetTextColor(r, g, b)
    line.label:SetText(labelText)
    line.label:SetTextColor(0.92, 0.92, 0.85)
    line.t = 0
    SetLineAlpha(line, 1)
    line.num:Show()
    line.label:Show()
    table.insert(active, 1, line)
    while #active > db.maxLines do Release(#active) end
    header:Show(); header:SetAlpha(1)
    rule:Show(); rule:SetAlpha(1)
    Layout()
end

frame:SetScript("OnUpdate", function(_, elapsed)
    if #active == 0 then return end
    -- Mouse over the list: lines stay fully visible.
    local height = db.size * 0.8 + 12 + #active * (db.size + 6)
    local hovered = frame:IsMouseOver(0, -(height - frame:GetHeight()), 0, 200)
    local removed, maxAlpha = false, 0
    for i = #active, 1, -1 do
        local line = active[i]
        line.t = hovered and math.min(line.t, db.hold) or line.t + elapsed
        if line.t >= db.hold + db.fade then
            Release(i)
            removed = true
        else
            local a = line.t > db.hold and 1 - (line.t - db.hold) / db.fade or 1
            SetLineAlpha(line, a)
            maxAlpha = math.max(maxAlpha, a)
        end
    end
    if #active == 0 then
        header:Hide(); rule:Hide()
    else
        header:SetAlpha(maxAlpha); rule:SetAlpha(maxAlpha)
    end
    if removed then Layout() end
end)

local function FormatDelta(def, d)
    if def.pct then return format("%+.2f%%", d) end
    if def.dec2 then return format("%+.2f", d) .. (def.unit or "") end
    if def.dec or math.abs(d - math.floor(d + 0.5)) > 0.05 then return format("%+.1f", d) .. (def.unit or "") end
    return format("%+d", math.floor(d + 0.5)) .. (def.unit or "")
end

local function ShowDelta(def, d, old)
    local num = FormatDelta(def, d)
    local label = def.label or L[def.key]
    -- Relative change, e.g. "(+8%)", for flat stats with a non-zero previous value.
    if not def.pct and not def.noRel and old and old > 0 then
        local rel = d / old * 100
        if math.abs(rel) >= 0.5 then label = format("%s (%+.0f%%)", label, rel) end
    end
    -- Green = good for you: for attack speeds a lower value means faster swings.
    local good = (d > 0) ~= (def.inverse == true)
    if good then
        AddLine(num, label, 0.2, 1, 0.2)
    else
        AddLine(num, label, 1, 0.25, 0.25)
    end
    if db.chat then
        print((good and "|cff33ff33" or "|cffff4040") .. num .. "|r " .. label)
    end
end

---------------------------------------------------------------------------
-- Change detection
---------------------------------------------------------------------------

local last, ready, pending
local muteUntil = 0
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }

local function Update()
    pending = false
    if not ready then return end
    local now = Snapshot()
    -- Weapon swapped in combat: silently take the new values as baseline.
    if GetTime() < muteUntil then
        last = now
        return
    end
    local changes = {}
    for _, def in ipairs(STATS) do
        local old, new = last[def.key], now[def.key]
        if old and new and not (def.primary and db.hidePrimary) then
            local d = new - old
            local threshold = def.pct and 0.005 or def.dec2 and 0.005 or 0.05
            if math.abs(d) >= threshold then changes[#changes + 1] = { def, d, old } end
        end
    end
    -- Insert in reverse so the first stat ends up on top.
    for i = #changes, 1, -1 do ShowDelta(changes[i][1], changes[i][2], changes[i][3]) end
    last = now
end

-- Gear swaps and buffs fire bursts of events; coalesce them into one diff.
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.25, Update)
end

local events = CreateFrame("Frame")

local UNIT_EVENTS = {
    "UNIT_STATS", "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "UNIT_RESISTANCES",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_MAXHEALTH", "UNIT_MAXPOWER",
    "UNIT_DAMAGE", "UNIT_ATTACK_SPEED", "UNIT_DEFENSE",
}
local GLOBAL_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "UPDATE_SHAPESHIFT_FORM", "CHARACTER_POINTS_CHANGED",
    "PLAYER_LEVEL_UP", "PLAYER_DAMAGE_DONE_MODS", "SPELL_POWER_CHANGED", "COMBAT_RATING_UPDATE",
}

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" and db.muteSwap and WEAPON_SLOTS[arg1] and InCombatLockdown() then
        muteUntil = GetTime() + 1
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Stats are unreliable right after a loading screen; take a silent baseline.
        ready = false
        C_Timer.After(2, function()
            last = Snapshot()
            ready = true
        end)
    else
        Schedule()
    end
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local function ClearLines()
    while #active > 0 do Release(#active) end
    header:Hide(); rule:Hide()
end

local mod = TW:NewModule("StatDelta", {
    title = "Changements de stats",
    icon = "Interface\\Icons\\Spell_Nature_Strength",
    section = "Personnage",
    desc = "Affiche les gains et pertes de stats quand vous changez d'équipement, recevez ou perdez un buff, changez de forme ou de talents.",
    defaults = DEFAULTS,
    options = {
        { type = "slider", key = "size", label = "Taille du texte", min = 8, max = 40, step = 1 },
        { type = "slider", key = "hold", label = "Durée d'affichage (s)", min = 1, max = 15, step = 0.5 },
        { type = "slider", key = "maxLines", label = "Nombre de lignes max", min = 3, max = 30, step = 1 },
        { type = "toggle", key = "chat", label = "Écrire aussi les changements dans le chat" },
        { type = "toggle", key = "hidePrimary", label = "Masquer force, agilité, endurance, intelligence, esprit" },
        { type = "toggle", key = "muteSwap", label = "Ignorer les changements d'arme en combat" },
        { type = "execute", label = "Tester", func = function()
            ShowDelta({ key = "HEALTH" }, 15, 115)
            ShowDelta({ key = "MANA" }, 26, 216)
            ShowDelta({ key = "MP5", dec = true }, 2.5, 31)
            ShowDelta({ key = "INT" }, 1, 25)
            ShowDelta({ key = "SPI" }, -2, 25)
        end },
        { type = "execute", label = "Déplacer / Verrouiller", func = function() frame:ToggleMover() end },
        { type = "execute", label = "Réinitialiser la position", func = function() frame:ResetPosition() end },
    },
})

function mod:OnEnable()
    db = self.db
    frame:ApplyPosition()
    frame:Show()
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    for _, e in ipairs(UNIT_EVENTS) do pcall(events.RegisterUnitEvent, events, e, "player") end
    for _, e in ipairs(GLOBAL_EVENTS) do pcall(events.RegisterEvent, events, e) end
    -- Enabled from the config window while in world: take a baseline now.
    last = Snapshot()
    ready = true
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    ready = false
    frame:Lock()
    ClearLines()
    frame:Hide()
end

function mod:SetEditMode(on)
    frame:SetUnlocked(on)
end

function mod:OnOptionChanged()
    while #active > db.maxLines do Release(#active) end
    if #active > 0 then
        for _, line in ipairs(active) do
            line.num:SetFont(STANDARD_TEXT_FONT, db.size + 4, "OUTLINE")
            line.label:SetFont(STANDARD_TEXT_FONT, db.size - 2, "OUTLINE")
        end
        Layout()
    end
end
