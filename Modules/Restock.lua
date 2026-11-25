-- Restock: at a merchant, a button that buys what the check-up says is missing (food, water, ammo and
-- class reagents), up to its thresholds. It shows the price, and nothing is bought without a click.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetItemInfo, GetItemInfoInstant = ns.API.GetItemInfo, ns.API.GetItemInfoInstant
local GetCoinTextureString = ns.API.GetCoinTextureString

local STEP_SECONDS = 0.4

local queue, ticker = {}, nil
local plan = {}

local function MerchantItem(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost, info.isPurchasable end
        return
    end
    local _, _, price, stack, available, purchasable, _, extended = GetMerchantItemInfo(index)
    return price, stack, available, extended, purchasable
end

local function MerchantID(index)
    local link = GetMerchantItemLink(index)
    return link and GetItemInfoInstant(link) or nil
end

-- What to buy here: { id, index, price (of a batch), batch, batches }. One food and one drink at most.
local function MakePlan()
    wipe(plan)
    local want = ns.CheckupWant and ns.CheckupWant()
    if not want then return 0 end
    local total, done = 0, {}
    for i = 1, GetMerchantNumItems() do
        local id = MerchantID(i)
        local kind, missing
        if id then kind, missing = ns.CheckupMatch(want, id) end
        local price, batch, available, extended, purchasable = MerchantItem(i)
        if kind and missing and missing > 0 and not done[kind] and price and price > 0 and not extended
            and purchasable ~= false and available ~= 0 then
            batch = math.max(batch or 1, 1)
            local batches = math.ceil(missing / batch)
            if available and available > 0 then batches = math.min(batches, available) end
            done[kind] = true
            plan[#plan + 1] = { id = id, index = i, price = price, batch = batch, batches = batches }
            total = total + price * batches
        end
    end
    return total
end

local button = CreateFrame("Button", "TinkerwiseRestockButton", UIParent, "UIPanelButtonTemplate")
button:SetHeight(24)
button:SetFrameStrata("HIGH")
button:Hide()

local function Stop()
    if ticker then ticker:Cancel() end
    ticker = nil
    wipe(queue)
end

local function Refresh()
    if ticker or not (MerchantFrame and MerchantFrame:IsShown()) or not ns.CheckupRestock() then
        button:Hide()
        return
    end
    local total = MakePlan()
    if total == 0 then
        button:Hide()
        return
    end
    button:SetText(format(L["Buy what is missing (%s)"], GetCoinTextureString(total)))
    button:SetWidth(button:GetFontString():GetStringWidth() + 32)
    button:SetEnabled(total <= GetMoney())
    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", 0, 4)
    button:Show()
end

local function Step()
    local entry = table.remove(queue, 1)
    if not entry or not MerchantFrame:IsShown() then
        Stop()
        C_Timer.After(1, Refresh) -- the last purchase needs a moment to reach the bags
        return
    end
    -- The list of the merchant may have moved.
    local index = entry.index
    if MerchantID(index) ~= entry.id then
        index = nil
        for i = 1, GetMerchantNumItems() do
            if MerchantID(i) == entry.id then index = i end
        end
    end
    if not index or GetMoney() < entry.cost then return end
    -- Sold by batches: one batch at a time, without a quantity.
    if entry.batch > 1 then BuyMerchantItem(index) else BuyMerchantItem(index, entry.count) end
end

button:SetScript("OnClick", function()
    if ticker then return end
    local total = MakePlan() -- with what is in the bags now
    if total == 0 or total > GetMoney() then return Refresh() end
    local links = {}
    for _, item in ipairs(plan) do
        local _, link, _, _, _, _, _, stackSize = GetItemInfo(item.id)
        links[#links + 1] = format("%s x%d", link or item.id, item.batch * item.batches)
        local left = item.batches
        local most = item.batch > 1 and 1
            or math.max(1, math.min(GetMerchantItemMaxStack(item.index) or 1, stackSize or 1))
        while left > 0 do
            local count = math.min(left, most)
            queue[#queue + 1] = { id = item.id, index = item.index, batch = item.batch, count = count, cost = item.price * count }
            left = left - count
        end
    end
    TW:Print(format(L["bought: %s (%s)"], table.concat(links, ", "), GetCoinTextureString(total)))
    ticker = C_Timer.NewTicker(STEP_SECONDS, Step)
    button:Hide()
    GameTooltip:Hide()
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Missing according to the check-up"])
    for _, item in ipairs(plan) do
        local name = GetItemInfo(item.id)
        GameTooltip:AddDoubleLine(format("%s x%d", name or item.id, item.batch * item.batches),
            GetCoinTextureString(item.price * item.batches), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)
if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end

local pending
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.4, function()
        pending = nil
        Refresh()
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
        Stop()
        button:Hide()
    elseif MerchantFrame and MerchantFrame:IsShown() then
        Schedule()
    end
end)

-- Turned on and off with the check-up (its "restock" option).
function ns.EnableRestock(on)
    events:UnregisterAllEvents()
    if on then
        for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
            events:RegisterEvent(e)
        end
        Schedule()
    else
        Stop()
        button:Hide()
    end
end
