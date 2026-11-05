-- AutoVendor: at a merchant, sells grey (poor quality) items and repairs your gear.
-- Selling is spread over several ticks so the server does not drop sales.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetItemInfo = ns.API.GetItemInfo
local GetCoinTextureString = ns.API.GetCoinTextureString

local DEFAULTS = {
    sell = true,       -- sell grey items
    printOnly = false, -- only list what would be sold
    repair = true,     -- repair everything when the merchant can
}

local PER_TICK = 4     -- items sold per tick
local TICK = 0.2

local db
local queue, gained, ticker = {}, 0, nil

local NumSlots, ContainerItem = ns.API.ContainerNumSlots, ns.API.ContainerItem
local UseItem = C_Container and C_Container.UseContainerItem or UseContainerItem

local function StopSelling()
    if ticker then ticker:Cancel() end
    ticker = nil
    wipe(queue)
end

local function SellTick()
    if not MerchantFrame:IsShown() then return StopSelling() end
    for _ = 1, PER_TICK do
        local entry = table.remove(queue, 1)
        if not entry then break end
        -- the slot may have changed since it was queued
        local id, _, quality = ContainerItem(entry.bag, entry.slot)
        if quality == 0 and id == entry.id then
            UseItem(entry.bag, entry.slot)
            gained = gained + entry.value
        end
    end
    if #queue == 0 then
        StopSelling()
        if gained > 0 then TW:Print(L["junk sold: "] .. GetCoinTextureString(gained)) end
    end
end

local function Repair()
    if not db.repair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost == 0 then return end
    if cost > GetMoney() then
        TW:Print(L["not enough gold to repair ("] .. GetCoinTextureString(cost) .. ").")
        return
    end
    RepairAllItems()
    TW:Print(L["gear repaired: "] .. GetCoinTextureString(cost))
end

local function SellJunk()
    if not db.sell then return end
    StopSelling()
    gained = 0
    local total, links = 0, {}
    for bag = 0, 4 do
        for slot = 1, NumSlots(bag) or 0 do
            local id, count, quality, noValue = ContainerItem(bag, slot)
            if quality == 0 and id and not noValue then
                local _, link, _, _, _, _, _, _, _, _, price = GetItemInfo(id)
                local value = (price or 0) * (count or 1)
                if value > 0 then
                    total = total + value
                    links[#links + 1] = link
                    queue[#queue + 1] = { bag = bag, slot = slot, id = id, value = value }
                end
            end
        end
    end
    if #queue == 0 then return end
    if db.printOnly then
        TW:Print(format(L["junk to sell (%s): %s"], GetCoinTextureString(total), table.concat(links, " ")))
        wipe(queue)
        return
    end
    ticker = C_Timer.NewTicker(TICK, SellTick)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        Repair()
        SellJunk()
    elseif event == "MERCHANT_CLOSED" then
        StopSelling()
    end
end)

local mod = TW:NewModule("AutoVendor", {
    title = L["Auto Vendor"],
    section = L["Items"],
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    desc = L["At a merchant, automatically sells gray items (junk) and repairs your gear. The total earned and the repair cost are shown in chat."],
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "sell", label = L["Sell gray items"] },
        { type = "toggle", key = "printOnly", label = L["Only list junk (sell nothing)"] },
        { type = "toggle", key = "repair", label = L["Repair automatically"] },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    StopSelling()
end
