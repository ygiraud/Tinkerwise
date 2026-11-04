-- Checkup: "am I ready to go?" report (durability, food, drink, potions, ammo, reagents, bags)
-- with a readiness score and the top tips. Also warns when leaving town, when entering a
-- dungeon, and points out what a merchant sells that you are missing.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local API = ns.API
local GetSpellInfo, GetItemInfo, GetItemInfoInstant = API.GetSpellInfo, API.GetItemInfo, API.GetItemInfoInstant
local GetItemCount, GetItemSpell = API.GetItemCount, API.GetItemSpell

local DEFAULTS = {
    dura = 30,          -- warn when an item is below this durability %
    food = 10,          -- minimum food count
    drink = 10,         -- minimum drink count (mana users)
    ammo = 800,         -- minimum ammo count (hunters)
    slots = 4,          -- minimum free bag slots
    sound = true,
    quick = false,      -- faster reveal animation
    centerIcon = "class", -- image in the ring: "class" emblem or player "portrait"
    chatButton = true,
    autoRest = true,    -- warn when leaving a rested area
    autoInstance = true,-- open the check-up when entering a dungeon / raid
    merchant = true,    -- list what a merchant sells that you need
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

-- Class reagents: { itemID, from level, to level, needed, critical, tip when not sold by vendors }
local REAGENTS = {
    MAGE = { { 17020, 56, 60, 5 }, { 17031, 20, 60, 2 }, { 17032, 40, 60, 1 }, { 17056, 12, 60, 5 } },
    PRIEST = { { 17028, 48, 59, 5 }, { 17029, 60, 60, 5 }, { 17056, 34, 60, 5 } },
    SHAMAN = { { 17030, 30, 60, 1, true } },
    WARLOCK = { { 6265, 10, 60, 3, true, L["Collect %s by finishing off monsters with Drain Soul (%d / %d)."] } },
    ROGUE = { { 5140, 22, 60, 5 } },
    PALADIN = { { 17033, 30, 60, 1 }, { 21177, 52, 60, 10 } },
    DRUID = { { 17034, 20, 29, 1 }, { 17035, 30, 39, 1 }, { 17036, 40, 49, 1 }, { 17037, 50, 59, 1 },
              { 17038, 60, 60, 1 }, { 17021, 50, 59, 5 }, { 17026, 60, 60, 5 } },
}

local DURA_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local ICONS = {
    armor = "Interface\\Icons\\Trade_BlackSmithing",
    food = "Interface\\Icons\\INV_Misc_Food_15",
    drink = "Interface\\Icons\\INV_Drink_07",
    potions = "Interface\\Icons\\INV_Potion_54",
    ammo = "Interface\\Icons\\INV_Ammo_Arrow_02",
    reagents = "Interface\\Icons\\INV_Misc_Dust_02",
    elixirs = "Interface\\Icons\\INV_Potion_61",
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
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    for _, slot in ipairs(DURA_SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            sum, n = sum + pct, n + 1
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
    if cat.status ~= OK then want[kind] = tier end
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
    if class ~= "HUNTER" or not kind then return end
    local cat = NewCategory("ammo", L["Ammo"])
    local level = UnitLevel("player")
    local total, bestLevel = 0, -1
    for id, count in pairs(inv.counts) do
        local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
        if classID == 6 and subclassID == (kind == "arrow" and 2 or 3) then
            total = total + count
            bestLevel = math.max(bestLevel, MinLevel(id))
        end
    end
    local best = BestVendorAmmo(kind, level)
    cat.lines[1] = format("%d %s", total, kind == "arrow" and L["arrows"] or L["bullets"])
    if best then cat.lines[2] = format(L["Recommended for your level: %s (lvl %d)"], ItemLink(best[1]), best[2]) end
    if not inv.quiver and level >= 10 then
        cat.lines[#cat.lines + 1] = ORANGE .. L["No quiver / ammo pouch equipped|r"]
        Tip(cat, 30, L["A quiver or ammo pouch speeds up your shots and frees up space."])
    end

    cat.status = OK
    if total == 0 then
        cat.status = BAD
        Tip(cat, 95, L["You are out of ammo!"])
    elseif total < db.ammo then
        cat.status = WARN
        Tip(cat, 55, format(L["Only %d ammo left: buy more."], total))
    end
    if best and total > 0 and bestLevel < best[2] then
        cat.status = math.min(cat.status, WARN)
        Tip(cat, 45, format(L["Switch to %s (lvl %d): more damage per shot."], ItemName(best[1]), best[2]))
    end
    cat.pct = math.min(total / db.ammo, 1) * 100
    if best and total > 0 and bestLevel < best[2] then cat.pct = cat.pct * 0.7 end
    if best and (cat.status ~= OK) then want.ammo = best[1] end
    return cat
end

local function CheckReagents(want)
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local list = REAGENTS[class]
    if not list then return end
    local cat = NewCategory("reagents", L["Reagents"])
    cat.status = OK
    local fill, n = 0, 0
    for _, r in ipairs(list) do
        local id, from, to, need, critical, farmTip = r[1], r[2], r[3], r[4], r[5], r[6]
        if level >= from and level <= to then
            local count = GetItemCount(id)
            fill, n = fill + math.min(count / need, 1), n + 1
            local color = count >= need and "" or (count == 0 and RED or ORANGE)
            cat.lines[#cat.lines + 1] = format("%s%s : %d|r", color, ItemName(id), count)
            if count < need then
                local status = (count == 0 and critical) and BAD or WARN
                cat.status = math.min(cat.status, status)
                Tip(cat, critical and 75 or 25, format(farmTip or L["Buy more %s (%d / %d)."], ItemName(id), count, need))
                if not farmTip then -- only vendor reagents are suggested at merchants
                    want.reagents = want.reagents or {}
                    want.reagents[id] = true
                end
            end
        end
    end
    if n == 0 then return end
    cat.pct = fill / n * 100
    return cat
end

local function CheckElixirs(inv)
    local level = UnitLevel("player")
    if level < 20 then return end
    local cat = NewCategory("elixirs", L["Elixirs"])
    local total = 0
    for id, count in pairs(inv.counts) do
        if ELIXIRS[id] then total = total + count end
    end
    cat.lines[1] = total > 0 and format(L["%d elixir(s) in your bags"], total) or L["No elixirs"]
    cat.pct = math.min(total / 2, 1) * 100 -- informative only, not counted in the score
    if total == 0 and level >= 30 then Tip(cat, 10, L["An elixir or two helps in dungeons and against elites."]) end
    return cat
end

local function CheckBags(inv)
    local cat = NewCategory("bags", L["Bags"])
    local used = inv.total > 0 and (inv.total - inv.free) / inv.total * 100 or 0
    cat.lines[1] = format(L["Free slots: %d / %d (%d %% full)"], inv.free, inv.total, used + 0.5)
    local equipped = 0
    for bag = 1, 4 do if (NumSlots(bag) or 0) > 0 then equipped = equipped + 1 end end
    cat.lines[2] = format(L["Bags equipped: %d / 4"], equipped)
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
    local want = {}
    local cats = {}
    local function add(c) if c then cats[#cats + 1] = c end end
    add(CheckArmor())
    add(CheckFoodOrDrink(inv, "food", want))
    if UsesMana() then add(CheckFoodOrDrink(inv, "drink", want)) end
    add(CheckPotions(inv))
    add(CheckAmmo(inv, want))
    add(CheckReagents(want))
    add(CheckElixirs(inv))
    add(CheckBags(inv))

    local sum, n, tips = 0, 0, {}
    for _, c in ipairs(cats) do
        if c.status then sum, n = sum + c.pct, n + 1 end
        for _, t in ipairs(c.tips) do tips[#tips + 1] = t end
    end
    table.sort(tips, function(a, b) return a.prio > b.prio end)
    return { cats = cats, tips = tips, want = want, score = n > 0 and math.floor(sum / n + 0.5) or 100 }
end

local function Verdict(score)
    if score >= 85 then return L["READY FOR ADVENTURE"], 0.2, 1, 0.2 end
    if score >= 55 then return L["READY, WITH CAVEATS"], 1, 0.63, 0.13 end
    return L["NOT PREPARED"], 1, 0.25, 0.25
end

---------------------------------------------------------------------------
-- Window: readiness ring on the left (player level on a die), "Bilan" on the right with the
-- verdict banner, one line per category with its percentage, and the top tips. Everything is
-- revealed step by step; clicking the window skips to the end.
---------------------------------------------------------------------------

local WIDTH = 500
local LEFT_W = 190
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local TICKS = 40
local GOLD = { 1, 0.82, 0 }

local function Snd(id)
    if db.sound and id then PlaySound(id, "SFX") end
end
local function Clamp01(x) return math.max(0, math.min(1, x)) end
local function EaseOut(p) return 1 - (1 - p) ^ 3 end

local Spaced = ns.Spaced

local function PctColor(p)
    if p >= 80 then return 0.3, 1, 0.3 end
    if p >= 40 then return 1, 0.63, 0.13 end
    return 1, 0.25, 0.25
end

local win = CreateFrame("Frame", "TinkerwiseCheckupFrame", UIParent, "BackdropTemplate")
win:SetSize(WIDTH, 320)
win:SetPoint("CENTER", 0, 40)
win:SetFrameStrata("DIALOG")
win:SetMovable(true)
win:SetClampedToScreen(true)
win:EnableMouse(true)
win:Hide()
tinsert(UISpecialFrames, "TinkerwiseCheckupFrame")
win:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
win:SetBackdropColor(0.45, 0.32, 0.2, 1) -- warm brown tint
CreateFrame("Button", nil, win, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

local sep = win:CreateTexture(nil, "ARTWORK")
sep:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
sep:SetWidth(1)
sep:SetPoint("TOPLEFT", LEFT_W, -26)
sep:SetPoint("BOTTOMLEFT", LEFT_W, 22)

-- Left: readiness ring ---------------------------------------------------------

local ring = CreateFrame("Frame", nil, win)
ring:SetSize(140, 140)
ring:SetPoint("TOP", win, "TOPLEFT", LEFT_W / 2 + 4, -34)

local function Disk(size, r, g, b, a, sub)
    local t = ring:CreateTexture(nil, "BACKGROUND", nil, sub)
    t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    t:SetVertexColor(r, g, b, a)
    return t
end
Disk(140, GOLD[1], GOLD[2], GOLD[3], 0.55, 1)  -- outer gold line
Disk(136, 0.07, 0.04, 0.02, 0.95, 2)           -- dark disk
Disk(98, GOLD[1], GOLD[2], GOLD[3], 0.35, 3)   -- inner gold line
Disk(95, 0.1, 0.06, 0.03, 1, 4)

local ticks = {}
for i = 1, TICKS do
    local angle = (i - 1) / TICKS * 2 * math.pi
    local t = ring:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetSize(3, 10)
    t:SetPoint("CENTER", ring, "CENTER", math.sin(angle) * 57, math.cos(angle) * 57)
    t:SetRotation(-angle)
    ticks[i] = t
end

-- Round class emblem in the centre, with the level in a small gold badge below it.
local emblem = ring:CreateTexture(nil, "ARTWORK", nil, 2)
emblem:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
emblem:SetSize(64, 64)
emblem:SetPoint("CENTER")
local dieGlow = ring:CreateTexture(nil, "ARTWORK", nil, 1) -- halo behind the emblem
dieGlow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
dieGlow:SetBlendMode("ADD")
dieGlow:SetSize(78, 78)
dieGlow:SetPoint("CENTER")

local badge = CreateFrame("Frame", nil, ring)
badge:SetSize(22, 22)
badge:SetPoint("CENTER", ring, "CENTER", 0, -30) -- stays inside the inner gold circle
badge:SetFrameLevel(ring:GetFrameLevel() + 2)
local badgeRim = badge:CreateTexture(nil, "BACKGROUND")
badgeRim:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
badgeRim:SetAllPoints()
badgeRim:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
local badgeBg = badge:CreateTexture(nil, "BORDER")
badgeBg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
badgeBg:SetSize(18, 18)
badgeBg:SetPoint("CENTER")
badgeBg:SetVertexColor(0.12, 0.07, 0.03, 1)
local levelText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
levelText:SetPoint("CENTER", 0, 1)
levelText:SetTextColor(1, 0.95, 0.8)

local scoreText = win:CreateFontString(nil, "OVERLAY")
scoreText:SetFont(TITLE_FONT, 30, "")
scoreText:SetPoint("TOP", ring, "BOTTOM", 0, -10)
local scoreLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
scoreLabel:SetPoint("TOP", scoreText, "BOTTOM", 0, -2)
scoreLabel:SetTextColor(0.75, 0.68, 0.55)
scoreLabel:SetText(L["readiness"])

local function SetRing(value, r, g, b)
    local filled = math.floor(value / 100 * TICKS + 0.5)
    for i, t in ipairs(ticks) do
        if i <= filled then t:SetVertexColor(r, g, b, 1) else t:SetVertexColor(0.35, 0.28, 0.2, 0.6) end
    end
    scoreText:SetText(format("%d %%", value + 0.5))
    scoreText:SetTextColor(r, g, b)
end

-- Right: bilan -----------------------------------------------------------------

local X = LEFT_W + 18
local RIGHT_W = WIDTH - X - 22

local subtitle = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", X, -28)
subtitle:SetTextColor(0.8, 0.7, 0.5)

local title = win:CreateFontString(nil, "OVERLAY")
title:SetFont(TITLE_FONT, 30, "")
title:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -2)
title:SetTextColor(1, 0.9, 0.7)
title:SetText(L["Summary"])

local banner = CreateFrame("Frame", nil, win, "BackdropTemplate")
banner:SetSize(RIGHT_W, 30)
banner:SetPoint("TOPLEFT", X, -86)
banner:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
banner:SetBackdropColor(0.3, 0.15, 0.05, 0.95)
banner:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bannerText:SetPoint("CENTER")
local bannerFlash = banner:CreateTexture(nil, "OVERLAY")
bannerFlash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
bannerFlash:SetBlendMode("ADD")
bannerFlash:SetPoint("TOPLEFT", -40, 26)
bannerFlash:SetPoint("BOTTOMRIGHT", 40, -26)

local scanning = win:CreateFontString(nil, "OVERLAY")
scanning:SetFont(TITLE_FONT, 15, "")
scanning:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
scanning:SetPoint("CENTER", banner, "CENTER")
scanning:SetText(L["Inspecting your pack..."])

local rows = {}
local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, win)
    r:SetSize(RIGHT_W, 18)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.iconHolder = CreateFrame("Frame", nil, r)
    r.iconHolder:SetSize(15, 15)
    r.iconHolder:SetPoint("LEFT", 4, 0)
    r.icon = r.iconHolder:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.iconHolder, "RIGHT", 6, 0)
    r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.pct:SetPoint("RIGHT", -4, 0)
    r.pct:SetJustifyH("RIGHT")
    r.dots = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.dots:SetPoint("LEFT", r.name, "RIGHT", 4, -1)
    r.dots:SetPoint("RIGHT", r, "RIGHT", -44, -1)
    r.dots:SetWordWrap(false)
    r.dots:SetJustifyH("LEFT")
    r.dots:SetText(string.rep(" .", 80))
    r:SetScript("OnEnter", function(self)
        if not self.cat then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.cat.name)
        for _, line in ipairs(self.cat.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local tipsTitle = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tipsTitle:SetText(Spaced("CONSEILS"))
tipsTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
local tipLines = {}
local function TipLine(i)
    if tipLines[i] then return tipLines[i] end
    local fs = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

-- Animation ----------------------------------------------------------------------

local anim = { done = true }

win:SetScript("OnUpdate", function(_, elapsed)
    if anim.done then
        -- slow breathing glow around the die once finished
        anim.idle = (anim.idle or 0) + elapsed
        dieGlow:SetAlpha(0.25 + 0.2 * math.sin(anim.idle * 2))
        return
    end
    local t = anim.t + elapsed
    anim.t = t
    local result, s = anim.result, anim.speed
    local vr, vg, vb = PctColor(result.score)

    -- 1. one category per beat, its percentage counting up
    local started = 0
    for i, cat in ipairs(result.cats) do
        local row, u = rows[i], t - anim.rowStart[i]
        if u >= 0 then
            started = started + 1
            row:SetAlpha(Clamp01(u / 0.15))
            row.iconHolder:SetScale(u < 0.25 and 1.8 - 0.8 * EaseOut(Clamp01(u / 0.25)) or 1)
            local p = cat.pct * EaseOut(Clamp01(u / 0.4))
            row.pct:SetText(format("%d %%", p + 0.5))
            row.pct:SetTextColor(PctColor(cat.pct))
            if not anim.played[i] then
                anim.played[i] = true
                Snd(cat.status == BAD and SOUNDKIT.IG_QUEST_FAILED
                    or cat.status == WARN and SOUNDKIT.IG_QUEST_LIST_OPEN
                    or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
        end
    end
    subtitle:SetText(Spaced(format(L["%d STEPS CHECKED"], started)))

    -- 2. the ring fills while the categories come in
    local rp = Clamp01(t / anim.bannerStart)
    SetRing(result.score * EaseOut(rp), vr, vg, vb)
    dieGlow:SetVertexColor(vr, vg, vb)
    dieGlow:SetAlpha(0.3 + 0.3 * math.sin(t * 6))

    -- 3. the verdict banner lands
    local v = t - anim.bannerStart
    scanning:SetAlpha(v < 0 and (0.55 + 0.45 * math.sin(t * 5)) or 0)
    if v >= 0 then
        if not anim.bannerPlayed then
            anim.bannerPlayed = true
            Snd(result.score >= 85 and 888 or result.score >= 55 and 3081 or SOUNDKIT.IG_QUEST_FAILED)
        end
        banner:SetAlpha(Clamp01(v / 0.15))
        banner:SetScale(1 + 0.35 * (1 - EaseOut(Clamp01(v / 0.3))))
        bannerFlash:SetAlpha(Clamp01(1 - v / 0.9))
    end

    -- 4. tips
    for i, fs in ipairs(anim.tips) do
        fs:SetAlpha(Clamp01((t - anim.tipStart - (i - 1) * 0.25 * s) / 0.3))
    end
    tipsTitle:SetAlpha(Clamp01((t - anim.tipStart + 0.2) / 0.3))

    if t > anim.finish then anim.done = true end
end)

-- Click anywhere on the window to skip the animation.
win:SetScript("OnMouseUp", function(_, mouse)
    if mouse == "LeftButton" and not anim.done then
        for i in ipairs(anim.result.cats) do anim.played[i] = true end -- no burst of row sounds
        anim.t = anim.finish - 0.01
    end
end)

local function Render(result)
    local s = db.quick and 0.4 or 1
    local label, vr, vg, vb = Verdict(result.score)
    bannerText:SetText(label)
    bannerText:SetTextColor(vr, vg, vb)
    banner:SetAlpha(0)
    bannerFlash:SetVertexColor(vr, vg, vb)
    bannerFlash:SetAlpha(0)
    levelText:SetText(UnitLevel("player"))
    if db.centerIcon == "portrait" then
        SetPortraitTexture(emblem, "player")
        emblem:SetTexCoord(0, 1, 0, 1)
    else
        emblem:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        local coords = CLASS_ICON_TCOORDS[select(2, UnitClass("player"))]
        if coords then emblem:SetTexCoord(unpack(coords)) end
    end
    SetRing(0, PctColor(result.score))

    local y = -126
    local rowStart = {}
    for i, cat in ipairs(result.cats) do
        local row = Row(i)
        row.cat = cat
        row.icon:SetTexture(cat.icon)
        row.name:SetText(cat.name)
        row.pct:SetText("")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win, "TOPLEFT", X, y)
        row:SetAlpha(0)
        row:Show()
        rowStart[i] = 0.4 + (i - 1) * 0.35 * s
        y = y - 19
    end
    for i = #result.cats + 1, #rows do rows[i]:Hide(); rows[i].cat = nil end

    tipsTitle:ClearAllPoints()
    tipsTitle:SetPoint("TOPLEFT", win, "TOPLEFT", X, y - 10)
    tipsTitle:SetAlpha(0)
    y = y - 28
    local shown = {}
    local n = math.min(3, #result.tips)
    for i = 1, math.max(n, 1) do
        local fs = TipLine(i)
        fs:SetText(n == 0 and L["“All in order. Good adventuring!”"] or (L["“"] .. result.tips[i].text .. L["”"]))
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", win, "TOPLEFT", X, y)
        fs:SetAlpha(0)
        fs:Show()
        shown[i] = fs
        y = y - fs:GetStringHeight() - 4
    end
    for i = math.max(n, 1) + 1, #tipLines do tipLines[i]:Hide() end
    win:SetHeight(math.max(300, -y + 52))

    local rowsEnd = (rowStart[#rowStart] or 0) + 0.5 * s
    anim = {
        t = 0, result = result, speed = s, rowStart = rowStart, played = {}, tips = shown,
        bannerStart = rowsEnd,
    }
    anim.tipStart = rowsEnd + 0.5 * s
    anim.finish = anim.tipStart + #shown * 0.25 * s + 0.6
end

local function Open()
    Render(RunScan())
    win:Show()
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
chatButton:RegisterForDrag("LeftButton")
chatButton:Hide()

local CHAT_BUTTONS = {
    "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    "ChatFrameMenuButton", "ChatFrame1ButtonFrameUpButton", "FriendsMicroButton", "QuickJoinToastButton",
}

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

local unlocked = false
chatButton:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
chatButton:SetScript("OnDragStop", function(self)
    if not unlocked then return end -- the drag moved nothing, keep the saved position
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db.btnPoint, db.btnX, db.btnY = point, x, y
end)
chatButton:SetScript("OnClick", function(_, mouse)
    if unlocked then return end
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

local function WarnLeavingTown()
    local result = RunScan()
    local bad = {}
    for _, c in ipairs(result.cats) do
        if c.status == BAD then
            for _, t in ipairs(c.tips) do bad[#bad + 1] = t end
        end
    end
    if #bad == 0 then return end
    table.sort(bad, function(a, b) return a.prio > b.prio end)
    RaidNotice_AddMessage(RaidWarningFrame, L["Tinkerwise: "] .. bad[1].text, ChatTypeInfo["RAID_WARNING"])
    if db.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    for _, t in ipairs(bad) do TW:Print(RED .. t.text .. "|r") end
end

local function MerchantHints()
    local want = RunScan().want
    local level = UnitLevel("player")
    local links = {}
    for i = 1, GetMerchantNumItems() do
        local link = GetMerchantItemLink(i)
        local id = link and GetItemInfoInstant(link)
        if id then
            local kind = ConsumableKind(id)
            local match = (want.ammo == id)
                or (want.reagents and want.reagents[id])
                or (kind and want[kind] and MinLevel(id) == want[kind] and MinLevel(id) <= level)
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
        C_Timer.After(1, PlaceChatButton)
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

-- Placeholder shown while moving: same size and spot as the window, no scan.
local preview

local function BuildPreview()
    preview = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    preview:SetFrameStrata("DIALOG")
    preview:SetMovable(true)
    preview:SetClampedToScreen(true)
    preview:EnableMouse(true)
    preview:RegisterForDrag("LeftButton")
    preview:SetBackdrop(win:GetBackdrop())
    preview:SetBackdropColor(0.45, 0.32, 0.2, 1)
    local label = preview:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\MORPHEUS.TTF", 22, "")
    label:SetTextColor(1, 0.9, 0.7)
    label:SetPoint("CENTER")
    label:SetText("Check-up")
    preview:SetScript("OnDragStart", preview.StartMoving)
    preview:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.winPoint, db.winX, db.winY = point, x, y
        win:ClearAllPoints()
        win:SetPoint(point, UIParent, point, x, y)
    end)
end

local function SetUnlocked(on)
    unlocked = on
    if on then
        if not preview then BuildPreview() end
        win:Hide()
        preview:SetSize(win:GetSize())
        preview:ClearAllPoints()
        preview:SetPoint(win:GetPoint())
        preview:Show()
    elseif preview then
        preview:Hide()
    end
end

local function ResetPosition()
    db.winPoint, db.btnPoint = nil, nil
    win:ClearAllPoints()
    win:SetPoint("CENTER", 0, 40)
    PlaceChatButton()
    if unlocked then SetUnlocked(true) end
end

local mod = TW:NewModule("Checkup", {
    title = "Check-up",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    section = L["Preparation"],
    desc = L["Checks that you're ready to go: durability and repair cost, food and water suited to your level, potions, ammo suited to your level, class reagents, elixirs and bag space. Button above the chat, right-click on the minimap button, or /checkup."],
    defaults = DEFAULTS,
    options = {
        { type = "execute", label = L["Run the check-up"], func = function() Open() end },
        { type = "execute", label = L["Move / Lock"], func = function() SetUnlocked(not unlocked) end },
        { type = "execute", label = L["Reset position"], func = function() ResetPosition() end },
        { type = "header", label = L["Thresholds"] },
        { type = "slider", key = "dura", label = L["Minimum durability (%)"], min = 10, max = 90, step = 5 },
        { type = "slider", key = "food", label = L["Minimum food"], min = 0, max = 40, step = 1 },
        { type = "slider", key = "drink", label = L["Minimum drinks"], min = 0, max = 40, step = 1 },
        { type = "slider", key = "ammo", label = L["Minimum ammo (hunter)"], min = 200, max = 3000, step = 100 },
        { type = "slider", key = "slots", label = L["Minimum free slots"], min = 0, max = 20, step = 1 },
        { type = "header", label = L["Automatic"] },
        { type = "toggle", key = "autoRest", label = L["Alert when leaving a city / inn"] },
        { type = "toggle", key = "autoInstance", label = L["Check-up when entering a dungeon / raid"] },
        { type = "toggle", key = "merchant", label = L["At a merchant, report what you need"] },
        { type = "toggle", key = "chatButton", label = L["Button above the chat"] },
        { type = "toggle", key = "sound", label = L["Sounds"] },
        { type = "toggle", key = "quick", label = L["Fast animation"] },
        { type = "select", key = "centerIcon", label = L["Image in the center of the ring"], values = {
            { "class", L["Class emblem"] },
            { "portrait", L["My portrait"] },
        } },
    },
})

function mod:Open() Open() end

function mod:OnEnable()
    db = self.db
    for _, list in pairs(AMMO) do for _, a in ipairs(list) do ItemName(a[1]) end end -- warm item cache
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("MERCHANT_SHOW")
    wasResting = IsResting()
    PlaceChatButton()
    chatButton:SetShown(db.chatButton)
    if db.winPoint then
        win:ClearAllPoints()
        win:SetPoint(db.winPoint, UIParent, db.winPoint, db.winX, db.winY)
    end
end

function mod:SetEditMode(on)
    SetUnlocked(on)
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    chatButton:Hide()
    win:Hide()
    SetUnlocked(false)
end

function mod:OnOptionChanged(key)
    if key == "chatButton" then chatButton:SetShown(db.chatButton) end
end

SLASH_TINKERWISECHECKUP1 = "/checkup"
SlashCmdList.TINKERWISECHECKUP = function()
    if mod.active then Open() else TW:Print(L["the Check-up module is disabled (/tw)."]) end
end
