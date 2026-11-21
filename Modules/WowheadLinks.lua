-- WowheadLinks: Ctrl + C over the tooltip of an item, a spell, a quest or a creature opens a small
-- window with its Wowhead (Classic) address, selected and ready to be copied with Ctrl + C again.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local BASE_URL = "https://www.wowhead.com/classic/"
local LOCALE_PATHS = {
    frFR = "fr/", deDE = "de/", esES = "es/", esMX = "es/", ptBR = "pt/", ruRU = "ru/",
    itIT = "it/", koKR = "ko/", zhCN = "cn/", zhTW = "tw/",
}

local issecretvalue = _G.issecretvalue
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local mod

---------------------------------------------------------------------------
-- What the tooltip shows
---------------------------------------------------------------------------

local function NpcID(unit)
    local guid = unit and Plain(UnitGUID(unit))
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Returns the Wowhead page kind ("item", "spell"...) and the id.
local function TooltipTarget(tooltip)
    local types = Enum.TooltipDataType
    local data = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
    if data and types then
        local id = Plain(data.id)
        if id then
            if data.type == types.Item then return "item", id end
            if data.type == types.Spell then return "spell", id end
            if data.type == types.Quest then return "quest", id end
        end
    end
    local _, link = tooltip:GetItem()
    link = Plain(link)
    local itemID = link and tonumber(link:match("item:(%d+)"))
    if itemID then return "item", itemID end
    if tooltip.GetSpell then
        local _, spellID = tooltip:GetSpell()
        spellID = Plain(spellID)
        if spellID then return "spell", spellID end
    end
    local _, unit = tooltip:GetUnit()
    local npcID = NpcID(Plain(unit))
    if npcID then return "npc", npcID end
end

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------

local window, edit

local function BuildWindow()
    window = CreateFrame("Frame", "TinkerwiseWowheadFrame", UIParent, "BackdropTemplate")
    window:SetSize(460, 84)
    window:SetPoint("CENTER", 0, 120)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:Hide()
    TW:SkinDialog(window, L["Wowhead link (Ctrl + C to copy)"])
    tinsert(UISpecialFrames, "TinkerwiseWowheadFrame")

    edit = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    edit:SetPoint("BOTTOMLEFT", 24, 18)
    edit:SetPoint("BOTTOMRIGHT", -20, 18)
    edit:SetHeight(24)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    edit:SetScript("OnEnterPressed", function() window:Hide() end)
    -- Read-only: typing puts the address back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.original)
            self:HighlightText()
        end
    end)
    -- Ctrl + C copies the selection; the window closes right after.
    edit:SetScript("OnKeyUp", function(_, key)
        if key == "C" and IsControlKeyDown() then window:Hide() end
    end)
end

local function ShowLink(kind, id)
    if not window then BuildWindow() end
    local url = BASE_URL .. (LOCALE_PATHS[GetLocale()] or "") .. kind .. "=" .. id
    edit.original = url
    edit:SetText(url)
    window:Show()
    edit:SetFocus()
    edit:HighlightText()
end

---------------------------------------------------------------------------
-- Key watcher: the keys go on to the game as usual.
---------------------------------------------------------------------------

local keys = CreateFrame("Frame", nil, UIParent)
keys:Hide()
pcall(keys.SetPropagateKeyboardInput, keys, true) -- once, at load: not allowed in combat afterwards
keys:SetScript("OnKeyDown", function(_, key)
    if key ~= "C" or not IsControlKeyDown() or not GameTooltip:IsShown() then return end
    local ok, kind, id = pcall(TooltipTarget, GameTooltip) -- secret values make some reads fail
    if ok and kind then ShowLink(kind, id) end
end)

mod = TW:NewModule("WowheadLinks", {
    title = L["Wowhead Links"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    section = L["Items"],
    desc = L["Hover over an item, a spell, a quest or a creature and press Ctrl + C: a small window shows its Wowhead (Classic) address, ready to copy with Ctrl + C again and paste in your browser."],
    defaults = {},
})

function mod:OnEnable()
    keys:Show()
    keys:EnableKeyboard(true)
end

function mod:OnDisable()
    keys:EnableKeyboard(false)
    keys:Hide()
    if window then window:Hide() end
end
