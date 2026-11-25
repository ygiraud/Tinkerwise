-- SoulShards: for warlocks, destroys the soul shards above the number to keep.
--
-- The game only lets an item be destroyed on a key press or a click: the next one after a shard too
-- many does it, one shard at a time, outside combat.

local _, ns = ...
local L = ns.L
local TW = ns.TW

if select(2, UnitClass("player")) ~= "WARLOCK" then return end

local Plain = ns.Spells.Plain -- set by Courtesy.lua
local ContainerNumSlots = ns.API.ContainerNumSlots

local SOUL_SHARD = 6265
local STEP_SECONDS = 0.5
local MAX_FAILURES = 3

local mod, db
local hooked = false
local lastTry, failures = 0, 0

local function Count()
    return Plain(ns.API.GetItemCount(SOUL_SHARD)) or 0
end

local function TooMany()
    return mod.active and db.destroy and failures < MAX_FAILURES and Count() > db.max
end

-- The shard to destroy: the ones outside soul bags first, they take the room of other items.
local function FindShard(spare)
    local inSoulBag
    for bag = NUM_BAG_SLOTS or 4, 0, -1 do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        for slot = ContainerNumSlots(bag) or 0, 1, -1 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- A stack bigger than what is too many stays whole.
            if info and info.itemID == SOUL_SHARD and not info.isLocked and (info.stackCount or 1) <= spare then
                if not family or family == 0 then return bag, slot end
                inSoulBag = inSoulBag or { bag, slot }
            end
        end
    end
    if inSoulBag then return inSoulBag[1], inSoulBag[2] end
end

local function Busy()
    return InCombatLockdown() or UnitIsDeadOrGhost("player") or GetCursorInfo() ~= nil
        or (SpellIsTargeting and SpellIsTargeting()) or (TradeFrame and TradeFrame:IsShown())
end

local function OnInput()
    if not TooMany() or Busy() or GetTime() - lastTry < STEP_SECONDS then return end
    local before = Count()
    local bag, slot = FindShard(before - db.max)
    if not bag then return end
    lastTry = GetTime()
    C_Container.PickupContainerItem(bag, slot)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= SOUL_SHARD then
        ClearCursor()
        return
    end
    DeleteCursorItem()
    if GetCursorInfo() then -- refused: the shard goes back, and after a few times we stop asking
        ClearCursor()
        failures = failures + 1
        if failures == MAX_FAILURES then TW:Print(L["the game refuses to destroy soul shards: stopped until the next login."]) end
        return
    end
    failures = 0
    if db.say then TW:Print(format(L["soul shard destroyed (%d to keep)."], db.max)) end
end

-- Keys are only listened to while there is something to destroy, and always passed on.
local keys = CreateFrame("Frame")
keys:Hide()
keys:SetScript("OnKeyDown", OnInput)

local function Update()
    local on = TooMany()
    if on and not hooked then
        if InCombatLockdown() then return end -- set up once the fight is over
        hooked = true
        keys:SetPropagateKeyboardInput(true)
        keys:EnableKeyboard(true)
        WorldFrame:HookScript("OnMouseUp", OnInput)
    end
    keys:SetShown(hooked and on or false)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Update)

mod = TW:NewModule("SoulShards", {
    title = L["Soul Shards"],
    icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    section = L["Items"],
    desc = L["For warlocks: destroys the soul shards above the number you want to keep. The game only allows it on a key press or a click, so the next one does it, one shard at a time, outside combat. The ones outside soul bags go first. A destroyed shard cannot be recovered."],
    defaults = { destroy = false, max = 10, say = true },
    options = {
        { type = "toggle", key = "destroy", label = L["Destroy the soul shards in excess"] },
        { type = "slider", key = "max", label = L["Soul shards to keep"], min = 1, max = 60, step = 1 },
        { type = "toggle", key = "say", label = L["Say it in the chat"] },
    },
})

function mod:OnEnable()
    db = self.db
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(e)
    end
    Update()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    Update()
end

function mod:OnOptionChanged() Update() end
