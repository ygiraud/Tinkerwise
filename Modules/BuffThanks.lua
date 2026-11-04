-- BuffThanks: thanks players who buff you and offers a one-click button to buff them back.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local GetSpellInfo, GetSpellTexture = ns.API.GetSpellInfo, ns.API.GetSpellTexture

local DEFAULTS = {
    thank = true,          -- thank automatically
    thankMode = "emote",   -- "emote" or "whisper"
    message = L["Thanks for the %s!"],
    throttle = 120,        -- seconds before thanking the same player again
    ignoreGroup = true,    -- don't thank party/raid members (raid buffs spam)
    rebuff = true,         -- show the buff-back button
    timeout = 60,          -- seconds a buff-back button stays
    point = "CENTER", x = 0, y = -180,
}

local MAX_BUTTONS = 5

-- Buffs we can give back, by player class (rank 1 ids, used for the localized name;
-- casting without a rank uses the highest known rank).
local CASTER_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true }

local function SpellName(id)
    return (GetSpellInfo(id))
end

local function Known(id)
    local name = SpellName(id)
    return name and GetSpellInfo(name) and name
end

local function PickBuff(targetClass)
    local _, myClass = UnitClass("player")
    if myClass == "MAGE" then return Known(1459) end      -- Arcane Intellect
    if myClass == "PRIEST" then return Known(1243) end    -- Power Word: Fortitude
    if myClass == "DRUID" then return Known(1126) end     -- Mark of the Wild
    if myClass == "PALADIN" then
        return Known(20217)                                -- Blessing of Kings
            or (CASTER_CLASSES[targetClass] and Known(19742)) -- Blessing of Wisdom
            or Known(19740)                                -- Blessing of Might
    end
end

local db
local lastThanked = {}

---------------------------------------------------------------------------
-- Buff-back buttons (secure: attributes and visibility only change out of combat)
---------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "TinkerwiseBuffThanksAnchor", UIParent)
anchor:SetSize(220, 16)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db.point, db.x, db.y = point, x, y
end)
anchor:Hide()

local anchorBg = anchor:CreateTexture(nil, "BACKGROUND")
anchorBg:SetAllPoints()
anchorBg:SetColorTexture(0, 0.6, 1, 0.4)
local anchorLabel = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
anchorLabel:SetPoint("CENTER")
anchorLabel:SetText(L["Rebuff - drag here"])

local entries = {}   -- { name, spell, classFile, time }
local buttons = {}
local dirty = false  -- layout change waiting for combat to end

local Refresh

local function Remove(name)
    for i = #entries, 1, -1 do
        if entries[i].name == name then table.remove(entries, i) end
    end
    Refresh()
end

for i = 1, MAX_BUTTONS do
    local b = CreateFrame("Button", "TinkerwiseBuffThanksButton" .. i, UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    b:SetSize(220, 26)
    b:SetPoint("TOP", anchor, "BOTTOM", 0, -2 - (i - 1) * 28)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    b:SetBackdropColor(0, 0, 0, 0.8)
    b:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    b:RegisterForClicks("AnyUp", "AnyDown") -- secure actions fire on press or release, per game setting
    b:SetAttribute("type1", "macro")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("LEFT", 4, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Left click casts (secure macro), right click dismisses; both remove the entry.
    b:SetScript("PostClick", function(self, _, down)
        -- Remove only on the phase that casts, or the other phase would clear the button first.
        local castOnDown = GetCVarBool("ActionButtonUseKeyDown")
        if self.name and (down and true or false) == (castOnDown and true or false) then Remove(self.name) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.name or "")
        GameTooltip:AddLine(L["Left-click: cast "] .. (self.spell or ""), 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: ignore"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    buttons[i] = b
end

function Refresh()
    if InCombatLockdown() then
        dirty = true
        return
    end
    dirty = false
    for i, b in ipairs(buttons) do
        local e = entries[i]
        if e then
            b.name, b.spell = e.name, e.spell
            b:SetAttribute("macrotext", format("/targetexact %s\n/cast %s\n/targetlasttarget", e.name, e.spell))
            local color = RAID_CLASS_COLORS[e.classFile]
            local colored = color and format("|c%s%s|r", color.colorStr or "ffffffff", e.name) or e.name
            b.text:SetText(colored .. " - " .. e.spell)
            b.icon:SetTexture((GetSpellTexture(e.spell)))
            b:Show()
        else
            b.name, b.spell = nil, nil
            b:Hide()
        end
    end
end

local function AddEntry(name, spell, classFile)
    for _, e in ipairs(entries) do
        if e.name == name then
            e.spell, e.time = spell, GetTime()
            return Refresh()
        end
    end
    table.insert(entries, 1, { name = name, spell = spell, classFile = classFile, time = GetTime() })
    while #entries > MAX_BUTTONS do table.remove(entries) end
    Refresh()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHAT_EMOTE_BUTTON or 852)
end

local function ExpireEntries()
    local now, changed = GetTime(), false
    for i = #entries, 1, -1 do
        if now - entries[i].time > db.timeout then
            table.remove(entries, i)
            changed = true
        end
    end
    if changed then Refresh() end
end
local ticker

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------

local function InGroup(name)
    return UnitInParty(name) or UnitInRaid(name)
end

local function OnBuffed(sourceGUID, sourceName, spellName)
    local _, classFile = GetPlayerInfoByGUID(sourceGUID)
    local now = GetTime()
    if db.ignoreGroup and InGroup(sourceName) then return end
    if lastThanked[sourceName] and now - lastThanked[sourceName] < db.throttle then return end
    lastThanked[sourceName] = now

    if db.thank then
        if db.thankMode == "whisper" then
            local ok, text = pcall(format, db.message, spellName)
            SendChatMessage(ok and text or db.message, "WHISPER", nil, sourceName)
        else
            SendChatMessage(format(L["thanks %s for %s."], sourceName, spellName), "EMOTE")
        end
    end

    if db.rebuff then
        local spell = PickBuff(classFile)
        if spell then AddEntry(sourceName, spell, classFile) end
    end
end

-- The secure buttons hang from the anchor: it cannot move in combat.
local positionPending = false
local function ApplyPosition()
    positionPending = InCombatLockdown()
    if positionPending then return end
    anchor:ClearAllPoints()
    anchor:SetPoint(db.point, UIParent, db.point, db.x, db.y)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if positionPending then ApplyPosition() end
        if dirty then Refresh() end
        return
    end
    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, _, _, _, _, spellName, _, auraType =
        CombatLogGetCurrentEventInfo()
    if subEvent ~= "SPELL_AURA_APPLIED" or auraType ~= "BUFF" then return end
    if destGUID ~= UnitGUID("player") or not sourceGUID or sourceGUID == destGUID or not sourceName then return end
    if bit.band(sourceFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) == 0 then return end
    if bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0 then return end
    OnBuffed(sourceGUID, sourceName, spellName)
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local mod =TW:NewModule("BuffThanks", {
    title = L["Thanks & Rebuff"],
    icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    section = L["Group"],
    desc = L["Automatically thanks players who buff you and shows a button to buff them back in one click (mage, priest, druid, paladin)."],
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "thank", label = L["Thank automatically"] },
        { type = "select", key = "thankMode", label = L["How to thank"], values = {
            { "emote", "Emote" },
            { "whisper", L["Whisper"] },
        } },
        { type = "input", key = "message", label = L["Whisper message (%s = buff name)"] },
        { type = "slider", key = "throttle", label = L["Delay before thanking again (s)"], min = 10, max = 600, step = 10 },
        { type = "toggle", key = "ignoreGroup", label = L["Ignore group / raid members"] },
        { type = "toggle", key = "rebuff", label = L["Offer to buff back"] },
        { type = "slider", key = "timeout", label = L["Rebuff button duration (s)"], min = 10, max = 300, step = 10 },
        { type = "execute", label = L["Test the button"], func = function()
            local spell = PickBuff("WARRIOR")
            if spell then
                AddEntry(UnitName("player"), spell, select(2, UnitClass("player")))
            else
                TW:Print(L["your class has no buff to offer."])
            end
        end },
        { type = "execute", label = L["Move / Lock"], func = function()
            if InCombatLockdown() then return end
            anchor:SetShown(not anchor:IsShown())
        end },
        { type = "execute", label = L["Reset position"], func = function()
            db.point, db.x, db.y = DEFAULTS.point, DEFAULTS.x, DEFAULTS.y
            ApplyPosition()
        end },
    },
})

function mod:OnEnable()
    db = self.db
    if db.whisper then db.thankMode = "whisper" end -- previous checkbox setting
    db.whisper = nil
    ApplyPosition()
    events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    ticker = C_Timer.NewTicker(1, ExpireEntries)
end

function mod:SetEditMode(on)
    anchor:SetShown(on)
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if ticker then ticker:Cancel(); ticker = nil end
    wipe(entries)
    anchor:Hide()
    Refresh()
    if dirty then events:RegisterEvent("PLAYER_REGEN_ENABLED") end -- buttons hide after combat
end
