-- ClassBar: a bar with the utility spells of your class (conjured food, portals, demons, pet care...).
-- A group of which you know one spell casts it; one of which you know several opens a small list.
--
-- The buttons are secure: they are built, placed and given their spells outside combat only. The
-- lists open and close through the game's secure snippets, so they work in combat too.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local Spells = ns.Spells -- set by Courtesy.lua

local DEFAULTS = {
    orientation = "horizontal", rows = 1, icons = 12, -- as an action bar in the game's Edit Mode
    iconSize = 100, padding = 2,
    grow = "both", -- "start": to the right or down, "end": to the left or up
    visible = "always", alwaysShow = false,
    hover = false,
    point = "BOTTOM", x = 0, y = 230,
}

---------------------------------------------------------------------------
-- The spells (vanilla ones, as on WoW Forever). Each group holds spells, each spell its ranks from
-- the first to the last: the best one known is cast.
---------------------------------------------------------------------------

local CLASS_GROUPS = {
    MAGE = {
        { label = L["Conjure food"], spells = { { 587, 597, 990, 6129, 10144, 10145, 28612 } } },
        { label = L["Conjure water"], spells = { { 5504, 5505, 5506, 6127, 10138, 10139, 10140 } } },
        { label = L["Mana gems"], spells = { { 10054 }, { 10053 }, { 3552 }, { 759 } } },
        { label = L["Teleports"], spells = { { 3567 }, { 3563 }, { 3566 }, { 3561 }, { 3562 }, { 3565 } } },
        { label = L["Portals"], spells = { { 11417 }, { 11418 }, { 11420 }, { 10059 }, { 11416 }, { 11419 } } },
    },
    WARLOCK = {
        { label = L["Soul Shards"], item = 6265, level = 10, spells = {} }, -- a counter, nothing to cast
        { label = L["Demons"], spells = { { 688 }, { 697 }, { 712 }, { 691 }, { 1122 }, { 18540 } } },
        { label = L["Healthstone"], spells = { { 6201, 6202, 5699, 11729, 11730 } } },
        { label = L["Soulstone"], spells = { { 693, 20752, 20755, 20756, 20757 } },
          items = { 16896, 16895, 16893, 16892, 5232 } }, -- best first: used when in the bags, else created
        { label = L["Weapon stones"], spells = { { 6366, 17951, 17952, 17953 }, { 2362, 17727, 17728 } } },
        { label = L["Ritual of Summoning"], spells = { { 698 } } },
        { label = L["Utility"], spells = { { 126 }, { 5697 }, { 132 }, { 5500 } } },
        { label = L["Mounts"], spells = { { 5784 }, { 23161 } } },
    },
    HUNTER = {
        { label = L["Call, revive or dismiss the pet"], spells = { { 883 }, { 982 }, { 2641 } } },
        { label = L["Mend the pet"], spells = { { 136, 3111, 3661, 3662, 13542, 13543, 13544 } } },
        { label = L["Feed the pet"], spells = { { 6991 } } },
        { label = L["Taming and training"], spells = { { 5149 }, { 1515 }, { 1462 }, { 1002 } } },
        { label = L["Tracking"], spells = { { 1494 }, { 19883 }, { 19884 }, { 19885 }, { 19880 }, { 19878 }, { 19882 }, { 19879 } } },
        { label = L["Utility"], spells = { { 6197 }, { 1543 } } },
    },
    SHAMAN = {
        { label = L["Astral Recall"], spells = { { 556 } } },
        { label = L["Resurrection"], spells = { { 2008, 20609, 20610, 20776, 20777 } } },
        { label = L["Utility"], spells = { { 2645 }, { 546 }, { 131 }, { 6196 } } },
    },
    DRUID = {
        { label = L["Teleports"], spells = { { 18960 } } },
        { label = L["Resurrection"], spells = { { 20484, 20739, 20742, 20747, 20748 } } },
        { label = L["Tracking"], spells = { { 5225 } } },
    },
    PRIEST = {
        { label = L["Resurrection"], spells = { { 2006, 2010, 10880, 10881, 20770 } } },
        { label = L["Utility"], spells = { { 1706 }, { 2096, 10909 } } },
    },
    PALADIN = {
        { label = L["Resurrection"], spells = { { 7328, 10322, 10324, 20772, 20773 } } },
        { label = L["Mounts"], spells = { { 13819 }, { 23214 } } },
        { label = L["Tracking"], spells = { { 5502 } } },
    },
    ROGUE = {
        { label = L["Poisons"], spells = { { 2842 } } },
        { label = L["Utility"], spells = { { 1804 }, { 921 }, { 1725 }, { 2836 }, { 1842 } } },
    },
}

local groups = CLASS_GROUPS[select(2, UnitClass("player"))] or {}

local mod, db
local slots = {} -- one per group, in the same order

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local container = CreateFrame("Frame", "TinkerwiseClassBar", UIParent)
container:SetSize(45, 45)
container:Hide()
TW:CreateMover(container, function() return db end, DEFAULTS)

local function ShowTooltip(self)
    if self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
        return
    end
    if not self.spellID then return end
    local stone = self.stones and self.stoneInBags
    if stone then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(stone)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.isList then
        GameTooltip:AddLine(self.label, 1, 1, 1)
        GameTooltip:AddLine(L["Click to choose"], 0.7, 0.7, 0.7)
    else
        GameTooltip:SetSpellByID(self.spellID)
    end
    GameTooltip:Show()
end

-- The art of the game's own action buttons, or the classic one where it doesn't exist.
local BUTTON_SIZE = 45
local FRAME_ATLAS = "UI-HUD-ActionBar-IconFrame"
ns.actionBarTextures = {} -- the borders, for the dark theme

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function PlaceBorder(texture)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT")
    texture:SetSize(BUTTON_SIZE + 1, BUTTON_SIZE)
end

-- The mask has empty margins: it keeps its own size around the icon, as on the game's buttons.
local function MaskIcon(b, icon)
    if not HasAtlas(FRAME_ATLAS .. "-Mask") then return end
    local mask = b:CreateMaskTexture()
    mask:SetAtlas(FRAME_ATLAS .. "-Mask", true)
    mask:SetPoint("CENTER", icon)
    icon:AddMaskTexture(mask)
end

-- An empty place of the bar ("always show buttons").
local function NewEmpty()
    local e = CreateFrame("Frame", nil, container)
    e:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    if HasAtlas(FRAME_ATLAS .. "-Background") then
        local back = e:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetAtlas(FRAME_ATLAS .. "-Background")
    end
    local border = e:CreateTexture(nil, "ARTWORK")
    if HasAtlas(FRAME_ATLAS) then
        border:SetAtlas(FRAME_ATLAS)
        PlaceBorder(border)
    else
        border:SetTexture("Interface\\Buttons\\UI-Quickslot")
        border:SetPoint("CENTER")
        border:SetSize(BUTTON_SIZE * 66 / 36, BUTTON_SIZE * 66 / 36)
    end
    ns.actionBarTextures[#ns.actionBarTextures + 1] = border
    return e
end

local function NewButton(name, parent)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    -- Both: the game acts on the one matching the "cast on key down" setting.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetAllPoints()
    if HasAtlas(FRAME_ATLAS) then
        MaskIcon(b, b.icon)
        b:SetNormalAtlas(FRAME_ATLAS)
        b:SetPushedAtlas(FRAME_ATLAS .. "-Down")
        b:SetHighlightAtlas(FRAME_ATLAS .. "-Mouseover")
        for _, texture in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
            PlaceBorder(texture)
        end
    else
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        local border = b:GetNormalTexture()
        border:ClearAllPoints()
        border:SetPoint("CENTER")
        border:SetSize(BUTTON_SIZE * 66 / 36, BUTTON_SIZE * 66 / 36)
        b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    ns.actionBarTextures[#ns.actionBarTextures + 1] = b:GetNormalTexture()
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetPoint("TOPLEFT", 3, -3)
    b.cooldown:SetPoint("BOTTOMRIGHT", -3, 3)
    b.cooldown:SetDrawEdge(false)
    b.cooldown:SetDrawBling(false)
    b.cooldown:SetSwipeColor(0, 0, 0, 0.64)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    return b
end

-- On the main button: opens or closes the list when the group has one, instead of casting.
local TOGGLE = [[
    if not self:GetAttribute("haslist") then return end
    if not down then
        if owner:IsShown() then
            owner:Hide()
        else
            owner:Show()
            owner:RegisterAutoHide(1)
            owner:AddToAutoHide(self)
        end
    end
    return false
]]

-- On a button of the list: closes it once the click is over.
local CLOSE_PRE = [[ if not down then return nil, "close" end ]]
local CLOSE_POST = [[ owner:Hide() ]]

local function BuildSlots()
    for i, group in ipairs(groups) do
        if not slots[i] then
            local slot = { buttons = {} }
            slot.main = NewButton("TinkerwiseClassBarButton" .. i, container)
            slot.main.label = group.label
            slot.main.arrow = slot.main:CreateTexture(nil, "OVERLAY")
            if HasAtlas("UI-HUD-ActionBar-Flyout") and SetClampedTextureRotation then
                slot.main.arrow:SetAtlas("UI-HUD-ActionBar-Flyout")
                slot.main.arrow:SetSize(18, 7)
                slot.main.arrow.turns = true
            else
                slot.main.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
                slot.main.arrow:SetSize(14, 14)
                slot.main.arrow:SetPoint("BOTTOMRIGHT", -2, 2)
            end
            slot.main.count = slot.main:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            slot.main.count:SetPoint("BOTTOMRIGHT", -5, 5)
            slot.list = CreateFrame("Frame", "TinkerwiseClassBarList" .. i, container, "SecureHandlerBaseTemplate")
            slot.list:SetFrameStrata("HIGH")
            slot.list:EnableMouse(true)
            slot.list:Hide()
            SecureHandlerWrapScript(slot.main, "OnClick", slot.list, TOGGLE)
            for j = 1, #group.spells do
                local b = NewButton("TinkerwiseClassBarList" .. i .. "Button" .. j, slot.list)
                b:SetAttribute("useOnKeyDown", false) -- on the way up, just before the list closes
                SecureHandlerWrapScript(b, "OnClick", slot.list, CLOSE_PRE, CLOSE_POST)
                slot.buttons[j] = b
            end
            slots[i] = slot
        end
    end
end

---------------------------------------------------------------------------
-- Cooldowns: the ones the game keeps secret (in combat) are left as they are.
---------------------------------------------------------------------------

local function UpdateCooldown(b)
    if not b:IsShown() or b.isList or not b.spellID then return b.cooldown:Clear() end
    local start, duration
    if b.stones then -- the stone's own cooldown (they share it), long after it was used
        local read = C_Container and C_Container.GetItemCooldown or GetItemCooldown
        for _, id in ipairs(b.stones) do
            local s, d = read(id)
            s, d = Spells.Plain(s), Spells.Plain(d)
            if s and d and (not duration or d > duration) then start, duration = s, d end
        end
    elseif C_Spell and C_Spell.GetSpellCooldown then
        local info = Spells.Plain(C_Spell.GetSpellCooldown(b.spellID))
        if info then start, duration = Spells.Plain(info.startTime), Spells.Plain(info.duration) end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(b.spellID)
    end
    if not start or not duration then return end
    if duration > 1.5 then b.cooldown:SetCooldown(start, duration) else b.cooldown:Clear() end -- no global cooldown
end

local function UpdateCooldowns()
    for _, slot in ipairs(slots) do
        UpdateCooldown(slot.main)
        for _, b in ipairs(slot.buttons) do UpdateCooldown(b) end
    end
end

---------------------------------------------------------------------------
-- Counters (soul shards): red when there are none left.
---------------------------------------------------------------------------

local function UpdateCounts()
    for _, slot in ipairs(slots) do
        local b = slot.main
        if b.itemID then
            local count = Spells.Plain(ns.API.GetItemCount(b.itemID))
            if count then
                b.count:SetText(count)
                b.count:SetTextColor(1, count > 0 and 1 or 0.2, count > 0 and 1 or 0.2)
                b.icon:SetDesaturated(count == 0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Layout (outside combat only)
---------------------------------------------------------------------------

-- The best rank known of each spell of the group, without those unticked in the options.
local function KnownSpells(group)
    local known = {}
    for _, ranks in ipairs(group.spells) do
        local name = #group.spells > 1 and Spells.Name(ranks[1])
        local skipped = name and db.skipSpells and db.skipSpells[name]
        for i = skipped and 0 or #ranks, 1, -1 do
            if Spells.Known(ranks[i]) then
                known[#known + 1] = ranks[i]
                break
            end
        end
    end
    return known
end

local function SetSpell(b, id)
    b.spellID = id
    b.isList = nil
    b.icon:SetTexture(Spells.Icon(id))
    b:SetAttribute("haslist", nil)
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", id) -- by id: "Create Healthstone (Minor)" would be read as a name and a rank
end

-- In a list: by name, as the demons are not summoned by id on WoW Forever. The empty brackets keep
-- "(Minor)" from being read as a rank.
local function SetListSpell(b, id)
    SetSpell(b, id)
    local name = Spells.Name(id)
    if not name then return end
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "/cast " .. name .. (name:find("(", 1, true) and "()" or ""))
end

-- A stone: the macro uses the one in the bags, on a friendly target or yourself, or creates one. In
-- combat it cannot change any more, so it then tries both in turn.
local function StoneInBags(b)
    for _, id in ipairs(b.stones) do
        local count = Spells.Plain(ns.API.GetItemCount(id))
        if count and count > 0 then return id end
    end
end

local function UpdateStone(b, forCombat)
    b.stoneInBags = StoneInBags(b)
    b.icon:SetTexture(b.stoneInBags and ns.API.GetItemIcon(b.stoneInBags) or Spells.Icon(b.spellID))
    if InCombatLockdown() then return end
    local lines = {}
    if b.stoneInBags or forCombat then
        for _, id in ipairs(b.stones) do
            lines[#lines + 1] = "/use [@target,help,nodead][@player] item:" .. id
        end
    end
    local name = Spells.Name(b.spellID)
    if name and (forCombat or not b.stoneInBags) then
        -- "Create Soulstone (Minor)": without the empty brackets, "Minor" would be read as a rank.
        lines[#lines + 1] = "/cast " .. name .. (name:find("(", 1, true) and "()" or "")
    end
    b:SetAttribute("haslist", nil)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", table.concat(lines, "\n"))
end

local function UpdateStones(forCombat)
    for _, slot in ipairs(slots) do
        if slot.main.stones and slot.main.spellID then UpdateStone(slot.main, forCombat) end
    end
end

local function SetCounter(b, id)
    b.itemID = id
    b.icon:SetTexture(ns.API.GetItemIcon(id))
    b:SetAttribute("type", nil)
    b:SetAttribute("haslist", nil)
end

local function SetList(b, id)
    b.spellID = id -- its icon stands for the list
    b.isList = true
    b.icon:SetTexture(Spells.Icon(id))
    b:SetAttribute("type", nil)
    b:SetAttribute("spell", nil)
    b:SetAttribute("haslist", true)
end

-- On the side the list opens to.
local function TurnArrow(arrow, side, degrees)
    if not arrow.turns then return end
    SetClampedTextureRotation(arrow, degrees)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", arrow:GetParent(), side)
end

-- Lists open towards the middle of the screen.
local function LayoutList(slot, count, vertical)
    local zoom = db.iconSize / 100
    local size = BUTTON_SIZE * zoom
    local step = size + db.padding
    local length = count * step + db.padding
    local x, y = container:GetCenter()
    local scale = container:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local list = slot.list
    list:ClearAllPoints()
    local towards
    if vertical then
        local right = (x or 0) * scale < UIParent:GetWidth() / 2
        list:SetSize(length, size)
        list:SetPoint(right and "LEFT" or "RIGHT", slot.main, right and "RIGHT" or "LEFT")
        towards = right and 1 or -1
        TurnArrow(slot.main.arrow, right and "RIGHT" or "LEFT", right and 90 or 270)
    else
        local up = (y or 0) * scale < UIParent:GetHeight() / 2
        list:SetSize(size, length)
        list:SetPoint(up and "BOTTOM" or "TOP", slot.main, up and "TOP" or "BOTTOM")
        towards = up and 1 or -1
        TurnArrow(slot.main.arrow, up and "TOP" or "BOTTOM", up and 0 or 180)
    end
    for j, b in ipairs(slot.buttons) do
        b:SetShown(j <= count)
        b:SetScale(zoom)
        b:ClearAllPoints()
        local offset = (db.padding + (j - 1) * step) * towards / zoom
        if vertical then
            local side = towards > 0 and "LEFT" or "RIGHT"
            b:SetPoint(side, list, side, offset, 0)
        else
            local side = towards > 0 and "BOTTOM" or "TOP"
            b:SetPoint(side, list, side, 0, offset)
        end
    end
end

-- The corner or side that stays in place when the bar gets longer or shorter.
local ANCHORS = {
    horizontal = { start = "BOTTOMLEFT", ["end"] = "BOTTOMRIGHT", both = "BOTTOM" },
    vertical = { start = "TOPLEFT", ["end"] = "BOTTOMLEFT", both = "LEFT" },
}

-- Saves the position from that point, without moving the bar, when it was saved from another one
-- (the bar was dragged, or the options changed).
local function AnchorPosition()
    local point = ANCHORS[db.orientation][db.grow]
    if not point or db.point == point then return end
    local left, bottom, width, height = container:GetRect()
    if not left then return end
    local x, y = left + width / 2 - UIParent:GetWidth() / 2, bottom + height / 2 - UIParent:GetHeight() / 2
    if point:find("LEFT") then
        x = left
    elseif point:find("RIGHT") then
        x = left + width - UIParent:GetWidth()
    end
    if point:find("BOTTOM") then
        y = bottom
    elseif point:find("TOP") then
        y = bottom + height - UIParent:GetHeight()
    end
    db.point, db.x, db.y = point, x, y
    container:ApplyPosition()
end

local empties = {}

local function Layout()
    local vertical = db.orientation == "vertical"
    local zoom = db.iconSize / 100
    local size = BUTTON_SIZE * zoom
    local step = size + db.padding
    local shown = {}
    for i, group in ipairs(groups) do
        local slot = slots[i]
        local wanted = not (db.skipGroups and db.skipGroups[group.label])
        if #shown >= db.icons then wanted = false end
        local known = wanted and KnownSpells(group) or {}
        local counter = wanted and group.item and UnitLevel("player") >= group.level
        slot.list:Hide()
        slot.main:SetShown(#known > 0 or counter or false)
        slot.main.arrow:SetShown(#known > 1)
        if counter then
            shown[#shown + 1] = { slot = slot, known = known }
            SetCounter(slot.main, group.item)
        elseif #known > 0 then
            shown[#shown + 1] = { slot = slot, known = known }
            slot.main.stones = group.items
            if group.items then
                slot.main.spellID, slot.main.isList = known[1], nil
                UpdateStone(slot.main)
            elseif #known == 1 then SetSpell(slot.main, known[1]) else SetList(slot.main, known[1]) end
        end
    end

    local total = #shown
    if total > 0 and db.alwaysShow then total = math.max(total, db.icons) end
    for i = 1, math.max(total - #shown, #empties) do
        empties[i] = empties[i] or NewEmpty()
        empties[i]:SetShown(i <= total - #shown)
    end

    -- As the game's bars: rows fill from the bottom up, columns from left to right.
    local lines = math.max(math.min(db.rows, total), 1)
    local perLine = math.max(math.ceil(total / lines), 1)
    lines = math.max(math.ceil(total / perLine), 1)
    local long, short = perLine * step - db.padding, lines * step - db.padding
    container:SetSize(vertical and short or long, vertical and long or short)
    container:ApplyPosition()
    if total > 0 then AnchorPosition() end
    local function Place(frame, i)
        local line, rank = math.floor((i - 1) / perLine), (i - 1) % perLine
        if db.grow == "end" then rank = perLine - 1 - rank end
        local column, row = rank, lines - 1 - line
        if vertical then column, row = line, rank end
        frame:SetScale(zoom)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", container, "TOPLEFT", column * step / zoom, -row * step / zoom)
    end
    for i = #shown + 1, total do Place(empties[i - #shown], i) end

    for i, entry in ipairs(shown) do
        local slot, known = entry.slot, entry.known
        Place(slot.main, i)
        for j, id in ipairs(known) do SetListSpell(slot.buttons[j], id) end
        LayoutList(slot, #known > 1 and #known or 0, vertical)
    end
    return #shown > 0
end

local editMode -- the bar in the game's Edit Mode
local pending = false -- something to apply once the fight is over

local function Apply()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    UnregisterStateDriver(container, "visibility")
    if not mod.active then
        container:Hide()
        return
    end
    BuildSlots()
    if not Layout() then
        container:Hide()
    elseif container:IsUnlocked() or db.visible == "always" then
        container:Show() -- always while it is being moved
    elseif db.visible == "inCombat" then
        RegisterStateDriver(container, "visibility", "[combat] show; hide")
    elseif db.visible == "outOfCombat" then
        RegisterStateDriver(container, "visibility", "[combat] hide; show")
    else
        container:Hide()
    end
    if ns.DarkenClassBar then ns.DarkenClassBar() end
    UpdateCooldowns()
    UpdateCounts()
end

-- Spell events come in bursts.
local scheduled = false
local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.5, function()
        scheduled = false
        if mod.active then
            Apply()
            editMode:Update() -- the first spell may just have been learned
        end
    end)
end

---------------------------------------------------------------------------
-- Mouseover: only the transparency changes, so it works in combat.
---------------------------------------------------------------------------

local ticker

local function UpdateAlpha()
    local over = not db.hover or container:IsUnlocked() or container:IsMouseOver()
    for _, slot in ipairs(slots) do
        over = over or slot.list:IsShown()
    end
    container:SetAlpha(over and 1 or 0)
end

local function ApplyHover()
    local wanted = mod.active and db.hover
    if wanted and not ticker then
        ticker = C_Timer.NewTicker(0.1, UpdateAlpha)
    elseif not wanted and ticker then
        ticker:Cancel()
        ticker = nil
    end
    if db then UpdateAlpha() end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then Apply() else UpdateStones() end
        -- The module was turned off during the fight: nothing left to wait for.
        if not mod.active then events:UnregisterAllEvents() end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateCooldowns()
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateCounts()
        UpdateStones()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateStones(true) -- the last moment the macro may still change
    else
        Schedule()
    end
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local function Relayout()
    if mod.active then Apply() end
end

-- The names the game's Edit Mode gives to the settings of an action bar, in the game's language.
local function GameText(key, fallback)
    local text = _G["HUD_EDIT_MODE_SETTING_ACTION_BAR_" .. key]
    return type(text) == "string" and text or fallback
end

mod = TW:NewModule("ClassBar", {
    title = L["Class Bar"],
    icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
    section = L["Character"],
    desc = L["A bar with the utility spells your class knows: conjured food and portals, demons and stones, pet care, tracking, resurrection... A button with an arrow opens a list to choose from. New spells and ranks are added as you learn them. Warriors have nothing to show."],
    defaults = DEFAULTS,
    options = {
        { type = "select", key = "orientation", label = GameText("ORIENTATION", L["Orientation"]),
          values = { { "horizontal", GameText("ORIENTATION_HORIZONTAL", L["Horizontal"]) },
                     { "vertical", GameText("ORIENTATION_VERTICAL", L["Vertical"]) } } },
        { type = "select", key = "grow", label = L["Extends"], values = {
            { "both", L["On both sides"] },
            { "start", L["To the right (down if vertical)"] },
            { "end", L["To the left (up if vertical)"] },
        } },
        { type = "slider", key = "rows", min = 1, max = 4, step = 1,
          label = GameText("NUM_ROWS", L["Rows"]) .. " / " .. GameText("NUM_COLUMNS", L["Columns"]) },
        { type = "slider", key = "icons", label = GameText("NUM_ICONS", L["Number of icons"]), min = 1, max = 12, step = 1 },
        { type = "slider", key = "iconSize", label = GameText("ICON_SIZE", L["Icon size"]) .. " (%)", min = 50, max = 200, step = 10 },
        { type = "slider", key = "padding", label = GameText("ICON_PADDING", L["Space between buttons"]), min = 2, max = 10, step = 1 },
        { type = "select", key = "visible", label = GameText("VISIBLE_SETTING", L["Bar visible"]), values = {
            { "always", GameText("VISIBLE_SETTING_ALWAYS", L["Always"]) },
            { "inCombat", GameText("VISIBLE_SETTING_IN_COMBAT", L["In combat"]) },
            { "outOfCombat", GameText("VISIBLE_SETTING_OUT_OF_COMBAT", L["Out of combat"]) },
            { "hidden", GameText("VISIBLE_SETTING_HIDDEN", L["Hidden"]) },
        } },
        { type = "toggle", key = "alwaysShow", label = GameText("ALWAYS_SHOW_BUTTONS", L["Always show buttons"]) },
        { type = "toggle", key = "hover", label = L["Only on mouseover"] },
        { type = "execute", label = L["Reset position"], editMode = "only", func = function()
            if InCombatLockdown() then return end
            container:ResetPosition()
            Relayout()
        end },
    },
})

editMode = ns.AddToEditMode({
    frame = container, mod = mod, label = L["Class Bar"],
    IsAvailable = function()
        for _, slot in ipairs(slots) do
            if slot.main:IsShown() then return true end
        end
        return false -- nothing to show
    end,
    OnEditing = function()
        Apply()
        UpdateAlpha()
    end,
    OnMoved = Apply, -- the lists may open on another side
})

-- One box per group of your class: an unticked one is not shown.
if #groups > 0 then
    mod.options[#mod.options + 1] = { type = "header", label = L["Buttons to show"] }
    mod.options[#mod.options + 1] = { type = "checklist", key = "skipGroups", items = function()
        local names = {}
        for _, group in ipairs(groups) do names[#names + 1] = group.label end
        return names
    end }
    -- And one per spell of the groups that hold several.
    for _, group in ipairs(groups) do
        if #group.spells > 1 then
            mod.options[#mod.options + 1] = { type = "header", label = group.label }
            mod.options[#mod.options + 1] = { type = "checklist", key = "skipSpells", items = function()
                local names = {}
                for _, ranks in ipairs(group.spells) do names[#names + 1] = Spells.Name(ranks[1]) end
                return names
            end }
        end
    end
end

function mod:OnEnable()
    db = self.db
    if db.hideInCombat then db.visible = "outOfCombat" end -- the option before the Edit Mode ones
    db.hideInCombat, db.size, db.spacing = nil, nil, nil
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
                         "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    Apply()
    ApplyHover()
end

function mod:OnDisable()
    if not InCombatLockdown() then events:UnregisterAllEvents() end
    Apply()
    ApplyHover()
end

function mod:OnOptionChanged()
    Apply()
    ApplyHover()
end
