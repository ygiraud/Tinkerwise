-- ItemLevel: writes the item level on the gear slots of the character sheet and of the inspect
-- window, and on the equippable items of the game's bags. Bag addons with their own windows are
-- not covered.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local C_Item = _G.C_Item or {}
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
local GetItemInfo = C_Item.GetItemInfo or _G.GetItemInfo

local WEAPON_CLASS, ARMOR_CLASS = 2, 4
local SHIRT_SLOT, TABARD_SLOT = 4, 19
local MIN_LEVEL = 2 -- level 1 items (shirts, starting gear) say nothing useful
local REFRESH_DELAY = 0.1

local mod, db
-- Kept apart from the game's buttons: nothing is written into their tables.
local labels = setmetatable({}, { __mode = "k" })

local function Label(button)
    local text = labels[button]
    if not text then
        text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetPoint("TOP", button, "TOP", 0, -2)
        labels[button] = text
    end
    return text
end

local function Clear(button)
    if labels[button] then labels[button]:Hide() end
end

local function Equippable(link)
    local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
    return (classID == WEAPON_CLASS or classID == ARMOR_CLASS) and equipLoc and equipLoc ~= ""
        and equipLoc ~= "INVTYPE_BODY" and equipLoc ~= "INVTYPE_TABARD"
end

local function Show(button, link)
    if not (mod.active and link and Equippable(link)) then return Clear(button) end
    local level = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
    if not level then level = select(4, GetItemInfo(link)) end
    if not level or level < MIN_LEVEL then return Clear(button) end
    local text = Label(button)
    text:SetText(level)
    local quality = select(3, GetItemInfo(link))
    if db.qualityColor and quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local color = ITEM_QUALITY_COLORS[quality]
        text:SetTextColor(color.r, color.g, color.b)
    else
        text:SetTextColor(1, 1, 1)
    end
    text:Show()
end

---------------------------------------------------------------------------
-- Character sheet and inspect window
---------------------------------------------------------------------------

local function ShowSlot(button, unit, enabled)
    local slot = button:GetID()
    if not enabled or slot == SHIRT_SLOT or slot == TABARD_SLOT then return Clear(button) end
    Show(button, GetInventoryItemLink(unit, slot))
end

local function OnPlayerSlot(button)
    if not db then return end
    ShowSlot(button, "player", db.character)
end

local function OnInspectSlot(button)
    if not db then return end
    ShowSlot(button, InspectFrame and InspectFrame.unit or "target", db.inspect)
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

local function BagFrames()
    local frames = {}
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        if _G["ContainerFrame" .. i] then frames[#frames + 1] = _G["ContainerFrame" .. i] end
    end
    if _G.ContainerFrameCombinedBags then frames[#frames + 1] = _G.ContainerFrameCombinedBags end
    return frames
end

-- Recent clients list their buttons; older ones name them ContainerFrame1Item1...
local function ForEachBagButton(frame, func)
    if frame.EnumerateValidItems then
        for _, button in frame:EnumerateValidItems() do func(button, button:GetBagID(), button:GetID()) end
    else
        local name = frame:GetName()
        for i = 1, frame.size or 0 do
            local button = _G[name .. "Item" .. i]
            if button then func(button, frame:GetID(), button:GetID()) end
        end
    end
end

local function ContainerLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
    return GetContainerItemLink(bag, slot)
end

local function RefreshBags()
    if not db then return end
    for _, frame in ipairs(BagFrames()) do
        if frame:IsShown() then
            ForEachBagButton(frame, function(button, bag, slot)
                if db.bags then Show(button, ContainerLink(bag, slot)) else Clear(button) end
            end)
        end
    end
end

local pending = false
local function QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, function()
        pending = false
        RefreshBags()
        if PaperDollFrame and PaperDollFrame:IsShown() and PaperDollItemSlotButton_Update then
            for _, name in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
                "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }) do
                local button = _G["Character" .. name .. "Slot"]
                if button then OnPlayerSlot(button) end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Hooks (once; they check that the module is active)
---------------------------------------------------------------------------

local hooked, inspectHooked = false, false

local function HookInspect()
    if inspectHooked or not InspectPaperDollItemSlotButton_Update then return end
    inspectHooked = true
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", OnInspectSlot)
end

local function Hook()
    if hooked then return end
    hooked = true
    if PaperDollItemSlotButton_Update then hooksecurefunc("PaperDollItemSlotButton_Update", OnPlayerSlot) end
    for _, frame in ipairs(BagFrames()) do frame:HookScript("OnShow", QueueRefresh) end
    HookInspect()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "Blizzard_InspectUI" then HookInspect() end
    else
        QueueRefresh()
    end
end)

mod = TW:NewModule("ItemLevel", {
    title = L["Item Level"],
    icon = "Interface\\Icons\\INV_Chest_Plate06",
    section = L["Items"],
    desc = L["Writes the item level on your gear in the character sheet, in the inspect window and on the equippable items of your bags (the game's bags, not those of bag addons)."],
    defaults = { character = true, inspect = true, bags = true, qualityColor = true },
    options = {
        { type = "toggle", key = "character", label = L["Character sheet"] },
        { type = "toggle", key = "inspect", label = L["Inspect window"] },
        { type = "toggle", key = "bags", label = L["Bags"] },
        { type = "toggle", key = "qualityColor", label = L["Color by item quality"] },
    },
})

function mod:OnEnable()
    db = self.db
    Hook()
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    QueueRefresh()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    for button in pairs(labels) do Clear(button) end
end

function mod:OnOptionChanged()
    for button in pairs(labels) do Clear(button) end
    QueueRefresh()
end
