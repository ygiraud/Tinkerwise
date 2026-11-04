-- AutoVendor: at a merchant, sells grey (poor quality) items and repairs your gear.
-- Selling is spread over several ticks so the server does not drop sales.

local _, ns = ...
local TW = ns.TW
local GetItemInfo = ns.API.GetItemInfo

local DEFAULTS = {
    sell = true,       -- sell grey items
    printOnly = false, -- only list what would be sold
    repair = true,     -- repair everything when the merchant can
}

local PER_TICK = 4     -- items sold per tick
local TICK = 0.2

local db
local queue, gained, ticker = {}, 0, nil

local NumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local UseItem = C_Container and C_Container.UseContainerItem or UseContainerItem

-- Returns quality, count, itemID, hasNoValue for a bag slot (new and old APIs).
local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.quality, info.stackCount, info.itemID, info.hasNoValue end
        return
    end
    local _, count, _, quality, _, _, _, _, noValue, id = GetContainerItemInfo(bag, slot)
    return quality, count, id, noValue
end

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
        local quality, _, id = SlotInfo(entry.bag, entry.slot)
        if quality == 0 and id == entry.id then
            UseItem(entry.bag, entry.slot)
            gained = gained + entry.value
        end
    end
    if #queue == 0 then
        StopSelling()
        if gained > 0 then TW:Print("camelote vendue : " .. GetCoinTextureString(gained)) end
    end
end

local function Repair()
    if not db.repair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost == 0 then return end
    if cost > GetMoney() then
        TW:Print("pas assez d'or pour réparer (" .. GetCoinTextureString(cost) .. ").")
        return
    end
    RepairAllItems()
    TW:Print("équipement réparé : " .. GetCoinTextureString(cost))
end

local function SellJunk()
    if not db.sell then return end
    StopSelling()
    gained = 0
    local total, links = 0, {}
    for bag = 0, 4 do
        for slot = 1, NumSlots(bag) or 0 do
            local quality, count, id, noValue = SlotInfo(bag, slot)
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
        TW:Print(format("camelote à vendre (%s) : %s", GetCoinTextureString(total), table.concat(links, " ")))
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
    title = "Vendeur automatique",
    section = "Préparation",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    desc = "Chez un marchand, vend automatiquement les objets gris (camelote) et répare votre équipement. Le total gagné et le coût de réparation s'affichent dans le chat.",
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "sell", label = "Vendre les objets gris" },
        { type = "toggle", key = "printOnly", label = "Seulement lister la camelote (ne rien vendre)" },
        { type = "toggle", key = "repair", label = "Réparer automatiquement" },
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
