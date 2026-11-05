-- PortraitInfo: hovering your player frame shows small badges above the portrait with
-- armor, physical damage reduction, weapon damage / DPS and spell power.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local DEFAULTS = {
    defense = true,  -- armor + damage reduction
    melee = true,    -- weapon damage + DPS (melee or ranged for hunters)
    spell = true,    -- spell power / healing + spell crit
    position = "top", -- side of the player frame: top, bottom, left, right
}

-- Which badges make sense for each class.
local PROFILES = {
    WARRIOR = { melee = true }, ROGUE = { melee = true }, HUNTER = { ranged = true },
    MAGE = { spell = true }, WARLOCK = { spell = true }, PRIEST = { spell = true },
    PALADIN = { melee = true, spell = true }, SHAMAN = { melee = true, spell = true },
    DRUID = { melee = true, spell = true },
}

local db, profile
local GREEN, RED, WHITE, SKY, VIOLET = { 0.3, 1, 0.3 }, { 1, 0.38, 0.38 }, { 1, 1, 1 }, { 0.65, 0.88, 1 }, { 0.8, 0.65, 1 }

local Comma, DamageReduction = ns.Comma, ns.DamageReduction
local issecretvalue = _G.issecretvalue

---------------------------------------------------------------------------
-- Badges
---------------------------------------------------------------------------

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata("HIGH")
holder:SetSize(1, 1)
holder:SetClampedToScreen(true)
holder:Hide()

local function CreateBadge(iconPath)
    return ns.CreateBadge(holder, iconPath)
end

-- Columns, bottom badge first.
local columns = {
    { CreateBadge("Interface\\Icons\\INV_Shield_06"), CreateBadge("Interface\\Icons\\Spell_Holy_DevotionAura") },
    { CreateBadge("Interface\\Icons\\INV_Sword_04"), CreateBadge("Interface\\Icons\\Ability_Warrior_Cleave") },
    { CreateBadge("Interface\\Icons\\Spell_Holy_MagicalSentry"), CreateBadge("Interface\\Icons\\Spell_Fire_FireBolt02") },
}
local armorB, reducB = columns[1][1], columns[1][2]
local dmgB, dpsB = columns[2][1], columns[2][2]
local spellB, scritB = columns[3][1], columns[3][2]

local function Layout()
    -- Each column is as wide as its widest badge, so top badges never overlap the next column.
    local x, height = 0, 22
    for _, col in ipairs(columns) do
        if col[1].on and col[2].on then height = 46 end
        if col[1].on then
            col[1]:ClearAllPoints()
            col[1]:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", x, 0)
            col[2]:ClearAllPoints()
            col[2]:SetPoint("BOTTOMLEFT", col[1], "TOPLEFT", 0, 2)
            local width = col[1]:GetWidth()
            if col[2].on then width = math.max(width, col[2]:GetWidth()) end
            x = x + width + 2
        end
        for _, b in ipairs(col) do b:SetShown(b.on) end
    end
    holder:SetSize(math.max(x - 2, 1), height) -- the block is anchored as a whole
end

local function ApplyPosition()
    holder:ClearAllPoints()
    local position = db.position
    if position == "bottom" then
        holder:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 0, -4)
    elseif position == "left" then
        holder:SetPoint("RIGHT", PlayerFrame, "LEFT", -4, 0)
    elseif position == "right" then
        holder:SetPoint("LEFT", PlayerFrame, "RIGHT", 4, 0)
    else
        holder:SetPoint("BOTTOMLEFT", PlayerPortrait or PlayerFrame, "TOPLEFT", 0, 6)
    end
end

local function AnySecret(...)
    for i = 1, select("#", ...) do
        if issecretvalue(select(i, ...)) then return true end
    end
    return false
end

-- The game can hide these values, in combat for instance: no calculation is possible with them.
local function StatsAreSecret()
    if not issecretvalue then return false end
    return AnySecret(UnitLevel("player"), UnitLevel("target"))
        or AnySecret(UnitArmor("player"))
        or AnySecret(UnitDamage("player"))
        or AnySecret(UnitAttackSpeed("player"))
        or (UnitRangedDamage and AnySecret(UnitRangedDamage("player")))
        or (GetSpellBonusDamage and AnySecret(GetSpellBonusDamage(2)))
        or (GetSpellCritChance and AnySecret(GetSpellCritChance(2)))
        or (GetSpellBonusHealing and AnySecret(GetSpellBonusHealing()))
end

local function Update()
    if StatsAreSecret() then return end -- the last values stay on screen

    for _, col in ipairs(columns) do for _, b in ipairs(col) do b.on = false end end

    -- Attacker level for the reduction: hostile target if any, else yourself.
    local level = UnitLevel("player")
    if UnitExists("target") and UnitCanAttack("player", "target") then
        local tl = UnitLevel("target")
        level = (tl and tl > 0) and tl or level + 10
    end

    if db.defense then
        local _, eff, _, pos, neg = UnitArmor("player")
        local net = (pos or 0) + (neg or 0)
        armorB:Set(eff, net < 0 and RED or net > 0 and GREEN or WHITE)
        reducB:Set("-" .. Comma(DamageReduction(eff, level) * 100) .. L[" % damage"], SKY)
    end

    if db.melee and profile.ranged and UnitRangedDamage then
        local speed, lo, hi = UnitRangedDamage("player")
        if hi and hi > 0 then
            dmgB.icon:SetTexture(GetInventoryItemTexture("player", 18) or "Interface\\Icons\\INV_Weapon_Bow_02")
            dmgB:Set(format("%d - %d", lo, hi), WHITE)
            dpsB:Set(Comma((lo + hi) / 2 / math.max(speed, 0.1)) .. " DPS", WHITE)
        end
    elseif db.melee and profile.melee then
        local lo, hi, offLo, offHi = UnitDamage("player")
        local mh, oh = UnitAttackSpeed("player")
        if lo then
            local dps = (lo + hi) / 2 / math.max(mh or 2, 0.1)
            if oh and oh > 0 and offHi and offHi > 0 then dps = dps + (offLo + offHi) / 2 / oh end
            dmgB.icon:SetTexture(GetInventoryItemTexture("player", 16) or "Interface\\Icons\\INV_Sword_04")
            dmgB:Set(format("%d - %d", lo, hi), WHITE)
            dpsB:Set(Comma(dps) .. " DPS", WHITE)
        end
    end

    if db.spell and profile.spell and GetSpellBonusDamage then
        local sp, crit = 0, 0
        for school = 2, 7 do
            sp = math.max(sp, GetSpellBonusDamage(school) or 0)
            crit = math.max(crit, GetSpellCritChance and GetSpellCritChance(school) or 0)
        end
        local heal = GetSpellBonusHealing and GetSpellBonusHealing()
        local text = sp .. L[" power"]
        if heal and heal ~= sp then text = text .. " · " .. heal .. L[" healing"] end
        spellB:Set(text, VIOLET)
        scritB:Set(Comma(crit) .. L[" % spell crit"], WHITE)
    end

    Layout()
end

-- Fade in/out while the mouse is over the player frame.
local alpha, elapsedSince = 0, 0
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
    local hovered = PlayerFrame:IsVisible() and PlayerFrame:IsMouseOver()
    local want = hovered and 1 or 0
    if alpha == 0 and want == 0 then return end
    if want == 1 and alpha == 0 then Update(); holder:Show() end
    alpha = want > alpha and math.min(1, alpha + elapsed / 0.15) or want < alpha and math.max(0, alpha - elapsed / 0.15) or alpha
    holder:SetAlpha(alpha)
    -- refresh values a few times per second while visible
    elapsedSince = elapsedSince + elapsed
    if hovered and elapsedSince > 0.3 then elapsedSince = 0; Update() end
    if alpha == 0 then holder:Hide() end
end)
watcher:Hide()

local mod = TW:NewModule("PortraitInfo", {
    title = L["Portrait Info"],
    icon = "Interface\\Icons\\INV_Shield_06",
    section = L["Character"],
    desc = L["Hover over your player frame to see, next to the portrait, your armor, physical damage reduction (against your target), weapon damage and DPS, and spell power. The information shown adapts to your class."],
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "defense", label = L["Armor and damage reduction"] },
        { type = "toggle", key = "melee", label = L["Weapon damage and DPS"] },
        { type = "toggle", key = "spell", label = L["Spell power and crit"] },
        { type = "select", key = "position", label = "Position", values = {
            { "top", L["Top"] },
            { "bottom", L["Bottom"] },
            { "left", L["Left"] },
            { "right", L["Right"] },
        } },
    },
})

function mod:OnEnable()
    db = self.db
    profile = PROFILES[select(2, UnitClass("player"))] or { melee = true }
    ApplyPosition()
    watcher:Show()
end

function mod:OnOptionChanged(key)
    if key == "position" then ApplyPosition() end
end

function mod:OnDisable()
    watcher:Hide()
    holder:Hide()
    alpha = 0
end
