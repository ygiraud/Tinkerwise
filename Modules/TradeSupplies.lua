-- TradeSupplies: when a trade opens, a mage's conjured water and food or a warlock's healthstone are
-- put in the window, for the class and level of the other player. The trade is never accepted.
--
-- One stack at a time: the game needs a moment between two items.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetItemInfo = ns.API.GetItemInfo
local ContainerNumSlots = ns.API.ContainerNumSlots
local Plain = ns.Spells.Plain -- set by Courtesy.lua

local STEP_SECONDS = 0.3
local TRADE_SLOTS = 6 -- the seventh is not traded

-- { item id, level required } from the best to the worst. The game's own level counts when it
-- knows the item already.
local WATER = { { 8079, 55 }, { 8078, 45 }, { 8077, 35 }, { 3772, 25 }, { 2136, 15 }, { 2288, 5 }, { 5350, 1 } }
local FOOD = { { 22895, 55 }, { 8076, 45 }, { 8075, 35 }, { 1487, 25 }, { 1114, 15 }, { 1113, 5 }, { 5349, 1 } }
local HEALTHSTONES = {
    { 19013, 48 }, { 19012, 48 }, { 9421, 48 }, { 19011, 36 }, { 19010, 36 }, { 5510, 36 },
    { 19009, 24 }, { 19008, 24 }, { 5509, 24 }, { 19007, 12 }, { 19006, 12 }, { 5511, 12 },
    { 19005, 1 }, { 19004, 1 }, { 5512, 1 },
}
ns.Healthstones = HEALTHSTONES -- also for Courtesy.lua
local NO_MANA = { WARRIOR = true, ROGUE = true }

local class = select(2, UnitClass("player"))

local mod, db
local queue, ticker

---------------------------------------------------------------------------
-- What to give
---------------------------------------------------------------------------

-- The stacks of an item in the bags, biggest first.
local function StacksOf(id)
    local stacks = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id and not info.isLocked then
                stacks[#stacks + 1] = { bag = bag, slot = slot, id = id, count = info.stackCount or 1 }
            end
        end
    end
    table.sort(stacks, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return stacks
end

-- Adds up to `wanted` stacks of the best items usable at that level to `into`. `keep` stacks of the
-- best item you can use yourself stay in your bags. Returns how many were added.
local function Collect(list, level, wanted, keep, into)
    local added, myLevel = 0, UnitLevel("player")
    for _, entry in ipairs(list) do
        local id = entry[1]
        local required = select(5, GetItemInfo(id)) or entry[2]
        local stacks = StacksOf(id)
        local available = #stacks
        if available > 0 and required <= myLevel then
            local kept = math.min(keep, available)
            available, keep = available - kept, keep - kept
        end
        if required <= level then
            for i = 1, math.min(available, wanted - added) do
                into[#into + 1] = stacks[i]
                added = added + 1
            end
        end
    end
    return added
end

local function Audience()
    if db.audience == "all" then return true end
    if Plain(UnitInParty("npc")) or Plain(UnitInRaid("npc")) then return true end
    return db.audience == "guild" and UnitIsInMyGuild and Plain(UnitIsInMyGuild("npc")) and true or false
end

local function Prepare()
    local _, partnerClass = UnitClass("npc")
    partnerClass = Plain(partnerClass)
    local level = Plain(UnitLevel("npc"))
    if type(level) ~= "number" or level < 1 then level = UnitLevel("player") end
    local items, missing = {}, {}

    local function Take(list, wanted, keep, name)
        if wanted > 0 and Collect(list, level, wanted, keep, items) < wanted then missing[#missing + 1] = name end
    end
    if class == "MAGE" then
        local mana = not NO_MANA[partnerClass or ""]
        if mana then Take(WATER, db.water, db.keep, L["water"]) end
        Take(FOOD, mana and db.foodMana or db.food, db.keep, L["food"])
    elseif class == "WARLOCK" and db.healthstone then
        Take(HEALTHSTONES, 1, db.keepStone and 1 or 0, L["healthstone"])
    end
    return items, missing
end

---------------------------------------------------------------------------
-- Filling the window
---------------------------------------------------------------------------

local function Stop()
    if ticker then ticker:Cancel() end
    ticker, queue = nil, nil
end

local function FreeSlot()
    for i = 1, TRADE_SLOTS do
        if not GetTradePlayerItemLink(i) then return i end
    end
end

local function Step()
    local item = queue and table.remove(queue, 1)
    if not item or InCombatLockdown() or not (TradeFrame and TradeFrame:IsShown()) then return Stop() end
    if GetCursorInfo() then return Stop() end -- the player is moving something
    local free = FreeSlot()
    if not free then return Stop() end
    -- The bag may have changed since the trade opened.
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if not info or info.itemID ~= item.id or info.isLocked then return end
    C_Container.PickupContainerItem(item.bag, item.slot)
    if GetCursorInfo() == "item" then
        ClickTradeButton(free)
        if GetCursorInfo() then ClearCursor() end
    end
end

local function OnTradeShow()
    Stop()
    if InCombatLockdown() or not Audience() then return end
    local items, missing = Prepare()
    if #missing > 0 and db.warn then
        TW:Print(format(L["not enough to give: %s."], table.concat(missing, ", ")))
    end
    if #items == 0 then return end
    queue = items
    ticker = C_Timer.NewTicker(STEP_SECONDS, Step)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SHOW" then OnTradeShow() else Stop() end
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local options = {
    { type = "select", key = "audience", label = L["Fill the trade for"], values = {
        { "group", L["My group"] }, { "guild", L["My group and my guild"] }, { "all", L["Everyone"] },
    } },
    { type = "toggle", key = "warn", label = L["Warn me when I don't have enough"] },
}
if class == "MAGE" then
    for _, opt in ipairs({
        { type = "header", label = L["Stacks to give"] },
        { type = "slider", key = "water", label = L["Water, to mana users"], min = 0, max = 6, step = 1 },
        { type = "slider", key = "foodMana", label = L["Food, to mana users"], min = 0, max = 6, step = 1 },
        { type = "slider", key = "food", label = L["Food, to warriors and rogues"], min = 0, max = 6, step = 1 },
        { type = "slider", key = "keep", label = L["Stacks to keep for me"], min = 0, max = 6, step = 1 },
    }) do options[#options + 1] = opt end
elseif class == "WARLOCK" then
    options[#options + 1] = { type = "header", label = L["Healthstone"] }
    options[#options + 1] = { type = "toggle", key = "healthstone", label = L["Give a healthstone"] }
    options[#options + 1] = { type = "toggle", key = "keepStone", label = L["Keep one for me"] }
end

mod = TW:NewModule("TradeSupplies", {
    title = L["Trade Supplies"],
    icon = "Interface\\Icons\\INV_Drink_18",
    section = L["Group"],
    desc = L["For mages and warlocks: when a trade opens outside combat, puts in your conjured water and food or a healthstone, for the class and level of the other player. You always accept the trade yourself. Does nothing on other classes."],
    defaults = {
        audience = "group", warn = true,
        water = 2, foodMana = 1, food = 2, keep = 1,
        healthstone = true, keepStone = true,
    },
    options = options,
})

function mod:OnEnable()
    db = self.db
    if class ~= "MAGE" and class ~= "WARLOCK" then return end
    events:RegisterEvent("TRADE_SHOW")
    events:RegisterEvent("TRADE_CLOSED")
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    Stop()
end
