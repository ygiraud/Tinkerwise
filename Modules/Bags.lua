-- Bags: remembers the bags, bank and gold of every character of the account, shows them with
-- each character's level and rest in the "Mes personnages" window (/tw chars) and adds who owns
-- what to item tooltips.

local _, ns = ...
local L = ns.L
local TW = ns.TW
local API = ns.API

local NumSlots, ContainerItem = API.ContainerNumSlots, API.ContainerItem
local GetCoinTextureString = API.GetCoinTextureString

local FIRST_BANK_BAG, BACKPACK, BANK_CONTAINER = 5, 0, -1
local LAST_BAG = 4
local SCAN_DELAY = 0.5 -- bag events come in bursts
local LIST_W, ROW_H = 230, 26
local FIRST_EQUIP_SLOT, LAST_EQUIP_SLOT = 1, 19 -- 0 (ammo) only mirrors the bags; 20 and up are the bags themselves
local HEARTHSTONE = 6948

local db
local bankOpen = false
local scanPending = false
local leavingWorld = false -- from the loading screen or logout until the next world entry
local moneyEmptied = false -- the game has just reported that the character spent all its gold

local function CountContainer(bag, into)
    for slot = 1, NumSlots(bag) or 0 do
        local id, count = ContainerItem(bag, slot)
        if id then into[id] = (into[id] or 0) + (count or 1) end
    end
end

local function CharacterKey()
    return TW:PlayerName() .. " - " .. GetRealmName()
end
ns.CharacterKey = CharacterKey

local function CurrentCharacter()
    local key = CharacterKey()
    local c = db.chars[key]
    if not c then
        c = { bags = {}, bank = {} }
        db.chars[key] = c
    end
    c.name, c.realm = TW:PlayerName(), GetRealmName()
    c.class = select(2, UnitClass("player"))
    c.mode = ns.CharacterGroups.GameMode()
    -- The game reads 0 while logging out: a 0 only counts after a real money change.
    local money = GetMoney()
    if money > 0 or moneyEmptied or not c.money then
        c.money, moneyEmptied = money, false
    end
    return c
end
ns.CurrentCharacter = CurrentCharacter -- also fed by the character list

-- Older clients have a main bank and bank bags, recent ones have purchased tabs.
local function ReadBank(into)
    local tabs = not NUM_BANKBAGSLOTS and C_Bank and C_Bank.FetchPurchasedBankTabData
        and Enum.BankType and C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
    if tabs then
        for _, tab in ipairs(tabs) do CountContainer(tab.ID, into) end
        return
    end
    CountContainer(BANK_CONTAINER, into)
    for bag = FIRST_BANK_BAG, LAST_BAG + (NUM_BANKBAGSLOTS or 6) do CountContainer(bag, into) end
end

-- "Sacs 3  Banque 5", leaving out the empty places.
local function Places(bags, bank, equip, mail)
    local parts = {}
    if (bags or 0) > 0 then parts[#parts + 1] = L["Bags "] .. bags end
    if (bank or 0) > 0 then parts[#parts + 1] = L["Bank "] .. bank end
    if (equip or 0) > 0 then parts[#parts + 1] = L["Worn "] .. equip end
    if (mail or 0) > 0 then parts[#parts + 1] = L["Mail "] .. mail end
    return table.concat(parts, "  ")
end

local Refresh

local function Scan()
    scanPending = false
    if not db then return end
    local c = CurrentCharacter()
    -- Nothing readable yet just after login: keep what is saved.
    if (NumSlots(BACKPACK) or 0) > 0 then
        local bags = {}
        for bag = BACKPACK, LAST_BAG do CountContainer(bag, bags) end
        if KEYRING_CONTAINER and HasKey and HasKey() then CountContainer(KEYRING_CONTAINER, bags) end
        c.bags = bags
    end
    local equip = {}
    for slot = FIRST_EQUIP_SLOT, LAST_EQUIP_SLOT do
        local id = GetInventoryItemID("player", slot)
        if id then equip[id] = (equip[id] or 0) + math.max(GetInventoryItemCount("player", slot) or 1, 1) end
    end
    c.equip = equip
    -- The bank can only be read while it is open.
    if bankOpen then
        local bank = {}
        ReadBank(bank)
        c.bank, c.bankTime = bank, time()
    end
    if Refresh then Refresh() end
end

-- The inbox can only be read while the mailbox is open.
local function ScanMail()
    if not db then return end
    local mail = {}
    for i = 1, GetInboxNumItems() do
        for slot = 1, ATTACHMENTS_MAX_RECEIVE or 12 do
            local link = GetInboxItemLink(i, slot)
            local id = link and API.GetItemInfoInstant(link)
            if id then
                local _, _, _, count = GetInboxItem(i, slot)
                mail[id] = (mail[id] or 0) + (count or 1)
            end
        end
    end
    CurrentCharacter().mail = mail
    if Refresh then Refresh() end
end

local function ScheduleScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(SCAN_DELAY, Scan)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local win, search, footer, listScroll, listChild
local selectedKey -- nil = all characters
local charButtons, itemRows = {}, {}

local function SortedKeys(isShown)
    local keys = {}
    for key, c in pairs(db.chars) do
        if isShown(key, c) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

-- Highest level first, then by name; characters never seen with a level come last.
local function ByLevel(keys)
    table.sort(keys, function(a, b)
        local la, lb = db.chars[a].level or 0, db.chars[b].level or 0
        if la ~= lb then return la > lb end
        return a < b
    end)
    return keys
end

local function ClassColored(c)
    local color = RAID_CLASS_COLORS[c.class]
    return color and format("|c%s%s|r", color.colorStr, c.name) or c.name
end
ns.ClassColored = ClassColored

local function CharButton(i)
    if charButtons[i] then return charButtons[i] end
    local b = CreateFrame("Button", nil, win)
    b:SetSize(LIST_W, 36)
    b:SetPoint("TOPLEFT", 22, -116 - (i - 1) * 38)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.mark = b:CreateTexture(nil, "BACKGROUND")
    b.mark:SetAllPoints()
    b.mark:SetColorTexture(1, 0.82, 0, 0.25)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("TOPLEFT", 6, -3)
    b.level = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.level:SetPoint("TOPRIGHT", -6, -4)
    b.money = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.money:SetPoint("BOTTOMLEFT", 6, 3)
    b.rested = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.rested:SetPoint("BOTTOMRIGHT", -6, 4)
    b:SetScript("OnClick", function(self)
        selectedKey = self.key
        Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        local c = self.key and db.chars[self.key]
        if not c then return end
        local list = ns.CharacterList
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ClassColored(c))
        if c.level then GameTooltip:AddDoubleLine(L["Level"], c.level, 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:AddDoubleLine(L["Gold"], GetCoinTextureString(c.money or 0), 1, 0.82, 0, 1, 1, 1)
        local rested = list.Rested(c)
        if rested then GameTooltip:AddDoubleLine(L["Rested (≈)"], rested, 1, 0.82, 0, 1, 1, 1) end
        if c.time then GameTooltip:AddDoubleLine(L["Last login"], list.Ago(time() - c.time), 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:AddDoubleLine(L["Bank"], c.bankTime and date(L["%m/%d/%Y"], c.bankTime) or L["never opened"],
            1, 0.82, 0, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    charButtons[i] = b
    return b
end

local function ItemRow(i)
    if itemRows[i] then return itemRows[i] end
    local r = CreateFrame("Button", nil, listChild)
    r:SetSize(380, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", -180, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemID)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    itemRows[i] = r
    return r
end

local function Build()
    win = CreateFrame("Frame", "TinkerwiseBagsFrame", UIParent, "BackdropTemplate")
    win:SetSize(680, 572)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    TW:SkinDialog(win, L["My Characters"])
    tinsert(UISpecialFrames, "TinkerwiseBagsFrame")

    search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    search:SetSize(380, 22)
    search:SetPoint("TOPLEFT", LIST_W + 40, -48)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() Refresh() end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", search, "TOPLEFT", -4, 2)
    hint:SetText(L["Search for an item"])

    listScroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", LIST_W + 36, -78)
    listScroll:SetPoint("BOTTOMRIGHT", -40, 52)
    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(380, 1)
    listScroll:SetScrollChild(listChild)

    footer = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    footer:SetPoint("BOTTOMLEFT", 26, 22)

    local forget = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    forget:SetSize(170, 22)
    forget:SetPoint("BOTTOMRIGHT", -24, 18)
    forget:SetText(L["Forget this character"])
    forget:SetScript("OnClick", function()
        if selectedKey then ns.ForgetCharacter(selectedKey) end
    end)
    win.forget = forget

    win.viewMenu = ns.CharacterGroups.CreateViewMenu(win, "TinkerwiseBagsGroupDropDown", 160)
    win.viewMenu:SetPoint("TOPLEFT", 6, -82)

    local function Filter(key, label, x, y)
        local check = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", x, y)
        check:SetChecked(db[key])
        check:SetScript("OnClick", function(self)
            db[key] = self:GetChecked() and true or false
            Refresh()
        end)
        local text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
        text:SetText(label)
    end
    Filter("showBags", L["Bags"], 24, -34)
    Filter("showBank", L["Bank"], 110, -34)
    Filter("showMail", L["Mail"], 24, -58)
    Filter("showWorn", L["Worn"], 110, -58)
end

-- Totals of the shown characters: { [id] = { bags, bank, equip, mail } }.
local function Totals()
    local totals = {}
    local function Add(from, field)
        for id, count in pairs(from or {}) do
            if id > 0 then -- older saves can hold an id of 0
                local t = totals[id]
                if not t then
                    t = { bags = 0, bank = 0, equip = 0, mail = 0 }
                    totals[id] = t
                end
                t[field] = t[field] + count
            end
        end
    end
    for key, c in pairs(db.chars) do
        if ns.CharacterGroups.IsViewed(key, c) and (not selectedKey or key == selectedKey) then
            if db.showBags then Add(c.bags, "bags") end
            if db.showBank then Add(c.bank, "bank") end
            if db.showMail then Add(c.mail, "mail") end
            if db.showWorn then Add(c.equip, "equip") end
        end
    end
    return totals
end

function Refresh()
    if not win or not win:IsShown() then return end

    local groups = ns.CharacterGroups
    UIDropDownMenu_SetText(win.viewMenu, groups.ViewedLabel())
    local chosen = selectedKey and db.chars[selectedKey]
    if not chosen or not groups.IsViewed(selectedKey, chosen) then selectedKey = nil end

    local gold = 0
    local keys = ByLevel(SortedKeys(groups.IsViewed))
    local allButton = CharButton(1)
    allButton.key = nil
    allButton.name:SetText(L["All characters"])
    allButton.level:SetText("")
    allButton.rested:SetText("")
    allButton.mark:SetShown(selectedKey == nil)
    allButton:Show()
    for i, key in ipairs(keys) do
        local c = db.chars[key]
        gold = gold + (c.money or 0)
        local b = CharButton(i + 1)
        b.key = key
        b.name:SetText(ClassColored(c))
        b.level:SetText(c.level and (L["Lvl"] .. " " .. c.level) or "")
        local rested = ns.CharacterList.Rested(c)
        b.rested:SetText(rested and rested ~= "----" and (L["Rested"] .. " " .. rested) or "")
        b.money:SetText(GetCoinTextureString(c.money or 0))
        b.mark:SetShown(selectedKey == key)
        b:Show()
    end
    for i = #keys + 2, #charButtons do charButtons[i]:Hide() end
    allButton.money:SetText(GetCoinTextureString(gold))

    local query = strtrim(search:GetText() or ""):lower()
    local items = {}
    for id, t in pairs(Totals()) do
        local name, _, quality = API.GetItemInfo(id)
        if query == "" or (name and name:lower():find(query, 1, true)) then
            items[#items + 1] = { id = id, name = name, quality = quality, places = Places(t.bags, t.bank, t.equip, t.mail) }
        end
    end
    table.sort(items, function(a, b)
        if a.name and b.name and a.name ~= b.name then return a.name < b.name end
        if (a.name ~= nil) ~= (b.name ~= nil) then return a.name ~= nil end
        return a.id < b.id
    end)

    listChild:SetHeight(math.max(#items * ROW_H, 1))
    for i, item in ipairs(items) do
        local r = ItemRow(i)
        r.itemID = item.id
        r.icon:SetTexture(API.GetItemIcon(item.id))
        r.name:SetText(item.name or L["Loading…"])
        if item.quality and GetItemQualityColor then
            -- Only three values: the fourth is a color string, not an alpha.
            local red, green, blue = GetItemQualityColor(item.quality)
            r.name:SetTextColor(red, green, blue)
        else
            r.name:SetTextColor(1, 1, 1)
        end
        r.count:SetText(item.places)
        r:Show()
    end
    for i = #items + 1, #itemRows do itemRows[i]:Hide() end

    local selected = selectedKey and db.chars[selectedKey]
    win.forget:SetShown(selected ~= nil)
    if selected and not selected.bankTime then
        footer:SetText(L["Bank not yet opened on this character"])
    elseif selected then
        footer:SetText(L["Bank last seen "] .. date(L["%m/%d/%Y"], selected.bankTime))
    else
        footer:SetText(L["Total gold: "] .. GetCoinTextureString(gold))
    end
end

local function Toggle()
    if not win then Build() end
    if win:IsShown() then return win:Hide() end
    ns.CharacterGroups.ResetView()
    ns.CharacterList.Save()
    Scan()
    win:Show()
    Refresh()
end

function ns.RefreshCharacterViews()
    Refresh()
end

function ns.ForgetCharacter(key)
    db.chars[key] = nil
    if selectedKey == key then selectedKey = nil end
    Scan() -- the current character may be the one just forgotten
    ns.CharacterGroups.Refresh()
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function AddOwners(tooltip, link)
    if not db or not db.tooltip or not TW.modules.Bags.active or not link then return end
    local id = API.GetItemInfoInstant(link)
    if not id or id == HEARTHSTONE or tooltip.twBagsShown == id then return end
    tooltip.twBagsShown = id

    local owners, total = {}, 0
    for _, key in ipairs(SortedKeys(ns.CharacterGroups.IsCurrentGroup)) do
        local c = db.chars[key]
        local bags, bank = c.bags and c.bags[id] or 0, c.bank and c.bank[id] or 0
        local equip, mail = c.equip and c.equip[id] or 0, c.mail and c.mail[id] or 0
        local count = bags + bank + equip + mail
        if count > 0 then
            owners[#owners + 1] = { c = c, places = Places(bags, bank, equip, mail) }
            total = total + count
        end
    end
    if #owners == 0 then return end
    tooltip:AddLine(" ")
    if #owners > 1 then tooltip:AddDoubleLine("Total", total, 1, 0.82, 0, 1, 1, 1) end
    for _, owner in ipairs(owners) do
        tooltip:AddDoubleLine(ClassColored(owner.c), owner.places, 1, 1, 1, 0.9, 0.84, 0.72)
    end
    tooltip:Show()
end

local function OnTooltipItem(tooltip)
    local _, link = tooltip:GetItem()
    AddOwners(tooltip, link)
end

-- Quest and profession items do not always go through the item script on older clients.
local LINK_GETTERS = {
    SetQuestItem = function(...) return GetQuestItemLink(...) end,
    SetQuestLogItem = function(...) return GetQuestLogItemLink(...) end,
    SetCraftItem = function(...) return GetCraftReagentItemLink(...) end,
    SetTradeSkillItem = function(skill, reagent)
        if reagent then return GetTradeSkillReagentItemLink(skill, reagent) end
        return GetTradeSkillItemLink(skill)
    end,
}

local hooked = false
local function HookTooltips()
    if hooked then return end
    hooked = true
    local useProcessor = TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if useProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then OnTooltipItem(tooltip) end
        end)
    end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            if not useProcessor and tooltip:HasScript("OnTooltipSetItem") then
                tooltip:HookScript("OnTooltipSetItem", OnTooltipItem)
            end
            if not useProcessor then
                for method, getLink in pairs(LINK_GETTERS) do
                    if tooltip[method] then
                        hooksecurefunc(tooltip, method, function(self, ...) AddOwners(self, getLink(...)) end)
                    end
                end
            end
            tooltip:HookScript("OnTooltipCleared", function(self) self.twBagsShown = nil end)
        end
    end
end

---------------------------------------------------------------------------
-- Gold of every character, when hovering the money of the bags
---------------------------------------------------------------------------

local function ShowGold(owner)
    if not db or not TW.modules.Bags.active then return end
    CurrentCharacter() -- brings the current money up to date
    local total = 0
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(L["Your characters' gold"])
    for _, key in ipairs(SortedKeys(ns.CharacterGroups.IsCurrentGroup)) do
        local c = db.chars[key]
        total = total + (c.money or 0)
        GameTooltip:AddDoubleLine(ClassColored(c), GetCoinTextureString(c.money or 0), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Total", GetCoinTextureString(total), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:Show()
end

local moneyFrames = {} -- frame -> whether it took the mouse before the module used it

local function HookMoney(frame)
    if not frame then return end
    local name = frame:GetName()
    moneyFrames[frame] = frame:IsMouseEnabled()
    local parts = { frame }
    if name then
        for _, coin in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
            parts[#parts + 1] = _G[name .. coin]
        end
    end
    for _, part in ipairs(parts) do
        part:HookScript("OnEnter", ShowGold)
        part:HookScript("OnLeave", function()
            if TW.modules.Bags.active then GameTooltip:Hide() end
        end)
    end
end

local moneyHooked = false
local function HookMoneyFrames()
    if moneyHooked then return end
    moneyHooked = true
    -- The backpack can open in any container frame, depending on which bags are already open.
    for i = 1, NUM_CONTAINER_FRAMES or 13 do HookMoney(_G["ContainerFrame" .. i .. "MoneyFrame"]) end
    HookMoney(_G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.MoneyFrame)
end

local function SetMoneyMouse(on)
    for frame, original in pairs(moneyFrames) do frame:EnableMouse(on or original) end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_INBOX_UPDATE" then
        ScanMail()
        return
    elseif event == "PLAYER_LEAVING_WORLD" then
        leavingWorld, moneyEmptied = true, false
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        leavingWorld = false
    elseif event == "PLAYER_MONEY" then
        moneyEmptied = not leavingWorld and GetMoney() == 0
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        return
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if win and win:IsShown() then ScheduleScan() end
        return
    end
    ScheduleScan()
end)

local mod = TW:NewModule("Bags", {
    title = L["My Characters"],
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    section = L["Character"],
    accountWide = true,
    perCharacterToggle = true,
    desc = L["Shows in one window (/tw chars) your characters' level, gold and rested XP, and what they keep in their bags, keyring, gear, bank and mail, with search and tooltips showing who owns what. Hover over a character for their last login. A character appears after their first login. Bags and gear update when they play, bank and mail when they open them; only rested XP is estimated, from elapsed time."]
        .. "\n\n" .. L["Characters are sorted by game mode (detected) and by the groups you create (/tw groups). The switch only applies to the current character, which stops recording its data when it is off."],
    defaults = { tooltip = true, showBags = true, showBank = true, showMail = false, showWorn = false },
    options = {
        { type = "toggle", key = "tooltip", label = L["Show owners in tooltips"] },
        { type = "execute", label = L["Show characters"], func = Toggle },
        { type = "execute", label = L["Manage groups"], func = function() ns.CharacterGroups.Toggle() end },
    },
})

function mod:OnEnable()
    db = self.db
    db.chars = db.chars or {}
    ns.CharacterGroups.Enable(db)
    ns.CharacterList.Enable(db)
    HookTooltips()
    HookMoneyFrames()
    SetMoneyMouse(true)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "BANKFRAME_OPENED",
                         "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED",
                         "PLAYER_EQUIPMENT_CHANGED", "MAIL_INBOX_UPDATE", "PLAYER_LEAVING_WORLD" }) do
        pcall(events.RegisterEvent, events, e)
    end
    if IsLoggedIn() then ScheduleScan() end
end

function mod:OnDisable()
    ns.CharacterList.Disable()
    ns.CharacterGroups.Disable()
    SetMoneyMouse(false)
    events:UnregisterAllEvents()
    bankOpen = false
    if win then win:Hide() end
end

TW.commands.chars = function()
    if mod.active then Toggle() else TW:Print(L["the My Characters module is disabled (/tw)."]) end
end
