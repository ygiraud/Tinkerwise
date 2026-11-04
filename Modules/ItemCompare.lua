-- ItemCompare: adds to item tooltips what the item would change compared with what you wear
-- in the same slot(s): one line per stat, green for gains, red for losses.

local _, ns = ...
local TW = ns.TW
local GetItemInfoInstant, GetItemInfo = ns.API.GetItemInfoInstant, ns.API.GetItemInfo

local DEFAULTS = {
    shiftOnly = false,  -- only compare while Shift is held
    percent = true,     -- add the relative change "(+12 %)"
}

-- Equip location -> inventory slots it can go into.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Display order and French fallbacks when the client has no global string for a stat.
local ORDER = {
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "RESISTANCE0_NAME",
    "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
}
local FALLBACK = {
    ITEM_MOD_STRENGTH_SHORT = "Force", ITEM_MOD_AGILITY_SHORT = "Agilité",
    ITEM_MOD_STAMINA_SHORT = "Endurance", ITEM_MOD_INTELLECT_SHORT = "Intelligence",
    ITEM_MOD_SPIRIT_SHORT = "Esprit", RESISTANCE0_NAME = "Armure",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Dégâts par seconde",
}

local db

local function Stats(link)
    local fn = GetItemStats or (C_Item and C_Item.GetItemStats)
    return (fn and fn(link)) or {}
end

local function Label(key)
    local text = _G[key]
    if type(text) == "string" and text ~= "" then return (text:gsub("%%s", ""):gsub("^%s+", "")) end
    return FALLBACK[key] or key
end

local function FormatValue(d)
    if math.abs(d - math.floor(d + 0.5)) > 0.05 then return format("%+.1f", d) end
    return format("%+d", math.floor(d + 0.5))
end

-- Adds the comparison block for one slot to the tooltip (no link = empty slot).
local function AddComparison(tooltip, newStats, equippedLink)
    local old = equippedLink and Stats(equippedLink) or {}
    tooltip:AddLine(" ")
    tooltip:AddLine(equippedLink and ("Par rapport à : " .. equippedLink) or "Emplacement vide", 1, 0.82, 0)

    -- union of stat keys, known ones first in a stable order
    local keys, seen = {}, {}
    for _, k in ipairs(ORDER) do
        if newStats[k] or old[k] then keys[#keys + 1] = k; seen[k] = true end
    end
    local rest = {}
    for k in pairs(newStats) do if not seen[k] then rest[#rest + 1] = k; seen[k] = true end end
    for k in pairs(old) do if not seen[k] then rest[#rest + 1] = k; seen[k] = true end end
    table.sort(rest)
    for _, k in ipairs(rest) do keys[#keys + 1] = k end

    local any = false
    for _, k in ipairs(keys) do
        local before, after = old[k] or 0, newStats[k] or 0
        local d = after - before
        if math.abs(d) >= 0.05 then
            any = true
            local text = FormatValue(d) .. " " .. Label(k)
            if db.percent and before > 0 then text = text .. format(" (%+d %%)", d / before * 100 + (d > 0 and 0.5 or -0.5)) end
            if d > 0 then tooltip:AddLine(text, 0.2, 1, 0.2) else tooltip:AddLine(text, 1, 0.25, 0.25) end
        end
    end
    if not any then tooltip:AddLine("Aucune différence de caractéristiques", 0.7, 0.7, 0.7) end
end

-- What each class can learn. Item subclasses: armor 1 cloth, 2 leather, 3 mail, 4 plate,
-- 6 shield, 7 libram, 8 idol, 9 totem; weapons 0/1 axes, 2 bow, 3 gun, 4/5 maces, 6 polearm,
-- 7/8 swords, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
local function Set(...)
    local set = {}
    for i = 1, select("#", ...) do set[select(i, ...)] = true end
    return set
end
local CLASS_ARMOR = {
    WARRIOR = Set(1, 2, 3, 4, 6), PALADIN = Set(1, 2, 3, 4, 6, 7), HUNTER = Set(1, 2, 3),
    SHAMAN = Set(1, 2, 3, 6, 9), ROGUE = Set(1, 2), DRUID = Set(1, 2, 8),
    PRIEST = Set(1), MAGE = Set(1), WARLOCK = Set(1),
}
local CLASS_WEAPONS = {
    WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
    HUNTER = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE = Set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST = Set(4, 10, 15, 19),
    SHAMAN = Set(0, 1, 4, 5, 10, 13, 15),
    MAGE = Set(7, 10, 15, 19),
    WARLOCK = Set(7, 10, 15, 19),
    DRUID = Set(4, 5, 10, 13, 15),
}
-- Armor learned later: mail for hunters and shamans, plate for warriors and paladins.
local ARMOR_LEVEL = {
    HUNTER = { [3] = 40 }, SHAMAN = { [3] = 40 }, WARRIOR = { [4] = 40 }, PALADIN = { [4] = 40 },
}
local ARMOR_CLASS, WEAPON_CLASS = 4, 2

local function ClassCanUse(class, classID, subclassID)
    if classID == ARMOR_CLASS then
        return subclassID == 0 or (CLASS_ARMOR[class] and CLASS_ARMOR[class][subclassID])
    elseif classID == WEAPON_CLASS then
        return CLASS_WEAPONS[class] and CLASS_WEAPONS[class][subclassID]
    end
    return true
end

local function RequiredLevel(link, class, classID, subclassID)
    local required = select(5, GetItemInfo(link)) or 0
    local learned = classID == ARMOR_CLASS and ARMOR_LEVEL[class] and ARMOR_LEVEL[class][subclassID]
    return math.max(required, learned or 0)
end

local function OnTooltipSetItem(tooltip)
    if not db or not TW.modules.ItemCompare.active then return end
    if db.shiftOnly and not IsShiftKeyDown() then return end
    local _, link = tooltip:GetItem()
    if not link or tooltip.twCompared == link then return end
    local _, _, _, equipLoc = GetItemInfoInstant(link)
    local slots = equipLoc and SLOTS[equipLoc]
    if not slots then return end

    -- Hovering something you already wear: nothing to compare.
    for _, slot in ipairs(slots) do
        if GetInventoryItemLink("player", slot) == link then return end
    end
    tooltip.twCompared = link

    local class = select(2, UnitClass("player"))
    local classID, subclassID = select(6, GetItemInfoInstant(link))
    if not ClassCanUse(class, classID, subclassID) then
        tooltip:AddLine(" ")
        tooltip:AddLine("Votre classe ne peut pas porter cet objet", 1, 0.25, 0.25)
        tooltip:Show()
        return
    end
    local required = RequiredLevel(link, class, classID, subclassID)
    if required > UnitLevel("player") then
        tooltip:AddLine(" ")
        tooltip:AddLine(format("Portable au niveau %d", required), 1, 0.63, 0.13)
    end

    local newStats = Stats(link)
    local compared = false
    for _, slot in ipairs(slots) do
        local equipped = GetInventoryItemLink("player", slot)
        if equipped then
            AddComparison(tooltip, newStats, equipped)
            compared = true
        end
    end
    if not compared then AddComparison(tooltip, newStats) end
    tooltip:Show()
end

ns.CompareTooltip = OnTooltipSetItem -- for tooltips outside the hooked ones (quest scene)

local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    -- Recent clients replaced the OnTooltipSetItem script with a tooltip data callback.
    local useProcessor = TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if useProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then OnTooltipSetItem(tooltip) end
        end)
    end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            if not useProcessor and tooltip:HasScript("OnTooltipSetItem") then
                tooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end
            tooltip:HookScript("OnTooltipCleared", function(self) self.twCompared = nil end)
        end
    end
end

local mod = TW:NewModule("ItemCompare", {
    title = "Comparateur d'objets",
    section = "Objets",
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    desc = "Au survol d'un objet équipable, l'infobulle indique ce qu'il vous ferait gagner ou perdre par rapport à l'objet porté au même emplacement (les deux anneaux, bijoux ou armes à une main sont comparés séparément). Vert = gain, rouge = perte.",
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "shiftOnly", label = "Comparer seulement en maintenant Maj" },
        { type = "toggle", key = "percent", label = "Afficher la variation en %" },
    },
})

function mod:OnEnable()
    db = self.db
    Hook() -- hooks cannot be removed; OnTooltipSetItem checks that the module is active
end
