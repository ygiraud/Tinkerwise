-- StatDelta: shows stat changes (+/-) when gear, buffs, forms or talents change, and a summary
-- panel on level up. The spells to learn come from the What's Training? addon, when installed.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetCoinTextureString = ns.API.GetCoinTextureString

local DEFAULTS = {
    point = "CENTER", x = 250, y = 50,
    hold = 4,        -- seconds a line stays fully visible
    fade = 1,        -- seconds of fade out
    size = 16,       -- font size
    maxLines = 14,
    chat = false,    -- also print changes to chat
    hidePrimary = false,   -- only show derived stats (no strength, agility...)
    muteSwap = true,       -- weapon swaps in combat show nothing
    levelUp = true,        -- summary panel on level up
    levelSpells = true,    -- list the spells to learn in that panel
    levelHold = 20,        -- seconds the panel stays fully visible
}

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------

local STAT_NAMES = {
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
    STAT_NAMES = {
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
    STATS[#STATS + 1] = { key = "DMG_" .. school, label = format(STAT_NAMES.SCHOOLDMG, STAT_NAMES[school]) }
end
for i, school in ipairs(SCHOOLS) do
    if school ~= "HOLY" then
        STATS[#STATS + 1] = { key = "RES_" .. school, label = format(STAT_NAMES.RESIST, STAT_NAMES[school]) }
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
TW:CreateMover(frame, function() return db end, L["Stat Changes - drag me"], DEFAULTS)

-- Gold "STATISTICS" header with a fading underline, shown while lines are visible.
local header = frame:CreateFontString(nil, "OVERLAY")
header:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE") -- a font must be set before SetText
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, 0)
header:SetTextColor(1, 0.82, 0)
header:SetText(L["STATISTICS"])
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
    local label = def.label or STAT_NAMES[def.key]
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
-- Level-up panel. It grows above the list, so stat lines can still appear below it.
---------------------------------------------------------------------------

local PANEL_WIDTH, COLUMN_WIDTH, STAT_ROW, SPELL_ROW, MAX_SPELLS = 400, 190, 18, 22, 8
local GOOD, BAD = "|cff33ff33", "|cffff4040"

local panel = CreateFrame("Frame", nil, frame)
panel:SetWidth(PANEL_WIDTH)
panel:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 8)
panel:SetClampedToScreen(true)
panel:Hide()

local panelBg = panel:CreateTexture(nil, "BACKGROUND")
panelBg:SetAllPoints()
panelBg:SetColorTexture(0, 0, 0, 0.65)

local function PanelText(size, r, g, b)
    local text = panel:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    text:SetTextColor(r, g, b)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local levelTitle = PanelText(26, 1, 0.82, 0)
levelTitle:SetPoint("TOPLEFT", 12, -10)

local panelRule = panel:CreateTexture(nil, "ARTWORK")
panelRule:SetHeight(1)
panelRule:SetPoint("TOPLEFT", 10, -42)
panelRule:SetPoint("TOPRIGHT", -10, -42)
panelRule:SetColorTexture(1, 0.82, 0, 0.7)

local trainTitle = PanelText(13, 1, 0.82, 0)
local trainCost = PanelText(13, 1, 1, 1)
local moreSpells = PanelText(12, 0.7, 0.7, 0.7)
local statCells, spellRows = {}, {}

-- Unlearned class spells the player can buy now, newest first. Empty without What's Training?.
local function TrainableSpells()
    local api = _G.WT_API
    if not db.levelSpells or not api or not api.IsReady() then return {}, 0 end
    local ok, spells = pcall(api.GetSpells)
    if not ok then return {}, 0 end
    local list, total = {}, 0
    for _, spell in ipairs(spells) do
        if spell.status == api.Status.AVAILABLE and spell.name and not spell.quest and not spell.isItem then
            list[#list + 1] = spell
            total = total + (spell.cost or 0)
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return list, total
end

local function SpellLabel(spell)
    local rank = spell.subText
    if rank and rank ~= "" then return spell.name .. " (" .. rank .. ")" end
    return spell.name
end

local function ShowLevelUp(level, changes)
    panel:SetScale(math.max(0.7, math.min(1.5, db.size / 16)))
    levelTitle:SetText(format(L["LEVEL %d"], level))

    local y = -50
    for i, change in ipairs(changes) do
        local def, d = change[1], change[2]
        local cell = statCells[i]
        if not cell then
            cell = PanelText(13, 0.92, 0.92, 0.85)
            cell:SetWidth(COLUMN_WIDTH - 8)
            statCells[i] = cell
        end
        local good = (d > 0) ~= (def.inverse == true)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", 12 + (i - 1) % 2 * COLUMN_WIDTH, y - math.floor((i - 1) / 2) * STAT_ROW)
        cell:SetText((good and GOOD or BAD) .. FormatDelta(def, d) .. "|r " .. (def.label or STAT_NAMES[def.key]))
        cell:Show()
    end
    for i = #changes + 1, #statCells do statCells[i]:Hide() end
    y = y - math.ceil(#changes / 2) * STAT_ROW

    local spells, total = TrainableSpells()
    local hasSpells = #spells > 0
    trainTitle:SetShown(hasSpells)
    trainCost:SetShown(hasSpells)
    if hasSpells then
        y = y - 10
        trainTitle:ClearAllPoints()
        trainTitle:SetPoint("TOPLEFT", 12, y)
        trainTitle:SetText(format(L["To learn from your class trainer (%d)"], #spells))
        trainCost:ClearAllPoints()
        trainCost:SetPoint("TOPRIGHT", -12, y)
        trainCost:SetText(GetCoinTextureString(total))
        y = y - 22
    end

    local shown = math.min(#spells, MAX_SPELLS)
    for i = 1, shown do
        local spell = spells[i]
        local row = spellRows[i]
        if not row then
            row = { icon = panel:CreateTexture(nil, "ARTWORK"), text = PanelText(13, 1, 1, 1) }
            row.icon:SetSize(18, 18)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetWidth(PANEL_WIDTH - 48)
            spellRows[i] = row
        end
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", 12, y)
        row.icon:SetTexture(spell.icon)
        row.text:SetText(SpellLabel(spell))
        -- Spells unlocked by this level stand out from the ones still waiting.
        if spell.level == level then
            row.text:SetTextColor(1, 1, 1)
        else
            row.text:SetTextColor(0.65, 0.65, 0.65)
        end
        row.icon:Show()
        row.text:Show()
        y = y - SPELL_ROW
    end
    for i = shown + 1, #spellRows do
        spellRows[i].icon:Hide()
        spellRows[i].text:Hide()
    end

    moreSpells:SetShown(#spells > MAX_SPELLS)
    if #spells > MAX_SPELLS then
        moreSpells:ClearAllPoints()
        moreSpells:SetPoint("TOPLEFT", 12, y)
        moreSpells:SetText(format(L["+%d more"], #spells - MAX_SPELLS))
        y = y - 18
    end

    panel:SetHeight(-y + 8)
    panel.t = 0
    panel:SetAlpha(1)
    panel:Show()

    if db.chat then
        print("|cffffd100" .. format(L["LEVEL %d"], level) .. "|r")
        for _, change in ipairs(changes) do
            local def, d = change[1], change[2]
            local good = (d > 0) ~= (def.inverse == true)
            print((good and GOOD or BAD) .. FormatDelta(def, d) .. "|r " .. (def.label or STAT_NAMES[def.key]))
        end
        if hasSpells then
            print("|cffffd100" .. format(L["To learn from your class trainer (%d)"], #spells) .. "|r " .. GetCoinTextureString(total))
            for _, spell in ipairs(spells) do print(spell.link or SpellLabel(spell)) end
        end
    end
end

-- Mouse over the panel: it stays fully visible.
panel:SetScript("OnUpdate", function(self, elapsed)
    self.t = self:IsMouseOver() and math.min(self.t, db.levelHold) or self.t + elapsed
    if self.t >= db.levelHold + db.fade then
        self:Hide()
    elseif self.t > db.levelHold then
        self:SetAlpha(1 - (self.t - db.levelHold) / db.fade)
    else
        self:SetAlpha(1)
    end
end)

---------------------------------------------------------------------------
-- Change detection
---------------------------------------------------------------------------

local last, ready, pending, levelPending
local muteUntil = 0
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }
local LEVEL_UP_DELAY = 1.5 -- stats and What's Training? both need a moment after the event

local function ComputeChanges(before, now)
    local changes = {}
    for _, def in ipairs(STATS) do
        local old, new = before[def.key], now[def.key]
        if old and new and not (def.primary and db.hidePrimary) then
            local d = new - old
            local threshold = def.pct and 0.005 or def.dec2 and 0.005 or 0.05
            if math.abs(d) >= threshold then changes[#changes + 1] = { def, d, old } end
        end
    end
    return changes
end

local function FinishLevelUp()
    local level = levelPending
    levelPending = nil
    if not level or not ready then return end
    local now = Snapshot()
    ShowLevelUp(level, ComputeChanges(last, now))
    last = now
end

local function Update()
    pending = false
    -- During a level up the baseline is kept, so every gain lands in the panel.
    if not ready or levelPending then return end
    local now = Snapshot()
    -- Weapon swapped in combat: silently take the new values as baseline.
    if GetTime() < muteUntil then
        last = now
        return
    end
    local changes = ComputeChanges(last, now)
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
    if event == "PLAYER_LEVEL_UP" and db.levelUp then
        levelPending = arg1
        C_Timer.After(LEVEL_UP_DELAY, FinishLevelUp)
    elseif event == "PLAYER_ENTERING_WORLD" then
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
    title = L["Stat Changes"],
    icon = "Interface\\Icons\\Spell_Nature_Strength",
    section = L["Character"],
    desc = L["Shows stat gains and losses when you change gear, gain or lose a buff, or change form or talents. On level up, sums up your gains and the spells to learn."],
    defaults = DEFAULTS,
    options = {
        { type = "slider", key = "size", label = L["Text size"], min = 8, max = 40, step = 1 },
        { type = "slider", key = "hold", label = L["Display duration (s)"], min = 1, max = 15, step = 0.5 },
        { type = "slider", key = "maxLines", label = L["Maximum lines"], min = 3, max = 30, step = 1 },
        { type = "toggle", key = "chat", label = L["Also write changes to chat"] },
        { type = "toggle", key = "hidePrimary", label = L["Hide strength, agility, stamina, intellect, spirit"] },
        { type = "toggle", key = "muteSwap", label = L["Ignore weapon swaps in combat"] },
        { type = "toggle", key = "levelUp", label = L["Summary panel on level up"] },
        { type = "toggle", key = "levelSpells", label = L["List the spells to learn (requires What's Training?)"] },
        { type = "slider", key = "levelHold", label = L["Level-up panel duration (s)"], min = 5, max = 60, step = 5 },
        { type = "execute", label = L["Test"], func = function()
            ShowDelta({ key = "HEALTH" }, 15, 115)
            ShowDelta({ key = "MANA" }, 26, 216)
            ShowDelta({ key = "MP5", dec = true }, 2.5, 31)
            ShowDelta({ key = "INT" }, 1, 25)
            ShowDelta({ key = "SPI" }, -2, 25)
        end },
        { type = "execute", label = L["Test level up"], func = function()
            ShowLevelUp(UnitLevel("player"), {
                { { key = "STA" }, 2 }, { { key = "INT" }, 1 }, { { key = "SPI" }, 1 },
                { { key = "HEALTH" }, 24 }, { { key = "MANA" }, 19 },
                { { key = "SCRIT", pct = true }, 0.04 },
            })
        end },
        { type = "execute", label = L["Move / Lock"], func = function() frame:ToggleMover() end },
        { type = "execute", label = L["Reset position"], func = function() frame:ResetPosition() end },
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
    levelPending = nil
    panel:Hide()
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
