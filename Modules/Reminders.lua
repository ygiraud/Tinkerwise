-- Reminders: what the card of Courtesy.lua offers besides buffs: a weapon without a temporary enchant,
-- the well fed buff, a hunter's pet or a warlock's demon. Only away from the rest areas, and only with
-- what is in the bags.
--
-- ns.Reminders.Next(db) returns an action like NextAction's in Courtesy.lua, or nil.

local _, ns = ...
local L = ns.L
local Spells = ns.Spells -- set by Courtesy.lua
local Plain = Spells.Plain
local GetItemCount, GetItemInfo, GetItemInfoInstant = ns.API.GetItemCount, ns.API.GetItemInfo, ns.API.GetItemInfoInstant
local ContainerNumSlots, ContainerItem = ns.API.ContainerNumSlots, ns.API.ContainerItem

local class = select(2, UnitClass("player"))

-- Every list from the best to the worst.
local POISONS = { 8928, 8927, 8926, 6950, 6949, 6947, 20844, 8985, 8984, 2893, 2892,
                  10922, 10921, 10920, 10918, 9186, 6951, 5237, 3776, 3775 }
local OILS = { 20749, 20750, 20746, 20744, 20748, 20747, 20745 }
local BLADE_STONES = { 18262, 12404, 7964, 2871, 2863, 2862 }
local BLUNT_STONES = { 18262, 12643, 7965, 3241, 3240, 3239 }
local BLADES = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true }
local FISHING_POLE = 20
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true }

-- A shaman's own weapon enchants: the first one known is offered, at its best rank.
local SHAMAN_ENCHANTS = {
    { 16362, 10486, 8235, 8232 },                 -- Windfury Weapon
    { 16342, 16341, 16339, 8030, 8027, 8024 },    -- Flametongue Weapon
    { 16316, 16315, 16314, 10399, 8019, 8018, 8017 }, -- Rockbiter Weapon
}

-- Only those whose buff is called "Well Fed": the others could not be told to be on.
local BUFF_FOODS = {
    20452, 18045, 16971, 13851, 12224, 12218, 12216, 12215,
    12213, 12212, 12210, 12209, 20074, 17222, 3729, 3728, 3727, 3726, 3666, 3665, 3664, 3663, 3662,
    2687, 2683, 1082, 1017, 724, 3220, 5527, 5525, 5480, 5479, 5477, 5476, 5474, 5472, 2684, 2680, 6888,
}
local WELL_FED, EATING, DRINKING = 19705, 433, 430

local HUNTER_CALL, HUNTER_REVIVE, HUNTER_FEED, FEED_EFFECT = 883, 982, 6991, 1539
local UNHAPPY = 1

local SOUL_SHARD = 6265
local DEMONS = { imp = 688, voidwalker = 697, succubus = 712, felhunter = 691 }
local DEMON_ORDER = { "imp", "voidwalker", "succubus", "felhunter" }
local DEMON_FAMILY = { imp = 23, voidwalker = 16, succubus = 17, felhunter = 15 }
local SACRIFICES = { 18789, 18790, 18791, 18792 } -- Demonic Sacrifice: no demon wanted

-- A warlock's stones, best first. They enchant the weapon on WoW Forever: only one at a time.
local STONES = {
    spellstone = { items = { 13603, 13602, 5522 }, create = { 17728, 17727, 2362 }, other = "firestone" },
    firestone = { items = { 13701, 13700, 13699, 1254 }, create = { 17953, 17952, 17951, 6366 }, other = "spellstone" },
}

local function HasAura(unit, spell)
    local name = Spells.Name(spell)
    if not name then return false end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        -- A secret answer counts as worn: nothing is offered without knowing.
        return not ok or (aura ~= nil)
    end
    return AuraUtil and AuraUtil.FindAuraByName(name, unit, "HELPFUL") ~= nil
end

-- The first item of the list in the bags that the character may use, or nil.
local function FirstUsable(list)
    local level = UnitLevel("player")
    for _, id in ipairs(list) do
        if (Plain(GetItemCount(id)) or 0) > 0 and (select(5, GetItemInfo(id)) or 0) <= level then return id end
    end
end

local function ItemAction(id, title, macro)
    local name = GetItemInfo(id)
    if not name then return end
    return { icon = ns.API.GetItemIcon(id), title = title, detail = name, text = title .. ": " .. name, macro = macro }
end

local function SpellAction(id, title)
    local name = Spells.Name(id)
    if not name then return end
    return { icon = Spells.Icon(id), title = title, detail = name, text = title .. ": " .. name,
             macro = "/cast " .. name .. (name:find("(", 1, true) and "()" or "") }
end

---------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------

-- Whether the weapon has a temporary enchant; nil when the game does not tell.
local function Enchanted(slot)
    local new = C_Item and C_Item.GetWeaponEnchantInfo
    local slots = Enum and Enum.WeaponSlot
    if new and slots then
        local ok, list = pcall(new, slot == 16 and slots.MainHand or slots.OffHand)
        if ok and type(Plain(list)) == "table" then
            for _, enchant in pairs(list) do
                local has = Plain(enchant.hasEnchant)
                if has == nil then return nil end
                if has then return true end
            end
            return false
        end
    end
    if _G.GetWeaponEnchantInfo then
        local main, _, _, _, off = GetWeaponEnchantInfo()
        if slot == 16 then return Plain(main) and true or false end
        return Plain(off) and true or false
    end
end

-- The favorite stone from the bags, else created; the other one while the favorite is not learned.
local function StoneAction(wanted)
    local stone = STONES[wanted]
    if not stone then return end
    local function Learned(s)
        for _, id in ipairs(s.create) do
            if Spells.Known(id) then return id end
        end
    end
    local spell = Learned(stone)
    if not spell then
        stone = STONES[stone.other]
        spell = Learned(stone)
    end
    if not spell then return end
    local id = FirstUsable(stone.items)
    if id then return ItemAction(id, L["Enchant your weapon"], "/use item:" .. id .. "\n/use 16") end
    if (Plain(GetItemCount(SOUL_SHARD)) or 0) > 0 then return SpellAction(spell, L["Create your stone"]) end
end

local function WeaponAction(db)
    for _, slot in ipairs({ 16, 17 }) do
        local weapon = GetInventoryItemID("player", slot)
        local _, _, _, _, _, classID, subclassID
        if weapon then _, _, _, _, _, classID, subclassID = GetItemInfoInstant(weapon) end
        if classID == 2 and subclassID ~= FISHING_POLE and Enchanted(slot) == false then
            if class == "SHAMAN" then
                for _, ranks in ipairs(SHAMAN_ENCHANTS) do
                    for _, id in ipairs(ranks) do
                        if Spells.Known(id) then return slot == 16 and SpellAction(id, L["Enchant your weapon"]) or nil end
                    end
                end
            end
            if class == "WARLOCK" then
                local action = StoneAction(db.stone)
                if action then return action end
            end
            local id
            if class == "ROGUE" then id = FirstUsable(POISONS) end
            if not id and CASTERS[class] then id = FirstUsable(OILS) end
            if not id and BLADES[subclassID] then id = FirstUsable(BLADE_STONES) end
            if not id and BLUNT[subclassID] and not CASTERS[class] then id = FirstUsable(BLUNT_STONES) end
            if id then return ItemAction(id, L["Enchant your weapon"], "/use item:" .. id .. "\n/use " .. slot) end
        end
    end
end

---------------------------------------------------------------------------
-- Food
---------------------------------------------------------------------------

local function FoodAction()
    if HasAura("player", WELL_FED) or HasAura("player", EATING) or HasAura("player", DRINKING) then return end
    local id = FirstUsable(BUFF_FOODS)
    if id then return ItemAction(id, L["Eat well"], "/use item:" .. id) end
end

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------

local isFood = {} -- item id -> whether it is food (it never changes)

-- The pet's food to give: the cheapest level first, a buff food never.
local buffFood = {}
for _, id in ipairs(BUFF_FOODS) do buffFood[id] = true end

-- Every item of the bags the pet can eat: { [id] = count }. Empty without a pet or on older clients.
function ns.PetFoods()
    local foods = {}
    local canEat = C_PetInfo and C_PetInfo.CanPetEatItem
    if not canEat or not UnitExists("pet") then return foods end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ContainerNumSlots(bag) or 0 do
            local id, count = ContainerItem(bag, slot)
            if id and isFood[id] == nil then
                local _, _, _, _, _, classID = GetItemInfoInstant(id)
                isFood[id] = classID == 0 or classID == 7
            end
            if id and isFood[id] then
                local ok, eats = pcall(canEat, id)
                if ok and Plain(eats) then foods[id] = (foods[id] or 0) + (count or 1) end
            end
        end
    end
    return foods
end

local function FeedAction()
    local get = C_PetInfo and C_PetInfo.GetPetHappiness or _G.GetPetHappiness
    if not get or not Spells.Known(HUNTER_FEED) then return end
    local ok, happiness = pcall(get)
    if not ok or Plain(happiness) ~= UNHAPPY or HasAura("pet", FEED_EFFECT) then return end
    local best, bestLevel
    for id in pairs(ns.PetFoods()) do
        local level = select(5, GetItemInfo(id))
        if level and not buffFood[id] and (not bestLevel or level > bestLevel) then best, bestLevel = id, level end
    end
    local spell = Spells.Name(HUNTER_FEED)
    if best and spell then return ItemAction(best, L["Feed your pet"], "/cast " .. spell .. "\n/use item:" .. best) end
end

local function HunterAction()
    if UnitExists("pet") then
        if Plain(UnitIsDead("pet")) then
            return Spells.Known(HUNTER_REVIVE) and SpellAction(HUNTER_REVIVE, L["Revive your pet"]) or nil
        end
        return FeedAction()
    end
    if Spells.Known(HUNTER_CALL) then return SpellAction(HUNTER_CALL, L["Call your pet"]) end
end

local function DemonAction(wanted)
    for _, id in ipairs(SACRIFICES) do
        if HasAura("player", id) then return end
    end
    local out = UnitExists("pet") and not Plain(UnitIsDead("pet"))
    if out then
        if wanted == "any" then return end
        local _, family = UnitCreatureFamily("pet")
        family = Plain(family)
        if not family or family == DEMON_FAMILY[wanted] then return end -- untold: taken as the right one
        local known = false
        for _, id in pairs(DEMON_FAMILY) do known = known or id == family end
        if not known then return end -- an infernal, a doomguard, an enslaved demon
    end
    local shards = Plain(GetItemCount(SOUL_SHARD)) or 0
    local function Can(key)
        return Spells.Known(DEMONS[key]) and (key == "imp" or shards > 0)
    end
    if wanted ~= "any" and Can(wanted) then return SpellAction(DEMONS[wanted], L["Summon your demon"]) end
    if out then return end
    for _, key in ipairs(DEMON_ORDER) do
        if Can(key) then return SpellAction(DEMONS[key], L["Summon your demon"]) end
    end
end

-- A pet comes back by itself a moment after dismounting or a loading screen.
local PET_GRACE = 5
local petMissingSince

local function PetAction(db)
    if class ~= "HUNTER" and class ~= "WARLOCK" then return end
    if UnitExists("pet") then
        petMissingSince = nil
    else
        petMissingSince = petMissingSince or GetTime()
        if GetTime() - petMissingSince < PET_GRACE then return end
    end
    if class == "HUNTER" then return HunterAction() end
    return DemonAction(db.demon)
end

---------------------------------------------------------------------------

ns.Reminders = {}

function ns.Reminders.Next(db)
    if Plain(IsResting()) or (IsMounted and Plain(IsMounted())) or (Plain(IsFlying and IsFlying())) then
        petMissingSince = nil
        return
    end
    return db.pet and PetAction(db)
        or db.weapon and WeaponAction(db)
        or db.foodBuff and FoodAction()
        or nil
end

-- The options for this class, after Courtesy's own.
local function Options()
    local options = {
        { type = "header", label = L["Reminders (away from rest areas)"] },
        { type = "toggle", key = "weapon", label = L["Weapon stones, oils and poisons"] },
        { type = "toggle", key = "foodBuff", label = L["Food that gives a buff"] },
    }
    if class == "HUNTER" or class == "WARLOCK" then
        options[#options + 1] = { type = "toggle", key = "pet", label = class == "HUNTER" and L["Pet missing, dead or unhappy"] or L["Demon missing"] }
    end
    if class == "WARLOCK" then
        local values = { { "any", L["Any demon"] } }
        for _, key in ipairs(DEMON_ORDER) do
            values[#values + 1] = { key, Spells.Name(DEMONS[key]) or key }
        end
        options[#options + 1] = { type = "select", key = "demon", label = L["Favorite demon"], values = values }
        options[#options + 1] = { type = "select", key = "stone", label = L["Favorite stone"], values = {
            { "spellstone", L["Spellstone"] }, { "firestone", L["Firestone"] }, { "none", L["None (oils only)"] },
        } }
    end
    return options
end

local courtesy = ns.TW.modules.Courtesy
for _, opt in ipairs(Options()) do courtesy.options[#courtesy.options + 1] = opt end
