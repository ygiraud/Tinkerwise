-- Checkup: "am I ready to go?" report (durability, food, drink, potions, ammo, reagents, bags)
-- with a readiness score and the top tips. Also warns when leaving town, when entering a
-- dungeon, and points out what a merchant sells that you are missing.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local API = ns.API
local GetSpellInfo, GetItemInfo, GetItemInfoInstant = API.GetSpellInfo, API.GetItemInfo, API.GetItemInfoInstant
local GetItemCount, GetItemSpell = API.GetItemCount, API.GetItemSpell
local GetCoinTextureString = API.GetCoinTextureString

local DEFAULTS = {
    dura = 30,          -- warn when an item is below this durability %
    food = 10,          -- minimum food count
    drink = 10,         -- minimum drink count (mana users)
    ammo = 800,         -- minimum ammo count (hunters)
    ammoOther = 200,    -- the same for the other classes with a bow, a crossbow or a gun
    petFood = 10,       -- minimum pet food (hunters with their pet out)
    elixirs = 0,        -- minimum elixirs (0: shown, but not counted)
    slots = 4,          -- minimum free bag slots
    sound = true,
    quick = false,      -- faster reveal animation
    chatButton = true,
    autoRest = true,    -- warn when leaving a rested area
    sleepAlert = true,  -- warn when the buff of the sleeping bag is about to end
    autoInstance = true,-- open the check-up when entering a dungeon / raid
    restock = true,     -- button that buys what is missing at a merchant
    merchant = true,    -- list what a merchant sells that you need
    -- the checks to run
    checkArmor = true,
    checkFood = true,
    checkDrink = true,
    checkPotions = true,
    checkAmmo = true,
    checkShards = true, -- warlocks
    checkReagents = true,
    checkElixirs = true,
    checkSleep = true, -- the buff of the sleeping bag
    checkBags = true,
    checkTalents = true,
}

local OK, WARN, BAD = 2, 1, 0
local GREEN, ORANGE, RED = "|cff33ff33", "|cffffa020", "|cffff4040"

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- Vendor ammo by required level.
local AMMO = {
    arrow = { { 2512, 1 }, { 2515, 10 }, { 3030, 25 }, { 11285, 40 } },
    bullet = { { 2516, 1 }, { 2519, 10 }, { 3033, 25 }, { 11284, 40 } },
}
-- Food / drink sold by vendors exist at these required levels.
local FOOD_TIERS = { 1, 5, 15, 25, 35, 45, 55 }

local HEALTHSTONES = {}
for _, id in ipairs({ 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }) do
    HEALTHSTONES[id] = true
end
local BANDAGES = {}
for _, id in ipairs({ 1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529, 14530 }) do BANDAGES[id] = true end
local ELIXIRS = {}
for _, id in ipairs({ 2454, 2457, 2458, 3383, 3389, 3390, 3391, 3825, 5997, 6373, 8949, 8951, 9155, 9179, 9187,
                      9206, 9264, 13445, 13447, 13452, 13453, 13454, 17708, 20004, 20007, 21546 }) do
    ELIXIRS[id] = true
end

-- Class reagents: { itemID, from level, to level, needed by default (0: not checked), critical }
local REAGENTS = {
    MAGE = { { 17020, 56, 60, 5 }, { 17031, 20, 60, 2 }, { 17032, 40, 60, 1 }, { 17056, 12, 60, 5 } },
    PRIEST = { { 17028, 48, 59, 5 }, { 17029, 60, 60, 5 }, { 17056, 34, 60, 5 } },
    SHAMAN = { { 17030, 30, 60, 1, true } },
    WARLOCK = { { 5565, 50, 60, 0 }, { 16583, 60, 60, 0 } },
    ROGUE = { { 5140, 22, 60, 5 }, { 5530, 34, 60, 5 } },
    PALADIN = { { 17033, 30, 60, 1 }, { 21177, 52, 60, 10 } },
    DRUID = { { 17034, 20, 29, 1 }, { 17035, 30, 39, 1 }, { 17036, 40, 49, 1 }, { 17037, 50, 59, 1 },
              { 17038, 60, 60, 1 }, { 17021, 50, 59, 5 }, { 17026, 60, 60, 5 } },
}

for _, list in pairs(REAGENTS) do
    for _, r in ipairs(list) do DEFAULTS["reagent" .. r[1]] = r[4] end
end

local SOUL_SHARD = 6265
local SLEEPING_BAG, WELL_RESTED, WELL_RESTED_STACKS = 211527, 429959, 3
local WELL_RESTED_SOON = 30 * 60 -- seconds left under which to sleep again

local DURA_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local ICONS = {
    armor = "Interface\\Icons\\Trade_BlackSmithing",
    food = "Interface\\Icons\\INV_Misc_Food_15",
    drink = "Interface\\Icons\\INV_Drink_07",
    potions = "Interface\\Icons\\INV_Potion_54",
    ammo = "Interface\\Icons\\INV_Ammo_Arrow_02",
    petfood = "Interface\\Icons\\Ability_Hunter_BeastTraining",
    shards = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    reagents = "Interface\\Icons\\INV_Misc_Dust_02",
    elixirs = "Interface\\Icons\\INV_Potion_61",
    talents = "Interface\\Icons\\Ability_Marksmanship",
    sleep = "Interface\\Icons\\INV_Misc_Bag_BigBagOfEnchantments",
    bags = "Interface\\Icons\\INV_Misc_Bag_08",
}
local STATUS_ICON = {
    [OK] = "Interface\\RaidFrame\\ReadyCheck-Ready",
    [WARN] = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    [BAD] = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local db

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local NumSlots, ContainerItem = API.ContainerNumSlots, API.ContainerItem
local FreeSlots = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots

local function ItemName(id)
    local name = GetItemInfo(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name or (L["item #"] .. id)
end

local function ItemLink(id)
    local _, link = GetItemInfo(id)
    return link or ItemName(id)
end

local function MinLevel(id)
    return select(5, GetItemInfo(id)) or 0
end

local function Tier(level)
    local best = 1
    for _, t in ipairs(FOOD_TIERS) do if t <= level then best = t end end
    return best
end

local function UsesMana()
    return UnitPowerMax("player", 0) > 0
end

local FOOD_SPELL, DRINK_SPELL

local function ConsumableKind(id)
    FOOD_SPELL = FOOD_SPELL or GetSpellInfo(433)
    DRINK_SPELL = DRINK_SPELL or GetSpellInfo(430)
    local spell = GetItemSpell(id)
    if not spell then return end
    if spell == DRINK_SPELL then return "drink" end
    if spell == FOOD_SPELL then return "food" end
end

local function AmmoType()
    local id = GetInventoryItemID("player", 18)
    if not id then return end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
    if classID ~= 2 then return end
    if subclassID == 2 or subclassID == 18 then return "arrow" end
    if subclassID == 3 then return "bullet" end
end

local function BestVendorAmmo(kind, level)
    local best
    for _, a in ipairs(AMMO[kind]) do
        if a[2] <= level then best = a end
    end
    return best
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------

local scanTip = CreateFrame("GameTooltip", "TinkerwiseCheckupTip", nil, "GameTooltipTemplate")

local function ScanBags()
    local inv = { counts = {}, free = 0, total = 0, quiver = false }
    for bag = 0, 4 do
        local n = NumSlots(bag) or 0
        local free, family = FreeSlots(bag)
        if bag > 0 and family and family ~= 0 then
            if bit.band(family, 3) ~= 0 then inv.quiver = true end
        else
            inv.free = inv.free + (free or 0)
            inv.total = inv.total + n
        end
        for slot = 1, n do
            local id, count = ContainerItem(bag, slot)
            if id then inv.counts[id] = (inv.counts[id] or 0) + (count or 0) end
        end
    end
    return inv
end

local function NewCategory(key, name)
    return { key = key, name = name, icon = ICONS[key], lines = {}, tips = {} }
end

local function Tip(cat, prio, text)
    cat.tips[#cat.tips + 1] = { prio = prio, text = text }
end

local function CheckArmor()
    local cat = NewCategory("armor", L["Armor"])
    local sum, n, lowest, lowestSlot, broken, cost = 0, 0, 101, nil, 0, 0
    cat.worn = {}
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    for _, slot in ipairs(DURA_SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            sum, n = sum + pct, n + 1
            if pct < db.dura then cat.worn[#cat.worn + 1] = { slot = slot, pct = pct } end
            if pct < lowest then lowest, lowestSlot = pct, slot end
            if cur == 0 then broken = broken + 1 end
            local _, _, repair = scanTip:SetInventoryItem("player", slot)
            cost = cost + (repair or 0)
        end
    end
    scanTip:Hide()
    if n == 0 then
        cat.status, cat.pct = OK, 100
        cat.lines[1] = L["No item with durability."]
        return cat
    end
    table.sort(cat.worn, function(a, b)
        if a.pct ~= b.pct then return a.pct < b.pct end
        return a.slot < b.slot
    end)
    local avg = sum / n
    cat.pct = broken > 0 and avg * 0.5 or avg
    cat.lines[1] = format(L["Average durability: %d %%"], avg + 0.5)
    cat.lines[2] = format(L["Most worn: %s (%d %%)"], GetInventoryItemLink("player", lowestSlot) or "?", lowest + 0.5)
    if broken > 0 then cat.lines[#cat.lines + 1] = RED .. broken .. L[" broken item(s)|r"] end
    local money = GetMoney()
    if cost > 0 then
        cat.lines[#cat.lines + 1] = L["Estimated repair: "] .. GetCoinTextureString(cost)
    end
    cat.lines[#cat.lines + 1] = L["Your gold: "] .. GetCoinTextureString(money)

    if broken > 0 or lowest < 10 then
        cat.status = BAD
        Tip(cat, 100, format(L["Repair your gear (most worn item: %d %%)."], lowest + 0.5))
    elseif lowest < db.dura then
        cat.status = WARN
        Tip(cat, 60, format(L["Consider repairing soon (most worn item: %d %%)."], lowest + 0.5))
    else
        cat.status = OK
    end
    if cost > money then
        cat.status = BAD
        Tip(cat, 90, L["You don't have enough gold to repair everything."])
    end
    return cat
end

local function CheckFoodOrDrink(inv, kind, want)
    local cat = NewCategory(kind, kind == "food" and L["Food"] or L["Water"])
    local word = kind == "food" and L["food"] or L["drink"]
    local level = UnitLevel("player")
    local total, bestMin, bestId = 0, -1, nil
    for id, count in pairs(inv.counts) do
        if ConsumableKind(id) == kind then
            total = total + count
            local ml = MinLevel(id)
            if ml > bestMin then bestMin, bestId = ml, id end
        end
    end
    local minimum = kind == "food" and db.food or db.drink
    local tier = Tier(level)
    cat.value = format("%d / %d", total, minimum)
    cat.lines[1] = format(L["%d %s item(s)"], total, word)
    if bestId then cat.lines[2] = format(L["Best: %s (lvl %d)"], ItemLink(bestId), bestMin) end

    cat.status = OK
    if total == 0 and level >= 5 then
        cat.status = BAD
        Tip(cat, 80, format(L["You have no %s."], word))
    elseif total < minimum and level >= 5 then
        cat.status = WARN
        Tip(cat, 50, format(L["Only %d %s item(s) left: stock up."], total, word))
    end
    if bestId and bestMin < tier - 10 then
        cat.status = math.min(cat.status, WARN)
        Tip(cat, 40, format(L["Your %s (lvl %d) is weak for your level: get the level %d one."], word, bestMin, tier))
    end
    if level < 5 then
        cat.pct = 100
    else
        cat.pct = minimum > 0 and math.min(total / minimum, 1) * 100 or (total > 0 and 100 or 0)
        if bestId and bestMin < tier - 10 then cat.pct = cat.pct * 0.6 end
    end
    if cat.status ~= OK then
        want[kind] = tier
        -- Too weak: a whole new stock.
        want.amount[kind] = (bestId and bestMin < tier - 10) and minimum or minimum - total
    end
    return cat
end

local function CheckPotions(inv)
    local cat = NewCategory("potions", "Potions")
    local level = UnitLevel("player")
    local heal, mana, stones, bandages = 0, 0, 0, 0
    local healSet, manaSet = {}, {}
    for _, id in ipairs(ns.POTIONS.heal) do healSet[id] = true end
    for _, id in ipairs(ns.POTIONS.mana) do manaSet[id] = true end
    for id, count in pairs(inv.counts) do
        if healSet[id] then heal = heal + count
        elseif manaSet[id] then mana = mana + count
        elseif HEALTHSTONES[id] then stones = stones + count
        elseif BANDAGES[id] then bandages = bandages + count end
    end
    cat.lines[1] = format(L["Healing potions: %d   ·   Healthstones: %d"], heal, stones)
    cat.lines[2] = format(L["Bandages: %d"], bandages) .. (UsesMana() and format(L["   ·   Mana potions: %d"], mana) or "")

    local healing = heal + stones
    cat.value = format("%d / 2", healing)
    cat.pct = math.min(healing / 2, 1) * 100
    if healing == 0 then
        cat.status = level >= 10 and BAD or WARN
        Tip(cat, 70, L["No healing potions: keep at least two for emergencies."])
    elseif healing < 2 then
        cat.status = WARN
        Tip(cat, 35, L["Only one healing potion: get a second one."])
    else
        cat.status = OK
    end
    if bandages == 0 and level >= 10 then Tip(cat, 15, L["Bandages let you heal without mana between fights."]) end
    return cat
end

local function CheckAmmo(inv, want)
    local kind = AmmoType()
    local _, class = UnitClass("player")
    local minimum = class == "HUNTER" and db.ammo or db.ammoOther
    if not kind or minimum <= 0 then return end -- only what the worn weapon shoots is counted
    local cat = NewCategory("ammo", L["Ammo"])
    local level = UnitLevel("player")
    local total, bestLevel, good = 0, -1, 0
    local best = BestVendorAmmo(kind, level)
    for id, count in pairs(inv.counts) do
        local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
        if classID == 6 and subclassID == (kind == "arrow" and 2 or 3) then
            total = total + count
            bestLevel = math.max(bestLevel, MinLevel(id))
            if best and MinLevel(id) >= best[2] then good = good + count end
        end
    end
    cat.value = format("%d / %d", total, minimum)
    cat.lines[1] = format("%d %s", total, kind == "arrow" and L["arrows"] or L["bullets"])
    if best then cat.lines[2] = format(L["Recommended for your level: %s (lvl %d)"], ItemLink(best[1]), best[2]) end
    if class == "HUNTER" and not inv.quiver and level >= 10 then
        cat.lines[#cat.lines + 1] = ORANGE .. L["No quiver / ammo pouch equipped|r"]
        Tip(cat, 30, L["A quiver or ammo pouch speeds up your shots and frees up space."])
    end

    cat.status = OK
    if total == 0 then
        cat.status = BAD
        Tip(cat, 95, L["You are out of ammo!"])
    elseif total < minimum then
        cat.status = WARN
        Tip(cat, 55, format(L["Only %d ammo left: buy more."], total))
    end
    if best and total > 0 and bestLevel < best[2] then
        cat.status = math.min(cat.status, WARN)
        Tip(cat, 45, format(L["Switch to %s (lvl %d): more damage per shot."], ItemName(best[1]), best[2]))
    end
    cat.pct = math.min(total / minimum, 1) * 100
    if best and total > 0 and bestLevel < best[2] then cat.pct = cat.pct * 0.7 end
    if best and (cat.status ~= OK) then
        want.ammo, want.amount.ammo = best[1], minimum - good
    end
    return cat
end

local function CheckPetFood()
    if select(2, UnitClass("player")) ~= "HUNTER" or db.petFood <= 0 or not UnitExists("pet") or not ns.PetFoods
        or not (C_PetInfo and C_PetInfo.CanPetEatItem) then return end
    local cat = NewCategory("petfood", L["Pet food"])
    local total = 0
    for _, count in pairs(ns.PetFoods()) do total = total + count end
    cat.value = format("%d / %d", total, db.petFood)
    cat.lines[1] = format(L["%d item(s) your pet can eat"], total)
    cat.pct = math.min(total / db.petFood, 1) * 100
    cat.status = total == 0 and BAD or total < db.petFood and WARN or OK
    if cat.status ~= OK then Tip(cat, 45, format(L["Only %d item(s) left that your pet can eat."], total)) end
    return cat
end

local function CheckShards()
    local _, class = UnitClass("player")
    local need = class == "WARLOCK" and ns.SoulShardsWanted and ns.SoulShardsWanted() or 0 -- see SoulShards.lua
    if need <= 0 or UnitLevel("player") < 10 then return end
    local cat = NewCategory("shards", L["Soul Shards"])
    local count = GetItemCount(SOUL_SHARD)
    cat.item = SOUL_SHARD
    cat.value = format("%d / %d", count, need)
    cat.lines[1] = format(L["%d in your bags, %d wanted"], count, need)
    cat.pct = math.min(count / need, 1) * 100
    cat.status = count >= need and OK or count == 0 and BAD or WARN
    if cat.status ~= OK then
        Tip(cat, 75, format(L["Collect %s by finishing off monsters with Drain Soul (%d / %d)."], ItemName(SOUL_SHARD), count, need))
    end
    return cat
end

-- One line per reagent of the class, added to the list one by one.
local function CheckReagents(want, add)
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    for _, r in ipairs(REAGENTS[class] or {}) do
        local id, from, to, critical = r[1], r[2], r[3], r[5]
        local need = db["reagent" .. id]
        if need > 0 and level >= from and level <= to then
            local cat = NewCategory("reagents", ItemName(id))
            cat.icon = API.GetItemIcon(id) or cat.icon
            local count = GetItemCount(id)
            cat.item = id
            cat.value = format("%d / %d", count, need)
            cat.lines[1] = format(L["%d in your bags, %d wanted"], count, need)
            cat.pct = math.min(count / need, 1) * 100
            cat.status = OK
            if count < need then
                cat.status = (count == 0 and critical) and BAD or WARN
                Tip(cat, critical and 75 or 25, format(L["Buy more %s (%d / %d)."], ItemName(id), count, need))
                want.reagents = want.reagents or {}
                want.reagents[id] = need - count
            end
            add(cat)
        end
    end
end

local function CheckElixirs(inv)
    local level = UnitLevel("player")
    if level < 20 and db.elixirs == 0 then return end
    local cat = NewCategory("elixirs", L["Elixirs"])
    local total = 0
    for id, count in pairs(inv.counts) do
        if ELIXIRS[id] then total = total + count end
    end
    cat.lines[1] = total > 0 and format(L["%d elixir(s) in your bags"], total) or L["No elixirs"]
    if db.elixirs > 0 then
        cat.value = format("%d / %d", total, db.elixirs)
        cat.pct = math.min(total / db.elixirs, 1) * 100
        cat.status = total >= db.elixirs and OK or WARN
        if cat.status ~= OK then Tip(cat, 20, format(L["Only %d elixir(s) in your bags, %d wanted."], total, db.elixirs)) end
        return cat
    end
    cat.pct = math.min(total / 2, 1) * 100 -- informative only, not counted in the score
    if total == 0 and level >= 30 then Tip(cat, 10, L["An elixir or two helps in dungeons and against elites."]) end
    return cat
end

-- The experience buff of the sleeping bag, for those who carry the bag and can still gain levels.
local function CheckSleep()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    local maxLevel = math.min(GetMaxPlayerLevel and GetMaxPlayerLevel() or 60, 60)
    if UnitLevel("player") >= maxLevel or GetItemCount(SLEEPING_BAG) == 0 then return end
    local Plain = ns.Spells.Plain
    local ok, answer = pcall(C_UnitAuras.GetPlayerAuraBySpellID, WELL_RESTED)
    local aura = ok and Plain(answer)
    if not ok or (issecretvalue and issecretvalue(answer)) then return end -- kept secret by the game

    local cat = NewCategory("sleep", L["Sleeping bag"])
    cat.item = SLEEPING_BAG
    cat.icon = API.GetItemIcon(SLEEPING_BAG) or cat.icon
    local stacks, expires = 0, nil
    if aura then
        stacks = Plain(aura.applications)
        if not stacks then return end
        stacks = math.max(stacks, 1) -- 0 when the game does not count a single one
        expires = Plain(aura.expirationTime)
    end
    cat.value = format("%d / %d", stacks, WELL_RESTED_STACKS)
    cat.pct = math.min(stacks / WELL_RESTED_STACKS, 1) * 100
    cat.lines[1] = format(L["Experience bonus: %d of %d"], stacks, WELL_RESTED_STACKS)
    if expires and expires > GetTime() then
        cat.lines[2] = format(L["Ends in %s"], SecondsToTime(expires - GetTime()))
    end
    local left = expires and expires > 0 and expires - GetTime()
    local soon = left and left < WELL_RESTED_SOON
    cat.soon = soon
    if stacks >= WELL_RESTED_STACKS and not soon then
        cat.status = OK
        return cat
    end

    local start, duration
    if C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(SLEEPING_BAG) end
    start, duration = Plain(start) or 0, Plain(duration) or 0
    local wait = start + duration - GetTime()
    if duration > 2 and wait > 0 then
        cat.lines[#cat.lines + 1] = format(L["Sleeping bag ready in %s"], SecondsToTime(wait)) -- shown, not counted
    else
        cat.status = WARN
        if stacks >= WELL_RESTED_STACKS then
            Tip(cat, 22, format(L["Sleep in your sleeping bag: the experience bonus ends in %s."], SecondsToTime(math.max(left, 1))))
        else
            Tip(cat, 22, format(L["Sleep in your sleeping bag: 1 minute per stack of experience bonus (%d / %d)."], stacks, WELL_RESTED_STACKS))
        end
    end
    return cat
end

local function ReadTalentPoints()
    local configID = C_ClassTalents.GetActiveConfigID()
    local total = 0
    for _, treeID in ipairs(C_Traits.GetConfigInfo(configID).treeIDs) do
        for _, currency in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false)) do
            total = total + currency.quantity
        end
    end
    return total
end

-- Number of talent points left to spend, or nil when the game doesn't tell. On Forever,
-- GetNumUnspentTalents answers 0 even with points left, and the older functions don't exist.
local function UnspentTalentCount()
    if not (C_ClassTalents and C_Traits) then return end
    local ok, total = pcall(ReadTalentPoints) -- also fails on secret values
    return ok and total or nil
end

-- Whether talent points are left to spend, or nil when the game doesn't tell. Fallback only: on
-- Forever it was seen answering true with every point spent.
local function HasUnspentTalents()
    local hasUnspent = C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints
    if not hasUnspent then return end
    local ok, spec, class = pcall(hasUnspent)
    if not ok or (issecretvalue and (issecretvalue(spec) or issecretvalue(class))) then return end
    return (spec or class) and true or false
end

local function CheckBags(inv)
    local cat = NewCategory("bags", L["Bags"])
    local used = inv.total > 0 and (inv.total - inv.free) / inv.total * 100 or 0
    cat.lines[1] = format(L["Free slots: %d / %d (%d %% full)"], inv.free, inv.total, used + 0.5)
    local equipped = 0
    for bag = 1, 4 do if (NumSlots(bag) or 0) > 0 then equipped = equipped + 1 end end
    cat.lines[2] = format(L["Bags equipped: %d / 4"], equipped)
    cat.value = format("%d / %d", inv.free, db.slots)
    cat.pct = (inv.free >= db.slots or db.slots == 0) and 100 or inv.free / db.slots * 100
    if inv.free == 0 then
        cat.status = BAD
        Tip(cat, 85, L["Your bags are full: sell or destroy some items."])
    elseif inv.free < db.slots then
        cat.status = WARN
        Tip(cat, 40, format(L["Only %d free slot(s) in your bags."], inv.free))
    else
        cat.status = OK
    end
    if equipped < 4 then Tip(cat, 20, L["You still have empty bag slots."]) end
    return cat
end

local function RunScan()
    local inv = ScanBags()
    local want = { amount = {} }
    local cats = {}
    local function add(c) if c then cats[#cats + 1] = c end end
    -- A check turned off counts nowhere: not in the list, the score, the alerts or at merchants.
    if db.checkArmor then add(CheckArmor()) end
    if db.checkFood then add(CheckFoodOrDrink(inv, "food", want)) end
    if db.checkDrink and UsesMana() then add(CheckFoodOrDrink(inv, "drink", want)) end
    if db.checkPotions then add(CheckPotions(inv)) end
    if db.checkAmmo then add(CheckAmmo(inv, want)) end
    if db.checkAmmo then add(CheckPetFood()) end
    if db.checkShards then add(CheckShards()) end
    if db.checkReagents then CheckReagents(want, add) end
    if db.checkElixirs then add(CheckElixirs(inv)) end
    if db.checkSleep then add(CheckSleep()) end
    if db.checkBags then add(CheckBags(inv)) end

    local sum, n, tips = 0, 0, {}
    for _, c in ipairs(cats) do
        if c.status then sum, n = sum + c.pct, n + 1 end
        for _, t in ipairs(c.tips) do tips[#tips + 1] = t end
    end
    table.sort(tips, function(a, b) return a.prio > b.prio end)
    -- Shown apart: talents are not supplies, so they stay out of the list and of the score.
    local talentPoints, talentsToSpend = nil, false
    if db.checkTalents and UnitLevel("player") >= 10 then
        talentPoints = UnspentTalentCount()
        if talentPoints then
            talentsToSpend = talentPoints > 0
        else
            talentsToSpend = HasUnspentTalents() == true
        end
    end
    return {
        cats = cats, tips = tips, want = want, score = n > 0 and math.floor(sum / n + 0.5) or 100,
        talentsToSpend = talentsToSpend, talentPoints = talentPoints,
    }
end

local function Verdict(score)
    if score >= 85 then return L["READY FOR ADVENTURE"], 0.2, 1, 0.2 end
    if score >= 55 then return L["READY, WITH CAVEATS"], 1, 0.63, 0.13 end
    return L["NOT PREPARED"], 1, 0.25, 0.25
end

---------------------------------------------------------------------------
-- Window: the player in 3D on the left, reacting to the verdict, with the score stamped in wax. On the
-- right, the verdict banner, one line with its advice per problem, then the checks that passed as a
-- row of icons. Everything is revealed step by step; clicking the window skips to the end.
---------------------------------------------------------------------------

local WIDTH, LEFT_W, MIN_HEIGHT = 590, 240, 420
local SEAL_X, SEAL_Y = 60, 58
local RIGHT_W = 278
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local GOLD = { 1, 0.82, 0 }
local MAX_WORN = 5
-- Animations of the character: standing, cheering, asking, refusing.
local STAND, CHEER, QUESTION, NO = 0, 68, 65, 186
local STAMP_SECONDS = 0.3
local STAR_SECONDS = 2
local PASSED_SIZE, PASSED_GAP = 26, 5

local function Snd(id)
    if db.sound and id then PlaySound(id, "SFX") end
end
local function Clamp01(x) return math.max(0, math.min(1, x)) end
local function EaseOut(p) return 1 - (1 - p) ^ 3 end

local Spaced = ns.Spaced

local function StatusColor(status)
    if status == OK then return 0.3, 0.85, 0.3 end
    if status == WARN then return 1, 0.63, 0.13 end
    if status == BAD then return 1, 0.25, 0.25 end
    return 0.5, 0.5, 0.5 -- informative only
end

local win = CreateFrame("Frame", "TinkerwiseCheckupFrame", UIParent, "BackdropTemplate")
win:SetSize(WIDTH, MIN_HEIGHT)
win:SetPoint("CENTER", 0, 40)
win:SetFrameStrata("DIALOG")
win:SetMovable(true)
win:SetClampedToScreen(true)
win:EnableMouse(true)
win:Hide()
tinsert(UISpecialFrames, "TinkerwiseCheckupFrame")
local winSolid = TW:AddSolidBackground(win, 0.14, 0.1, 0.06) -- colors: see TW:OnTheme below
win:SetToplevel(true) -- comes in front as a whole when shown or clicked
CreateFrame("Button", nil, win, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

-- Left: the character ------------------------------------------------------------

local stage = CreateFrame("Frame", nil, win)
local stageBg = stage:CreateTexture(nil, "BACKGROUND")
stageBg:SetAllPoints()
stageBg:SetTexture(WHITE)
local stageFloor = stage:CreateTexture(nil, "BORDER") -- a soft light at the feet
stageFloor:SetTexture(CIRCLE)
stageFloor:SetBlendMode("ADD")
stageFloor:SetSize(170, 44)
stageFloor:SetPoint("BOTTOM", 0, 4)

local model
do
    local ok, frame = pcall(CreateFrame, "PlayerModel", nil, stage)
    if ok and frame then
        model = frame
        model:SetAllPoints()
        model:EnableMouse(false)
        model:SetScript("OnAnimFinished", function(self) pcall(self.SetAnimation, self, STAND) end)
    end
end

local function ShowCharacter()
    if not model then return end
    pcall(function()
        model:SetUnit("player")
        model:SetPortraitZoom(0)
        model:SetCamDistanceScale(1.1)
        model:SetRotation(0.2)
        model:SetAnimation(STAND)
    end)
end

local function React(score)
    if not model then return end
    local anim = score >= 85 and CHEER or score >= 55 and QUESTION or NO
    pcall(function()
        if model:HasAnimation(anim) then model:SetAnimation(anim) end
    end)
end

local playerName = stage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local playerInfo = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

-- An icon with a border in the color of its state.
local function Icon(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetTexture(WHITE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1.5, -1.5)
    b.icon:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local wornIcons = {} -- the worn out pieces, next to the character
for i = 1, MAX_WORN do
    local b = Icon(stage, 30)
    b:SetFrameLevel(stage:GetFrameLevel() + 10)
    b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 44)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", self.slot)
        GameTooltip:Show()
    end)
    b:Hide()
    wornIcons[i] = b
end

-- Left: the wax seal, a disk with uneven edges and the score pressed in it ---------

local function Disk(parent, size, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, sub)
    t:SetTexture(CIRCLE)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    t:SetVertexColor(r, g, b, a)
    return t
end
local seal = CreateFrame("Frame", nil, win)
seal:SetSize(84, 84)
seal:SetFrameLevel(win:GetFrameLevel() + 20) -- over the character when it comes down
seal:SetPoint("CENTER", win, "BOTTOMLEFT", SEAL_X, SEAL_Y)
local wax = { dark = {}, main = {} }
do
    local function Blob(list, size, x, y, sub)
        local t = Disk(seal, size, 1, 1, 1, 1, sub)
        t:ClearAllPoints()
        t:SetPoint("CENTER", x, y)
        list[#list + 1] = t
    end
    Blob(wax.dark, 80, 1, -2, 1)
    Blob(wax.main, 78, 0, 0, 3)
    for i = 1, 11 do
        local angle = i / 11 * 2 * math.pi
        local size = 22 + (i * 7) % 11
        local away = 31 + (i * 5) % 4
        local x, y = math.sin(angle) * away, math.cos(angle) * away
        Blob(wax.dark, size, x + 1, y - 2, 1)
        Blob(wax.main, size, x, y, 3)
    end
    Blob(wax.dark, 64, 0, 0, 4) -- the edge left by the stamp
    Blob(wax.main, 61, 0, -1, 5)
end
local sealFlash = Disk(seal, 110, 1, 0.9, 0.6, 1, 7)
sealFlash:SetBlendMode("ADD")

local star = win:CreateTexture(nil, "ARTWORK") -- when everything is perfect
star:SetTexture("Interface\\Cooldown\\starburst")
star:SetBlendMode("ADD")
star:SetSize(220, 220)
star:SetPoint("CENTER", seal)
star:SetAlpha(0)

local scoreText = seal:CreateFontString(nil, "OVERLAY")
scoreText:SetFont(TITLE_FONT, 20, "")
scoreText:SetPoint("CENTER")
scoreText:SetTextColor(1, 0.93, 0.8)

-- Right: bilan -----------------------------------------------------------------

local right = CreateFrame("Frame", nil, win)
right:SetWidth(RIGHT_W)
right:SetPoint("TOPRIGHT", -24, 0)
right:SetPoint("BOTTOMRIGHT", -24, 0)

local subtitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", 0, -28)

local title = right:CreateFontString(nil, "OVERLAY")
title:SetFont(TITLE_FONT, 30, "")
title:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -2)
title:SetText(L["Summary"])

local banner = CreateFrame("Frame", nil, right, "BackdropTemplate")
banner:SetSize(RIGHT_W, 30)
banner:SetPoint("TOPLEFT", 0, -86)
local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bannerText:SetPoint("CENTER")
local bannerFlash = banner:CreateTexture(nil, "OVERLAY")
bannerFlash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
bannerFlash:SetBlendMode("ADD")
bannerFlash:SetPoint("TOPLEFT", -40, 26)
bannerFlash:SetPoint("BOTTOMRIGHT", 40, -26)

local scanning = right:CreateFontString(nil, "OVERLAY")
scanning:SetFont(TITLE_FONT, 15, "")
scanning:SetPoint("CENTER", banner, "CENTER")
scanning:SetText(L["Inspecting your pack..."])

local function CategoryTooltip(self)
    local cat = self.cat
    if not cat then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if cat.item then
        GameTooltip:SetItemByID(cat.item)
        GameTooltip:AddLine(" ")
    else
        GameTooltip:AddLine(cat.name)
    end
    for _, line in ipairs(cat.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
    for _, tip in ipairs(cat.tips) do GameTooltip:AddLine(tip.text, 1, 0.82, 0, true) end
    GameTooltip:Show()
end

-- A problem: icon, name, count, bar and advice.
local rows = {}
local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, right)
    r:SetWidth(RIGHT_W)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.box = Icon(r, 28)
    r.box:EnableMouse(false)
    r.box:SetPoint("CENTER", r, "TOPLEFT", 16, -17)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.value:SetPoint("TOPRIGHT", -4, -3)
    r.value:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("TOPLEFT", 37, -3)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.barBg = r:CreateTexture(nil, "BACKGROUND")
    r.barBg:SetColorTexture(0, 0, 0, 0.5)
    r.barBg:SetHeight(6)
    r.barBg:SetPoint("TOPLEFT", 37, -21)
    r.barBg:SetPoint("TOPRIGHT", -4, -21)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.bar:SetPoint("TOPLEFT", r.barBg)
    r.bar:SetPoint("BOTTOMLEFT", r.barBg)
    r.tip = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.tip:SetPoint("TOPLEFT", 37, -31)
    r.tip:SetWidth(RIGHT_W - 41)
    r.tip:SetJustifyH("LEFT")
    r.tip:SetTextColor(0.9, 0.84, 0.72)
    r:SetScript("OnEnter", CategoryTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

-- A check that passed.
local passed = {}
local function Passed(i)
    if passed[i] then return passed[i] end
    local b = Icon(right, PASSED_SIZE)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(14, 14)
    b.check:SetPoint("BOTTOMRIGHT", 4, -4)
    b.check:SetTexture(STATUS_ICON[OK])
    b:SetScript("OnEnter", CategoryTooltip)
    passed[i] = b
    return b
end

-- Notice under the list, only when talent points are left to spend.
local talentNote = CreateFrame("Frame", nil, right, "BackdropTemplate")
talentNote:SetSize(RIGHT_W, 26)
local talentIcon = talentNote:CreateTexture(nil, "ARTWORK")
talentIcon:SetSize(15, 15)
talentIcon:SetPoint("LEFT", 7, 0)
talentIcon:SetTexture(ICONS.talents)
talentIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local talentText = talentNote:CreateFontString(nil, "OVERLAY", "GameFontNormal")
talentText:SetPoint("LEFT", talentIcon, "RIGHT", 6, 0)
talentText:SetTextColor(1, 0.63, 0.13)
talentNote:Hide()

local function OpenTalents()
    if InCombatLockdown() then
        TW:Print(L["cannot open talents in combat."])
        return
    end
    local open = PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab or ToggleTalentFrame
    if not (open and pcall(open)) then
        TW:Print(L["the talent window could not be opened."])
        return
    end
    win:Hide()
end

talentNote:EnableMouse(true)
talentNote:SetScript("OnMouseUp", function(_, mouse)
    if mouse == "LeftButton" then OpenTalents() end
end)
talentNote:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Click to open your talents"])
    GameTooltip:Show()
end)
talentNote:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(1, 0.63, 0.13, 0.9)
    GameTooltip:Hide()
end)

local tipsTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tipsTitle:SetText(Spaced(L["ADVICE"]))

local tipLines = {}
local function TipLine(i)
    if tipLines[i] then return tipLines[i] end
    local fs = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(RIGHT_W)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.9, 0.84, 0.72)
    tipLines[i] = fs
    return fs
end

local refresh = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
refresh:SetSize(100, 22)
refresh:SetText(L["Rerun"])

local closeButton = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
closeButton:SetSize(100, 22)
closeButton:SetPoint("BOTTOMRIGHT", -20, 18)
closeButton:SetText(L["Close"])
closeButton:SetScript("OnClick", function() win:Hide() end)
refresh:SetPoint("RIGHT", closeButton, "LEFT", -6, 0)

-- Backdrops and colors (gold or the class's: Core.lua, TW:OnTheme) ---------------

local function NoteBackdrop(edge)
    return {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }
end

win:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
banner:SetBackdrop(NoteBackdrop(14))
talentNote:SetBackdrop(NoteBackdrop(12))
stage:SetPoint("TOPLEFT", 16, -16)
stage:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", LEFT_W + 16, 96)
playerName:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 112, 58)
playerName:SetWidth(144)
playerName:SetJustifyH("LEFT")
playerName:SetWordWrap(false)
playerInfo:SetPoint("TOPLEFT", playerName, "BOTTOMLEFT", 0, -3)

TW:OnTheme(function(theme)
    GOLD = theme.accent
    local a, t, m = theme.accent, theme.title, theme.muted
    win:SetBackdropColor(theme.backdrop[1], theme.backdrop[2], theme.backdrop[3], 1)
    winSolid:SetColorTexture(theme.solid[1], theme.solid[2], theme.solid[3], 0.96)
    banner:SetBackdropColor(theme.banner[1], theme.banner[2], theme.banner[3], 0.95)
    banner:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    talentNote:SetBackdropColor(theme.banner[1], theme.banner[2], theme.banner[3], 0.6)
    talentNote:SetBackdropBorderColor(1, 0.63, 0.13, 0.9)
    if CreateColor then
        pcall(stageBg.SetGradient, stageBg, "VERTICAL", CreateColor(a[1] * 0.35, a[2] * 0.35, a[3] * 0.35, 0.9),
            CreateColor(0, 0, 0, 0.35))
    else
        stageBg:SetVertexColor(a[1] * 0.2, a[2] * 0.2, a[3] * 0.2, 0.8)
    end
    stageFloor:SetVertexColor(a[1], a[2], a[3], 0.25)
    playerName:SetTextColor(t[1], t[2], t[3])
    playerInfo:SetTextColor(m[1], m[2], m[3])
    subtitle:SetTextColor(m[1], m[2], m[3])
    title:SetTextColor(t[1], t[2], t[3])
    scanning:SetTextColor(a[1], a[2], a[3])
    tipsTitle:SetTextColor(a[1], a[2], a[3])
end)

-- Animation ----------------------------------------------------------------------

local anim = { done = true }

win:SetScript("OnUpdate", function(_, elapsed)
    -- The burst of light of a perfect score, once everything is in.
    if anim.star then
        anim.star = anim.star + elapsed
        local p = anim.star / STAR_SECONDS
        star:SetAlpha(p < 0.2 and p / 0.2 or Clamp01((1 - p) / 0.8))
        star:SetRotation(anim.star * 0.6)
        if p >= 1 then
            anim.star = nil
            star:SetAlpha(0)
        end
    end
    if anim.done then return end
    local t = anim.t + elapsed
    anim.t = t
    local result, s = anim.result, anim.speed

    -- 1. one check per beat: the problems with their bar, then the icons of the others
    local started = 0
    for i, item in ipairs(anim.items) do
        local u = t - item.start
        if u >= 0 then
            started = started + 1
            local frame, cat = item.frame, item.cat
            frame:SetAlpha(Clamp01(u / 0.15))
            local pop = u < 0.25 and 1.8 - 0.8 * EaseOut(Clamp01(u / 0.25)) or 1
            if frame.box then
                frame.box:SetScale(pop)
                frame.box:SetPoint("CENTER", frame, "TOPLEFT", 16 / pop, -17 / pop)
                local width = frame.barBg:GetWidth() * cat.pct / 100 * EaseOut(Clamp01(u / 0.4))
                frame.bar:SetWidth(math.max(width, 0.01))
            end
            if not anim.played[i] then
                anim.played[i] = true
                Snd(cat.status == BAD and SOUNDKIT.IG_QUEST_FAILED
                    or cat.status == WARN and SOUNDKIT.IG_QUEST_LIST_OPEN
                    or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
        end
    end
    subtitle:SetText(Spaced(format(L["%d STEPS CHECKED"], started)))

    -- 2. the verdict banner lands, and the seal is stamped
    local v = t - anim.bannerStart
    scanning:SetAlpha(v < 0 and (0.55 + 0.45 * math.sin(t * 5)) or 0)
    if v >= 0 then
        if not anim.bannerPlayed then
            anim.bannerPlayed = true
            Snd(result.score >= 100 and 888 or result.score >= 85 and 878 or result.score >= 55 and 3081
                or SOUNDKIT.IG_QUEST_FAILED)
            React(result.score)
            if result.score >= 100 then anim.star = 0 end
        end
        local p = Clamp01(v / STAMP_SECONDS)
        seal:SetAlpha(Clamp01(p * 2))
        seal:SetScale(1 + 1.5 * (1 - p * p))
        seal:SetPoint("CENTER", win, "BOTTOMLEFT", SEAL_X / seal:GetScale(), SEAL_Y / seal:GetScale())
        if p >= 1 and not anim.stamped then
            anim.stamped = true
            Snd(SOUNDKIT.IG_ABILITY_PAGE_TURN)
        end
        sealFlash:SetAlpha(p < 1 and 0 or 0.6 * Clamp01(1 - (v - STAMP_SECONDS) / 0.5))
        banner:SetAlpha(Clamp01(v / 0.15))
        banner:SetScale(1 + 0.35 * (1 - EaseOut(Clamp01(v / 0.3))))
        bannerFlash:SetAlpha(Clamp01(1 - v / 0.9))
    end

    -- 3. other advice
    for i, fs in ipairs(anim.tips) do
        fs:SetAlpha(Clamp01((t - anim.tipStart - (i - 1) * 0.25 * s) / 0.3))
    end
    tipsTitle:SetAlpha(Clamp01((t - anim.tipStart + 0.2) / 0.3))
    talentNote:SetAlpha(tipsTitle:GetAlpha())

    if t > anim.finish then anim.done = true end
end)

-- Click anywhere on the window to skip the animation.
win:SetScript("OnMouseUp", function(_, mouse)
    if mouse == "LeftButton" and not anim.done then
        for i in ipairs(anim.items) do anim.played[i] = true end -- no burst of sounds
        anim.t = anim.finish - 0.01
    end
end)

-- The most important advice of a check.
local function FirstTip(cat)
    local best
    for _, tip in ipairs(cat.tips) do
        if not best or tip.prio > best.prio then best = tip end
    end
    return best
end

local function Render(result)
    local s = db.quick and 0.4 or 1
    local label, vr, vg, vb = Verdict(result.score)
    local verdict = result.score >= 85 and OK or result.score >= 55 and WARN or BAD
    local wr, wg, wb = 0.62, 0.07, 0.06
    if verdict == OK then wr, wg, wb = 0.16, 0.45, 0.12 elseif verdict == WARN then wr, wg, wb = 0.75, 0.38, 0.04 end
    for _, blob in ipairs(wax.main) do blob:SetVertexColor(wr, wg, wb) end
    for _, blob in ipairs(wax.dark) do blob:SetVertexColor(wr * 0.5, wg * 0.5, wb * 0.5) end
    seal:SetAlpha(0)
    sealFlash:SetAlpha(0)
    bannerText:SetText(label)
    bannerText:SetTextColor(vr, vg, vb)
    banner:SetAlpha(0)
    bannerFlash:SetVertexColor(vr, vg, vb)
    bannerFlash:SetAlpha(0)
    star:SetAlpha(0)
    star:SetVertexColor(vr, vg, vb)
    playerName:SetText(TW:PlayerName())
    playerInfo:SetText(format("%s · %d", UnitClass("player"), UnitLevel("player")))
    scoreText:SetText(format("%d %%", result.score))

    -- The problems first, the worst ones on top.
    local problems, fine, worn = {}, {}, {}
    for i, cat in ipairs(result.cats) do
        local tip = FirstTip(cat)
        local entry = { cat = cat, tip = tip, order = i }
        if cat.status == BAD or cat.status == WARN then
            problems[#problems + 1] = entry
        else
            fine[#fine + 1] = entry
        end
        if cat.worn then worn = cat.worn end
    end
    table.sort(problems, function(a, b)
        if a.cat.status ~= b.cat.status then return a.cat.status < b.cat.status end
        local pa, pb = a.tip and a.tip.prio or 0, b.tip and b.tip.prio or 0
        if pa ~= pb then return pa > pb end
        return a.order < b.order
    end)

    for i, b in ipairs(wornIcons) do
        local piece = worn[i]
        if piece then
            b.slot = piece.slot
            b.icon:SetTexture(GetInventoryItemTexture("player", piece.slot))
            local r, g, bl = StatusColor(piece.pct < 10 and BAD or WARN)
            b.border:SetVertexColor(r, g, bl)
            b.text:SetText(format("%d %%", piece.pct + 0.5))
            b.text:SetTextColor(r, g, bl)
        end
        b:SetShown(piece ~= nil)
    end

    local y = -126
    local items = {}
    for i, entry in ipairs(problems) do
        local cat, row = entry.cat, Row(i)
        local r, g, b = StatusColor(cat.status)
        row.cat = cat
        row.box.icon:SetTexture(cat.icon)
        row.box.border:SetVertexColor(r, g, b)
        row.name:SetText(cat.name)
        row.value:SetText(cat.value or format("%d %%", cat.pct + 0.5))
        row.value:SetTextColor(r, g, b)
        row.bar:SetVertexColor(r, g, b)
        row.bar:SetWidth(0.01)
        row.tip:SetText(entry.tip and entry.tip.text or "")
        local height = entry.tip and 31 + row.tip:GetStringHeight() + 3 or 34
        row:SetHeight(math.max(height, 36))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:SetAlpha(0)
        row:Show()
        items[#items + 1] = { frame = row, cat = cat, start = 0.4 + (#items) * 0.35 * s }
        y = y - row:GetHeight() - 4
    end
    for i = #problems + 1, #rows do rows[i]:Hide(); rows[i].cat = nil end

    if #fine > 0 then
        y = y - 4
        local perLine = math.floor((RIGHT_W + PASSED_GAP) / (PASSED_SIZE + PASSED_GAP))
        for i, entry in ipairs(fine) do
            local cat, b = entry.cat, Passed(i)
            b.cat = cat
            b.icon:SetTexture(cat.icon)
            b.border:SetVertexColor(StatusColor(cat.status))
            b.check:SetShown(cat.status == OK)
            b.icon:SetDesaturated(cat.status == nil and cat.pct == 0)
            b:ClearAllPoints()
            local column, line = (i - 1) % perLine, math.floor((i - 1) / perLine)
            b:SetPoint("TOPLEFT", column * (PASSED_SIZE + PASSED_GAP), y - line * (PASSED_SIZE + 8))
            b:SetAlpha(0)
            b:Show()
            items[#items + 1] = { frame = b, cat = cat, start = 0.4 + (#items) * 0.35 * s }
        end
        y = y - math.ceil(#fine / perLine) * (PASSED_SIZE + 8)
    end
    for i = #fine + 1, #passed do passed[i]:Hide(); passed[i].cat = nil end

    talentNote:SetShown(result.talentsToSpend)
    talentNote:SetAlpha(0)
    if result.talentsToSpend then
        local points = result.talentPoints or 0
        talentText:SetText(points > 0 and format(L["%d talent point(s) to spend"], points)
            or L["Talent points left to spend"])
        talentNote:ClearAllPoints()
        talentNote:SetPoint("TOPLEFT", 0, y - 4)
        y = y - 34
    end

    -- The advice of the checks that passed; the others show it on their own line.
    local extra = {}
    for _, entry in ipairs(fine) do
        for _, tip in ipairs(entry.cat.tips) do extra[#extra + 1] = tip end
    end
    table.sort(extra, function(a, b) return a.prio > b.prio end)
    local texts = {}
    for i = 1, math.min(2, #extra) do texts[i] = L["“"] .. extra[i].text .. L["”"] end
    if #texts == 0 and #problems == 0 then texts[1] = L["“All in order. Good adventuring!”"] end

    tipsTitle:SetShown(#texts > 0)
    tipsTitle:ClearAllPoints()
    tipsTitle:SetPoint("TOPLEFT", 0, y - 6)
    tipsTitle:SetAlpha(0)
    if #texts > 0 then y = y - 24 end
    local shown = {}
    for i, text in ipairs(texts) do
        local fs = TipLine(i)
        fs:SetText(text)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetAlpha(0)
        fs:Show()
        shown[i] = fs
        y = y - fs:GetStringHeight() - 4
    end
    for i = #texts + 1, #tipLines do tipLines[i]:Hide() end
    win:SetHeight(math.max(MIN_HEIGHT, -y + 52))

    local last = items[#items]
    local itemsEnd = (last and last.start or 0) + 0.5 * s
    anim = {
        t = 0, result = result, speed = s, items = items, played = {}, tips = shown, bannerStart = itemsEnd,
    }
    anim.tipStart = itemsEnd + 0.5 * s
    anim.finish = anim.tipStart + #shown * 0.25 * s + 1
end

local function Open()
    Render(RunScan())
    win:Show()
    ShowCharacter() -- a model only loads once shown
end

refresh:SetScript("OnClick", Open)
win:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
win:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end)

---------------------------------------------------------------------------
-- Chat button (top of the chat button column)
---------------------------------------------------------------------------

local chatButton = TW:CreateRoundButton("TinkerwiseCheckupButton", UIParent, "Interface\\Icons\\INV_Misc_Note_01")
chatButton:SetMovable(true)
chatButton:SetClampedToScreen(true)
chatButton:Hide()

local CHAT_BUTTONS = {
    "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    "ChatFrameMenuButton", "ChatFrame1ButtonFrameUpButton", "FriendsMicroButton", "QuickJoinToastButton",
}

-- The chat buttons only settle after entering the world: the icon stays hidden until then.
local chatButtonReady = false

local function PlaceChatButton()
    chatButton:ClearAllPoints()
    if db.btnPoint then
        chatButton:SetPoint(db.btnPoint, UIParent, db.btnPoint, db.btnX, db.btnY)
        return
    end
    local top, topFrame
    for _, name in ipairs(CHAT_BUTTONS) do
        local f = _G[name]
        if f and f:IsShown() and f:GetTop() and (not top or f:GetTop() > top) then
            top, topFrame = f:GetTop(), f
        end
    end
    if topFrame then
        chatButton:SetPoint("BOTTOM", topFrame, "TOP", 0, 2)
    else
        chatButton:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPLEFT", -2, 2)
    end
end

chatButton:SetScript("OnClick", function(_, mouse)
    if win:IsShown() then
        win:Hide()
    else
        Open()
    end
end)
chatButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Pre-adventure check-up"])
    GameTooltip:AddLine(L["Left-click: run the check-up"], 1, 1, 1)
    GameTooltip:Show()
end)
chatButton:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- Automatic checks
---------------------------------------------------------------------------

local wasResting, lastInstance

local sleepWarned = false -- once for each time the buff is about to end

local function WarnLeavingTown()
    local result = RunScan()
    local bad = {}
    local sleep -- the sleeping bag shows on the screen too, whatever else is wrong
    for _, c in ipairs(result.cats) do
        if c.status == BAD or (c.key == "sleep" and c.status == WARN) then
            if c.key == "sleep" then
                sleep = c.tips[1]
                sleepWarned = sleepWarned or c.soon or false
            end
            for _, t in ipairs(c.tips) do bad[#bad + 1] = t end
        end
    end
    if result.talentsToSpend then bad[#bad + 1] = { prio = 70, text = L["Spend your talent points."] } end
    if #bad == 0 then return end
    table.sort(bad, function(a, b) return a.prio > b.prio end)
    RaidNotice_AddMessage(RaidWarningFrame, L["Tinkerwise: "] .. bad[1].text, ChatTypeInfo["RAID_WARNING"])
    if sleep and sleep ~= bad[1] then
        RaidNotice_AddMessage(RaidWarningFrame, L["Tinkerwise: "] .. sleep.text, ChatTypeInfo["RAID_WARNING"])
    end
    if db.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    for _, t in ipairs(bad) do TW:Print(RED .. t.text .. "|r") end
end

local SLEEP_CHECK_EVERY = 20
local sleepTicker

-- Wherever the player is; during a fight or a flight, or while the bag is not ready, it waits.
local function WarnSleep()
    if not (db.checkSleep and db.sleepAlert) or InCombatLockdown() or UnitOnTaxi("player") or UnitIsDeadOrGhost("player") then return end
    local cat = CheckSleep()
    if not (cat and cat.soon) then
        sleepWarned = false
    elseif cat.status == WARN and not sleepWarned then
        sleepWarned = true
        local text = cat.tips[1].text
        RaidNotice_AddMessage(RaidWarningFrame, L["Tinkerwise: "] .. text, ChatTypeInfo["RAID_WARNING"])
        if db.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
        TW:Print(ORANGE .. text .. "|r")
    end
end

-- Which need an item of a merchant fills, and how many are missing; nil for none.
local function Match(want, id)
    if want.ammo == id then return "ammo", want.amount.ammo end
    if want.reagents and want.reagents[id] then return "reagent" .. id, want.reagents[id] end
    local kind = ConsumableKind(id)
    if kind and want[kind] and MinLevel(id) == want[kind] and MinLevel(id) <= UnitLevel("player") then
        return kind, want.amount[kind]
    end
end

-- For Restock.lua.
ns.CheckupMatch = Match
function ns.CheckupWant() return db and RunScan().want end
function ns.CheckupRestock() return db and TW.modules.Checkup.active and db.restock end

local function MerchantHints()
    local want = RunScan().want
    local links = {}
    for i = 1, GetMerchantNumItems() do
        local link = GetMerchantItemLink(i)
        local id = link and GetItemInfoInstant(link)
        if id then
            local match = Match(want, id)
            if match then links[#links + 1] = link end
        end
    end
    if #links > 0 then
        TW:Print(L["this merchant sells what you need: "] .. table.concat(links, " "))
    end
    if CanMerchantRepair() then
        local cost = GetRepairAllCost()
        if cost and cost > 0 then TW:Print(L["repair: "] .. GetCoinTextureString(cost)) end
    end
end

local TOWN_WARN_EVERY = 300    -- seconds between "leaving town" alerts
local INSTANCE_RECHECK = 1800  -- seconds before the same instance triggers a check-up again
local lastTownWarn, lastInstanceAt = -TOWN_WARN_EVERY, 0

-- For delayed actions: the module may have been disabled in the meantime.
local function IfActive(action)
    return function()
        if TW.modules.Checkup.active then action() end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_UPDATE_RESTING" then
        local resting = IsResting()
        if wasResting and not resting and db.autoRest and GetTime() - lastTownWarn >= TOWN_WARN_EVERY then
            lastTownWarn = GetTime()
            C_Timer.After(1, IfActive(WarnLeavingTown))
        end
        wasResting = resting
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            chatButtonReady = true
            if not TW.modules.Checkup.active then return end
            PlaceChatButton()
            chatButton:SetShown(db.chatButton)
        end)
        wasResting = IsResting()
        local inInstance, kind = IsInInstance()
        local name = GetInstanceInfo()
        if inInstance and (kind == "party" or kind == "raid") then
            -- Not again after a corpse run in the same instance.
            if db.autoInstance and (name ~= lastInstance or GetTime() - lastInstanceAt > INSTANCE_RECHECK) then
                C_Timer.After(3, IfActive(Open))
            end
            lastInstance, lastInstanceAt = name, GetTime()
        end
    elseif event == "MERCHANT_SHOW" then
        if db.merchant then C_Timer.After(0.3, IfActive(MerchantHints)) end
    end
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

-- Shown in the game's Edit Mode: same size and spot as the window, no scan.
local preview = CreateFrame("Frame", nil, UIParent)
preview:SetFrameStrata("DIALOG")
preview:SetMovable(true)
preview:SetClampedToScreen(true)
preview:Hide()

local function ShowPreview(on)
    if on then
        win:Hide()
        preview:SetSize(win:GetSize())
        preview:ClearAllPoints()
        preview:SetPoint(win:GetPoint())
    end
    preview:SetShown(on)
end

local function ResetPosition()
    db.winPoint, db.btnPoint = nil, nil
    win:ClearAllPoints()
    win:SetPoint("CENTER", 0, 40)
    PlaceChatButton()
    if preview:IsShown() then ShowPreview(true) end
end

local mod = TW:NewModule("Checkup", {
    title = "Check-up",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    section = L["Adventure"],
    desc = L["Checks that you're ready to go: durability and repair cost, food and water suited to your level, potions, ammo suited to your level, class reagents, elixirs, unspent talent points and bag space. Button above the chat, right-click on the minimap button, or /tw checkup."]
        .. " " .. L["At a merchant, a button buys what is missing, up to your thresholds and after showing the price."],
    defaults = DEFAULTS,
    options = {
        { type = "execute", label = L["Run the check-up"], editMode = "never", func = function() Open() end },
        { type = "execute", label = L["Reset position"], editMode = "only", func = function() ResetPosition() end },
        { type = "header", label = L["Checks"] },
        { type = "toggle", key = "checkArmor", label = L["Armor"] },
        { type = "toggle", key = "checkFood", label = L["Food"] },
        { type = "toggle", key = "checkDrink", label = L["Water"] },
        { type = "toggle", key = "checkPotions", label = "Potions" },
        { type = "toggle", key = "checkAmmo", label = L["Ammo"] },
        { type = "toggle", key = "checkShards", label = L["Soul Shards"], class = "WARLOCK" },
        { type = "toggle", key = "checkReagents", label = L["Reagents"] },
        { type = "toggle", key = "checkElixirs", label = L["Elixirs"] },
        { type = "toggle", key = "checkSleep", label = L["Sleeping bag"] },
        { type = "toggle", key = "checkBags", label = L["Bags"] },
        { type = "toggle", key = "checkTalents", label = L["Unspent talent points"] },
        { type = "header", label = L["Thresholds"] },
        { type = "slider", key = "dura", label = L["Minimum durability (%)"], min = 10, max = 90, step = 5 },
        { type = "slider", key = "food", label = L["Minimum food"], min = 0, max = 40, step = 1 },
        { type = "slider", key = "drink", label = L["Minimum drinks"], min = 0, max = 40, step = 1 },
        { type = "slider", key = "elixirs", label = L["Minimum elixirs (0 = not counted)"], min = 0, max = 20, step = 1 },
        { type = "slider", key = "slots", label = L["Minimum free slots"], min = 0, max = 20, step = 1 },
        { type = "header", label = L["Automatic"] },
        { type = "toggle", key = "autoRest", label = L["Alert when leaving a city / inn"] },
        { type = "toggle", key = "sleepAlert", label = L["Alert when the sleeping bag bonus ends in less than 30 minutes"] },
        { type = "toggle", key = "autoInstance", label = L["Check-up when entering a dungeon / raid"] },
        { type = "toggle", key = "merchant", label = L["At a merchant, report what you need"] },
        { type = "toggle", key = "restock", label = L["At a merchant, button that buys what is missing"] },
        { type = "toggle", key = "chatButton", label = L["Button above the chat"] },
        { type = "toggle", key = "sound", label = L["Sounds"] },
        { type = "toggle", key = "quick", label = L["Fast animation"] },
    },
})

ns.AddToEditMode({
    frame = preview, mod = mod, label = "Check-up",
    OnEditing = ShowPreview,
    Save = function(point, x, y)
        db.winPoint, db.winX, db.winY = point, x, y
        win:ClearAllPoints()
        win:SetPoint(point, UIParent, point, x, y)
    end,
})
ns.AddToEditMode({
    frame = chatButton, mod = mod, label = L["Button above the chat"],
    IsAvailable = function() return mod.db.chatButton and chatButtonReady end,
    Save = function(point, x, y) db.btnPoint, db.btnX, db.btnY = point, x, y end,
})

for i = #mod.options, 1, -1 do
    local class = mod.options[i].class
    if class and class ~= select(2, UnitClass("player")) then table.remove(mod.options, i) end
end

-- The thresholds of your class, in a card of their own before the automatic checks. 0: not checked.
do
    local class = select(2, UnitClass("player"))
    local list = {}
    local function Slider(key, label, max, step)
        local opt = { type = "slider", key = key, label = label, min = 0, max = max, step = step or 1 }
        list[#list + 1] = opt
        return opt
    end
    if class == "HUNTER" then
        Slider("ammo", L["Minimum ammo for your weapon (0 = ignore)"], 3000, 100)
        Slider("petFood", L["Minimum pet food (0 = ignore)"], 40)
    elseif class == "WARRIOR" or class == "ROGUE" then
        Slider("ammoOther", L["Minimum ammo for your weapon (0 = ignore)"], 1000, 50)
    end
    for _, r in ipairs(REAGENTS[class] or {}) do
        local id = r[1]
        local opt = Slider("reagent" .. id, format(L["%s (0 = ignore)"], L["item #"] .. id), math.max(20, r[4] * 4))
        -- The name comes from the server: before the panel is first opened, as a rule.
        if Item and Item.CreateFromItemID then
            Item:CreateFromItemID(id):ContinueOnItemLoad(function()
                opt.label = format(L["%s (0 = ignore)"], GetItemInfo(id) or (L["item #"] .. id))
            end)
        end
    end
    if #list > 0 then
        for i, opt in ipairs(mod.options) do
            if opt.type == "header" and opt.label == L["Automatic"] then
                table.insert(mod.options, i, { type = "header", label = L["Class reminders"] })
                for j, added in ipairs(list) do table.insert(mod.options, i + j, added) end
                break
            end
        end
    end
end

function mod:Open() Open() end

function mod:OnEnable()
    db = self.db
    for _, r in ipairs(REAGENTS[select(2, UnitClass("player"))] or {}) do ItemName(r[1]) end
    for _, list in pairs(AMMO) do for _, a in ipairs(list) do ItemName(a[1]) end end -- warm item cache
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("MERCHANT_SHOW")
    wasResting = IsResting()
    sleepWarned = false
    if not sleepTicker then sleepTicker = C_Timer.NewTicker(SLEEP_CHECK_EVERY, WarnSleep) end
    ns.EnableRestock(db.restock)
    PlaceChatButton()
    chatButton:SetShown(db.chatButton and chatButtonReady)
    win:ClearAllPoints()
    if not db.winPoint then
        win:SetPoint("CENTER", 0, 40)
    else
        win:SetPoint(db.winPoint, UIParent, db.winPoint, db.winX, db.winY)
    end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if sleepTicker then
        sleepTicker:Cancel()
        sleepTicker = nil
    end
    ns.EnableRestock(false)
    chatButton:Hide()
    win:Hide()
    ShowPreview(false)
end

function mod:OnOptionChanged(key)
    if key == "restock" then ns.EnableRestock(db.restock) end
    if key == "chatButton" then chatButton:SetShown(db.chatButton) end
end

TW.commands.checkup = function()
    if mod.active then Open() else TW:Print(L["the Check-up module is disabled (/tw)."]) end
end
