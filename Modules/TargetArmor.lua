-- TargetArmor: hovering the target frame shows armor debuffs on the target and, for monsters
-- whose armor you entered with /twarmor, its armor, how much of your physical damage it
-- absorbs and your weapon damage against it. The game does not expose monster armor, so
-- nothing is estimated.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local UnitDebuff = ns.API.UnitDebuff

local DEFAULTS = {
    damage = true,    -- show your damage against the target
    debuffs = true,   -- list armor debuffs
    custom = {},      -- [npcID] = armor set by hand
}

-- Armor reducing debuffs: [spellID] = { value, per stack }
local ARMOR_DEBUFFS = {
    [7386] = { 90, true }, [7405] = { 180, true }, [8380] = { 270, true },     -- Sunder Armor
    [11596] = { 360, true }, [11597] = { 450, true },
    [8647] = { 400 }, [8649] = { 725 }, [8650] = { 1050 }, [11197] = { 1375 }, [11198] = { 1700 }, -- Expose Armor (5 pts)
    [770] = { 175 }, [778] = { 285 }, [9749] = { 395 }, [9907] = { 505 },       -- Faerie Fire
    [16857] = { 175 }, [17390] = { 285 }, [17391] = { 395 }, [17392] = { 505 }, -- Faerie Fire (Feral)
    [704] = { 140 }, [7658] = { 290 }, [7659] = { 465 }, [11717] = { 640 },     -- Curse of Recklessness
    [16928] = { 200, true },                                                    -- Armor Shatter (Annihilator)
    [15235] = { 200 },                                                          -- Crystal Yield
}

local db
local WHITE, SKY, ORANGE, GREEN = { 1, 1, 1 }, { 0.65, 0.88, 1 }, { 1, 0.63, 0.13 }, { 0.3, 1, 0.3 }

local Comma, DamageReduction = ns.Comma, ns.DamageReduction

local function NpcID(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Base armor entered by hand for this monster, or nil.
local function BaseArmor(unit)
    local id = NpcID(unit)
    return id and db.custom[id]
end

local function ArmorDebuffs(unit)
    local total, sunder = 0, 0
    for i = 1, 40 do
        local name, _, count, _, _, _, _, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end
        local d = spellId and ARMOR_DEBUFFS[spellId]
        if d then
            local stacks = math.max(count or 0, 1)
            total = total + (d[2] and d[1] * stacks or d[1])
            if d[2] then sunder = stacks end
        end
    end
    return total, sunder
end

---------------------------------------------------------------------------
-- Badges, stacked above the target portrait
---------------------------------------------------------------------------

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata("HIGH")
holder:SetSize(1, 1)
holder:Hide()

local function CreateBadge(iconPath)
    return ns.CreateBadge(holder, iconPath)
end

local badges = {
    armor = CreateBadge("Interface\\Icons\\INV_Shield_06"),
    reduc = CreateBadge("Interface\\Icons\\Spell_Holy_DevotionAura"),
    debuff = CreateBadge("Interface\\Icons\\Ability_Warrior_Sunder"),
    damage = CreateBadge("Interface\\Icons\\INV_Sword_04"),
}
local ORDER = { "armor", "reduc", "debuff", "damage" } -- bottom to top

local function Update()
    for _, b in pairs(badges) do b.on = false end
    local unit = "target"
    if not UnitExists(unit) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end

    local minus, sunder = ArmorDebuffs(unit)
    if db.debuffs and minus > 0 then
        local text = "-" .. minus .. L[" armor (debuffs)"]
        if sunder > 0 then text = text .. format(L[" · Sunder x%d"], sunder) end
        badges.debuff:Set(text, ORANGE)
    end

    -- Armor, reduction and damage only for monsters whose armor was entered by hand.
    local base = BaseArmor(unit)
    if not base then return end
    local armor = math.max(base - minus, 0)
    badges.armor:Set(armor .. L[" armor"], minus > 0 and GREEN or WHITE)

    local dr = DamageReduction(armor, UnitLevel("player"))
    badges.reduc:Set("-" .. Comma(dr * 100) .. L[" % to your hits"], SKY)

    if db.damage then
        local _, class = UnitClass("player")
        local lo, hi, icon
        if class == "HUNTER" and UnitRangedDamage then
            local _, rlo, rhi = UnitRangedDamage("player")
            if rhi and rhi > 0 then lo, hi, icon = rlo, rhi, GetInventoryItemTexture("player", 18) end
        end
        if not lo and class ~= "MAGE" and class ~= "PRIEST" and class ~= "WARLOCK" then
            lo, hi = UnitDamage("player")
            icon = GetInventoryItemTexture("player", 16)
        end
        if lo then
            badges.damage.icon:SetTexture(icon or "Interface\\Icons\\INV_Sword_04")
            badges.damage:Set(format(L["%d - %d damage against it"], lo * (1 - dr), hi * (1 - dr)), WHITE)
        end
    end
end

local function Layout()
    local prev
    for _, key in ipairs(ORDER) do
        local b = badges[key]
        b:ClearAllPoints()
        if b.on then
            if prev then
                b:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", 0, 2)
            else
                b:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
            end
            prev = b
        end
        b:SetShown(b.on)
    end
end

-- Fade in/out while the mouse is over the target frame.
local alpha, since = 0, 0
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
    local hovered = TargetFrame:IsVisible() and TargetFrame:IsMouseOver()
    local want = hovered and 1 or 0
    if alpha == 0 and want == 0 then return end
    since = since + elapsed
    if (want == 1 and alpha == 0) or (hovered and since > 0.3) then
        since = 0
        Update()
        Layout()
        holder:Show()
    end
    alpha = want > alpha and math.min(1, alpha + elapsed / 0.15) or want < alpha and math.max(0, alpha - elapsed / 0.15) or alpha
    holder:SetAlpha(alpha)
    if alpha == 0 then holder:Hide() end
end)
watcher:Hide()

local mod = TW:NewModule("TargetArmor", {
    title = L["Target Armor"],
    icon = "Interface\\Icons\\Ability_Warrior_Sunder",
    section = "Combat",
    desc = L["Hover over your target's frame (monster) to see its armor debuffs (Sunder Armor, Faerie Fire, Expose Armor…).\n\nThe game doesn't provide monster armor: enter it with /twarmor 1234 (with the monster targeted) to also see its armor, the % of damage it removes from your hits and your damage against it. Remove: /twarmor clear"],
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "debuffs", label = L["Show armor debuffs"] },
        { type = "toggle", key = "damage", label = L["Show your damage against the target"] },
    },
})

function mod:OnEnable()
    db = self.db
    holder:ClearAllPoints()
    holder:SetPoint("BOTTOMRIGHT", TargetFramePortrait or TargetFrame, "TOPRIGHT", 0, 6)
    watcher:Show()
end

function mod:OnDisable()
    watcher:Hide()
    holder:Hide()
    alpha = 0
end

SLASH_TINKERWISEARMOR1 = "/twarmor"
SlashCmdList.TINKERWISEARMOR = function(input)
    if not mod.active then return TW:Print(L["the Target Armor module is disabled (/tw)."]) end
    local id = NpcID("target")
    if not id then return TW:Print(L["target a monster first."]) end
    local arg = strtrim(input or ""):lower()
    if arg == "clear" then
        db.custom[id] = nil
        TW:Print(format(L["override removed for %s."], UnitName("target")))
    elseif tonumber(arg) then
        db.custom[id] = tonumber(arg)
        TW:Print(format(L["%s's armor set to %d."], UnitName("target"), tonumber(arg)))
    else
        local base = BaseArmor("target")
        TW:Print(format(L["%s's armor: %s. Usage: /twarmor 1234 | clear"],
            UnitName("target"), base and tostring(base) or L["unknown"]))
    end
end
