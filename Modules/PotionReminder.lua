-- PotionReminder: shows the best usable healing / mana potion in your bags when it is not
-- on your action bars yet. Drag the icon onto a bar and it fades out.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetItemInfo, GetItemCount, GetItemIcon = ns.API.GetItemInfo, ns.API.GetItemCount, ns.API.GetItemIcon

local DEFAULTS = {
    heal = true,
    mana = true,
    size = 40,
    hint = true,     -- "drag me to your bar" text
    point = "CENTER", x = 0, y = 120,
}

-- Weakest to strongest.
local POTIONS = {
    heal = { 118, 858, 929, 1710, 3928, 13446 },
    mana = { 2455, 3385, 3827, 6149, 13443, 13444 },
}
-- Required level when the item info is not cached yet.
local MIN_LEVEL = {
    [118] = 1, [858] = 3, [929] = 12, [1710] = 21, [3928] = 35, [13446] = 45,
    [2455] = 5, [3385] = 14, [3827] = 22, [6149] = 31, [13443] = 41, [13444] = 49,
}
ns.POTIONS = POTIONS -- shared with the check-up
local KINDS = { "heal", "mana" }
local GOLD = { 1, 0.82, 0.3 }

local db
local previewUntil = 0

local function ItemCount(id)
    return GetItemCount(id) or 0
end

local function MinLevel(id)
    local minLevel = select(5, GetItemInfo(id))
    return minLevel or MIN_LEVEL[id] or 0
end

local function FindBest(list)
    local level = UnitLevel("player")
    for i = #list, 1, -1 do
        local id = list[i]
        if ItemCount(id) > 0 and MinLevel(id) <= level then return id end
    end
end

local function IsOnActionBar(id)
    local itemName = GetItemInfo(id)
    for slot = 1, 180 do
        local actionType, actionId = GetActionInfo(slot)
        if actionType == "item" and actionId == id then return true end
        if actionType == "macro" and itemName and GetMacroItem(actionId) == itemName then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local container = CreateFrame("Frame", "TinkerwisePotionFrame", UIParent)
container:SetSize(88, 40)
container:Hide()
TW:CreateMover(container, function() return db end, L["Potion Reminder"], DEFAULTS)

local hint = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hint:SetPoint("TOP", container, "BOTTOM", 0, -6)
hint:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
hint:SetText(L["Drag me to your bar"])

local buttons = {}
for i, kind in ipairs(KINDS) do
    local b = CreateFrame("Button", nil, container, "BackdropTemplate")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    b.border:SetBackdropBorderColor(1, 0.85, 0.35, 1)

    b.count = b.border:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)

    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        if self.itemID and not container:IsUnlocked() then PickupItem(self.itemID) end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemID)
        GameTooltip:AddLine(L["Drag onto an action bar"], GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b.kind = kind
    b:Hide()
    buttons[i] = b
end

local function Refresh()
    if not db then return end
    local size = db.size
    local preview = container:IsUnlocked() or GetTime() < previewUntil
    local shown = {}
    for _, b in ipairs(buttons) do
        local list = POTIONS[b.kind]
        local enabled = db[b.kind] and (b.kind ~= "mana" or UnitPowerMax("player", 0) > 0)
        local id = enabled and FindBest(list)
        if id and IsOnActionBar(id) then id = nil end
        if not id and preview and enabled then id = FindBest(list) or list[#list] end
        if id then
            b.itemID = id
            b.icon:SetTexture(GetItemIcon(id))
            local c = ItemCount(id)
            b.count:SetText(c > 1 and c or "")
            b:SetSize(size, size)
            b.glow:SetSize(size * 1.7, size * 1.7)
            b:Show()
            shown[#shown + 1] = b
        else
            b.itemID = nil
            b:Hide()
        end
    end

    local gap = 8
    local width = math.max(size, #shown * size + (#shown - 1) * gap)
    container:SetSize(width, size)
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", container, "LEFT", (i - 1) * (size + gap), 0)
    end
    hint:SetShown(db.hint and #shown > 0)
    container:SetShown(#shown > 0 or container:IsUnlocked())
end

-- Gentle "breathing" glow.
local t = 0
container:SetScript("OnUpdate", function(_, elapsed)
    t = t + elapsed
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            local s = 0.5 + 0.5 * math.sin(t * 2.2)
            b:SetAlpha(0.82 + 0.18 * s)
            b.glow:SetAlpha(0.12 + 0.3 * s)
        end
    end
end)

local function RefreshIfActive()
    if TW.modules.PotionReminder.active then Refresh() end
end

local pending
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        RefreshIfActive()
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Schedule)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local mod = TW:NewModule("PotionReminder", {
    title = L["Potion Reminder"],
    icon = "Interface\\Icons\\INV_Potion_54",
    section = L["Preparation"],
    desc = L["Shows the best usable healing / mana potion in your bags when it isn't on your action bars. Drag the icon onto a bar and it disappears."],
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "heal", label = L["Healing potions"] },
        { type = "toggle", key = "mana", label = L["Mana potions"] },
        { type = "toggle", key = "hint", label = L["Show \"Drag me to your bar\""] },
        { type = "slider", key = "size", label = L["Icon size"], min = 24, max = 80, step = 2 },
        { type = "execute", label = L["Preview (5 s)"], func = function()
            previewUntil = GetTime() + 5
            Refresh()
            C_Timer.After(5.1, RefreshIfActive)
        end },
        { type = "execute", label = L["Move / Lock"], func = function()
            container:ToggleMover()
            Refresh()
        end },
        { type = "execute", label = L["Reset position"], func = function() container:ResetPosition() end },
    },
})

function mod:OnEnable()
    db = self.db
    container:ApplyPosition()
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "ACTIONBAR_SLOT_CHANGED", "PLAYER_LEVEL_UP",
                         "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    Refresh()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    container:Lock()
    container:Hide()
end

function mod:OnOptionChanged()
    Refresh()
end

function mod:SetEditMode(on)
    container:SetUnlocked(on)
    Refresh()
end
