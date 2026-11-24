-- Tinkerwise configuration window, in the same style as the check-up: warm brown dialog,
-- quest-title font, gold accents. Sections on the left (with how many of their modules are on) and
-- a search box that lists the matching modules instead. On the right, one tab per module of the
-- section, and the selected module with its options grouped into cards.
--
-- Option entries declared by modules:
--   { type = "toggle",  key, label }
--   { type = "slider",  key, label, min, max, step }
--   { type = "color",   key, label }    db[key] holds { r, g, b }; opens the game's color wheel
--   { type = "input",   key, label }
--   { type = "select",  key, label, values = { { value, label }, ... } }
--   { type = "execute", label, func }   consecutive buttons share a line
--   { type = "header",  label }         starts a new card
--   { type = "checklist", key, items }  items() returns names; db[key] holds the unticked ones
-- With editMode = "only", an option shows in the window of the game's Edit Mode (EditMode.lua) and not
-- here; with editMode = "never", the other way round.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local WIDTH, HEIGHT = 880, 640
local MIN_WIDTH, MIN_HEIGHT = 760, 480
local LIST_W = 250
local PANEL_MARGINS = LIST_W + 34 + 22 + 30 -- window width minus the width of the option cards
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD, TITLE, MUTED, BORDER -- set from TW.theme, see TW:OnTheme at the end
local PARCHMENT = { 0.9, 0.84, 0.72 }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local PANEL_TOP = -92
local TAB_H, TAB_GAP = 24, 4

local window, selected, footer, searchBox, noResult, list
local rows, panels = {}, {}       -- module rows (search results) and module panels, by module key
local sectionRows, tabBars = {}, {} -- one list row and one tab bar per section
local sectionSel = {}              -- section -> module last shown in it
local Select

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local Spaced = ns.Spaced

local function SectionOf(mod)
    return mod.section or L["Misc"]
end

local function RoundMask(tex, parent)
    if not parent.CreateMaskTexture then return end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

local function GoldRule(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
    if CreateColor then
        pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.7), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))
    end
    return t
end

local CARD_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function CreateCheck(parent, text)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(text)
    cb.label:SetTextColor(PARCHMENT[1], PARCHMENT[2], PARCHMENT[3])
    function cb:MinWidth() return self.label:GetStringWidth() + 32 end
    return cb
end

local function CreateSlider(parent, opt)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(380, 40)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(opt.label)

    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(260, 17)
    s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(opt.min, opt.max)
    s:SetValueStep(opt.step)
    s:SetObeyStepOnDrag(true)

    local low = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 0)
    low:SetText(opt.min)
    local high = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 0)
    high:SetText(opt.max)

    -- current value in a small gold-bordered box
    local box = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    box:SetSize(54, 22)
    box:SetPoint("LEFT", s, "RIGHT", 12, 0)
    box:SetBackdrop(CARD_BACKDROP)
    box:SetBackdropColor(0, 0, 0, 0.7)
    box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
    local value = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("CENTER")

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / opt.step + 0.5) * opt.step
        value:SetText(v)
        if not holder.refreshing then TW:SetOption(holder.mod, opt.key, v) end
    end)

    function holder:Refresh()
        self.refreshing = true
        s:SetValue(self.mod.db[opt.key])
        value:SetText(self.mod.db[opt.key])
        self.refreshing = false
    end
    function holder:MinWidth() return math.max(label:GetStringWidth(), 186) end
    function holder:SetLayoutWidth(width)
        self:SetWidth(width)
        s:SetWidth(math.min(260, width - 66)) -- room for the value box
    end
    return holder
end

local function OpenColorPicker(color, apply)
    local function Changed() apply(ColorPickerFrame:GetColorRGB()) end
    local function Cancelled() apply(color.r, color.g, color.b) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b, hasOpacity = false,
            swatchFunc = Changed, cancelFunc = Cancelled,
        })
    else -- older clients
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacityFunc = nil
        ColorPickerFrame.func = Changed
        ColorPickerFrame.cancelFunc = Cancelled
        ColorPickerFrame.previousValues = { color.r, color.g, color.b }
        ColorPickerFrame:SetColorRGB(color.r, color.g, color.b)
        ColorPickerFrame:Show()
    end
end

local function CreateColorOption(parent, opt, mod)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(32, 22)
    b:SetBackdrop(CARD_BACKDROP)
    b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
    local swatch = b:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 4, -4)
    swatch:SetPoint("BOTTOMRIGHT", -4, 4)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    label:SetText(opt.label)
    label:SetTextColor(PARCHMENT[1], PARCHMENT[2], PARCHMENT[3])

    function b:Refresh()
        local c = mod.db[opt.key]
        swatch:SetColorTexture(c.r, c.g, c.b)
    end
    function b:MinWidth() return label:GetStringWidth() + 40 end
    b:SetScript("OnClick", function(self)
        OpenColorPicker(mod.db[opt.key], function(r, g, bl)
            TW:SetOption(mod, opt.key, { r = r, g = g, b = bl })
            self:Refresh()
        end)
    end)
    return b
end

local function CreateInput(parent, opt, mod)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(380, 44)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(opt.label)
    local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    box:SetSize(340, 20)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function(self)
        TW:SetOption(mod, opt.key, self:GetText())
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self) TW:SetOption(mod, opt.key, self:GetText()) end)
    box:SetScript("OnEscapePressed", function(self) w:Refresh(); self:ClearFocus() end)
    function w:Refresh() box:SetText(mod.db[opt.key] or "") end
    function w:MinWidth() return math.max(label:GetStringWidth(), 200) end
    function w:SetLayoutWidth(width)
        self:SetWidth(width)
        box:SetWidth(math.min(340, width - 12))
    end
    return w
end

-- Drop-down list: opt.values = { { value, label }, ... }
local dropCount = 0
local function CreateSelect(parent, opt, mod)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(380, 50)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(opt.label)

    dropCount = dropCount + 1
    local dd = CreateFrame("Frame", "TinkerwiseDropDown" .. dropCount, w, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dd, 200)

    local function LabelOf(value)
        for _, v in ipairs(opt.values) do
            if v[1] == value then return v[2] end
        end
        return tostring(value)
    end

    UIDropDownMenu_Initialize(dd, function()
        for _, v in ipairs(opt.values) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v[2]
            info.checked = mod.db[opt.key] == v[1]
            info.func = function()
                UIDropDownMenu_SetText(dd, v[2]) -- first: the choice shows even if applying it fails
                TW:SetOption(mod, opt.key, v[1])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- The game's list can open under this window (same strata): the options below the list then
    -- took the clicks. Bring it up front each time it opens.
    local opener = dd.Button or _G[dd:GetName() .. "Button"]
    if opener then
        opener:HookScript("OnClick", function()
            local list = _G.DropDownList1
            if list and list:IsShown() then
                list:SetFrameStrata("FULLSCREEN_DIALOG")
                list:Raise()
            end
        end)
    end

    function w:Refresh() UIDropDownMenu_SetText(dd, LabelOf(mod.db[opt.key])) end
    function w:MinWidth() return math.max(label:GetStringWidth(), 236) end
    return w
end

-- The widget of an option, its height, its horizontal offset in a card and whether it is a button.
-- Nothing for the headers and the checklists, which hold several.
local function CreateOption(parent, opt, mod)
    if opt.type == "toggle" then
        local w = CreateCheck(parent, opt.label)
        w:SetScript("OnClick", function(self)
            PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            TW:SetOption(mod, opt.key, self:GetChecked() and true or false)
        end)
        function w:Refresh() self:SetChecked(mod.db[opt.key]) end
        return w, 28, -4
    elseif opt.type == "slider" then
        return CreateSlider(parent, opt), 54
    elseif opt.type == "color" then
        return CreateColorOption(parent, opt, mod), 30
    elseif opt.type == "input" then
        return CreateInput(parent, opt, mod), 50
    elseif opt.type == "select" then
        return CreateSelect(parent, opt, mod), 56
    elseif opt.type == "execute" then
        local w = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        w:SetText(opt.label)
        w:SetSize(w:GetFontString():GetStringWidth() + 30, 22)
        w:SetScript("OnClick", function() opt.func(mod) end)
        function w:Refresh() self:SetEnabled(mod.active and true or false) end -- actions need an active module
        return w, 28, 0, true
    end
end
ns.CreateOption = CreateOption -- also for the windows of EditMode.lua

-- Pill-shaped on/off button: "ACTIVÉ" in green or "DÉSACTIVÉ" in grey.
local function CreateSwitch(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(120, 26)
    b:SetBackdrop(CARD_BACKDROP)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick(self)
    end)
    function b:SetOn(on)
        if on then
            self:SetBackdropColor(0.05, 0.25, 0.05, 0.95)
            self:SetBackdropBorderColor(0.3, 1, 0.3, 1)
            self.text:SetText(Spaced(L["ON"]))
            self.text:SetTextColor(0.4, 1, 0.4)
        else
            self:SetBackdropColor(0.12, 0.1, 0.08, 0.95)
            self:SetBackdropBorderColor(0.5, 0.45, 0.4, 1)
            self.text:SetText(Spaced(L["OFF"]))
            self.text:SetTextColor(0.6, 0.55, 0.5)
        end
    end
    return b
end

---------------------------------------------------------------------------
-- Module panel
---------------------------------------------------------------------------

-- Identifies the current checklist items, to rebuild a panel when they change.
local function ChecklistSignature(mod)
    local parts = {}
    for _, opt in ipairs(mod.options or {}) do
        if opt.type == "checklist" then parts[#parts + 1] = table.concat(opt.items(), "\n") end
    end
    return table.concat(parts, "\n")
end

-- Places a card's options on two columns and returns the card's height. Short options sit side
-- by side; one that does not fit half the card takes a whole line. Buttons flow on their own lines.
local function LayoutCard(card, cardW)
    local PAD, GAP = 14, 16
    local colW = (cardW - 2 * PAD - GAP) / 2
    local cy, rowH, leftUsed, bx = -30, 0, false, nil

    local function EndRow()
        cy, rowH, leftUsed, bx = cy - rowH, 0, false, nil
    end
    local function Place(item, x)
        item.widget:ClearAllPoints()
        item.widget:SetPoint("TOPLEFT", card, "TOPLEFT", x, cy)
        rowH = math.max(rowH, item.height)
    end

    for _, item in ipairs(card.items) do
        local w = item.widget
        if item.isButton then
            if leftUsed or (bx and bx + w:GetWidth() > cardW - 16) then EndRow() end
            bx = bx or 16
            Place(item, bx)
            bx = bx + w:GetWidth() + 6
        else
            if bx then EndRow() end
            local width
            if w:MinWidth() <= colW then
                width = colW
                Place(item, (leftUsed and PAD + colW + GAP or PAD) + item.dx)
                if leftUsed then EndRow() else leftUsed = true end
            else
                if leftUsed then EndRow() end
                width = cardW - 2 * PAD
                Place(item, PAD + item.dx)
                EndRow()
            end
            if w.SetLayoutWidth then w:SetLayoutWidth(width) end
        end
    end
    EndRow()
    return -cy + 8
end

local function BuildPanel(mod)
    local outer = CreateFrame("Frame", nil, window)
    outer.signature = ChecklistSignature(mod)
    outer.section = SectionOf(mod)
    outer.widgets = {}

    -- Header: icon, section, title, on/off switch, description
    local iconHolder = CreateFrame("Frame", nil, outer)
    iconHolder:SetSize(40, 40)
    iconHolder:SetPoint("TOPLEFT", 4, -4)
    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(mod.icon or DEFAULT_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local frame = iconHolder:CreateTexture(nil, "OVERLAY")
    frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    frame:SetSize(70, 70)
    frame:SetPoint("CENTER")

    local section = outer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    section:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 14, 0)
    section:SetText(Spaced(SectionOf(mod):upper()))
    section:SetTextColor(MUTED[1], MUTED[2], MUTED[3])

    local title = outer:CreateFontString(nil, "OVERLAY")
    title:SetFont(TITLE_FONT, 24, "")
    title:SetTextColor(TITLE[1], TITLE[2], TITLE[3])
    title:SetPoint("TOPLEFT", section, "BOTTOMLEFT", 0, -2)
    title:SetText(mod.title or mod.key)

    outer.switch = CreateSwitch(outer, function()
        TW:SetModuleEnabled(mod, not mod.active)
        TW:RefreshConfig()
    end)
    outer.switch:SetPoint("TOPRIGHT", -2, -8)
    outer.switch:SetShown(not mod.alwaysEnabled)

    local desc = outer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", iconHolder, "BOTTOMLEFT", 0, -12)
    desc:SetPoint("RIGHT", outer, "RIGHT", -4, 0)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(2)
    desc:SetTextColor(PARCHMENT[1], PARCHMENT[2], PARCHMENT[3])
    desc:SetText(mod.desc or "")

    local rule = GoldRule(outer)
    rule:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    rule:SetPoint("RIGHT", outer, "RIGHT", 0, 0)

    -- Options, grouped into cards, in a scroll frame
    local scroll = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(window:GetWidth() - PANEL_MARGINS, 1)
    scroll:SetScrollChild(content)

    local cards = {}
    function outer:ApplyWidth()
        local contentW = window:GetWidth() - PANEL_MARGINS
        content:SetWidth(contentW)
        local y = 0
        for _, c in ipairs(cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, y)
            c:SetWidth(contentW)
            local height = LayoutCard(c, contentW)
            c:SetHeight(height)
            y = y - height - 16
        end
        content:SetHeight(-y + 10)
    end

    local card

    local function AddItem(widget, height, dx, isButton)
        card.items[#card.items + 1] = { widget = widget, height = height, dx = dx or 2, isButton = isButton }
    end

    local function OpenCard(label)
        card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card.items = {}
        cards[#cards + 1] = card
        card:SetBackdrop(CARD_BACKDROP)
        card:SetBackdropColor(0.06, 0.04, 0.02, 0.75)
        card:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.9)
        local head = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", 14, -10)
        head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        head:SetText(Spaced(label:upper()))
        local line = GoldRule(card)
        line:SetPoint("LEFT", head, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    end

    for _, opt in ipairs(mod.options or {}) do
        if opt.type == "header" then
            OpenCard(opt.label)
        elseif opt.editMode ~= "only" then
            if not card then OpenCard(L["Settings"]) end
            local w, height, offset, isButton = CreateOption(card, opt, mod)
            if w then
                AddItem(w, height, offset, isButton)
            elseif opt.type == "checklist" then
                -- one box per item; db[key] holds the unticked names, so new items start ticked
                for _, name in ipairs(opt.items()) do
                    local check = CreateCheck(card, name)
                    check:SetScript("OnClick", function(self)
                        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                        local unticked = mod.db[opt.key] or {}
                        unticked[name] = not self:GetChecked() or nil
                        TW:SetOption(mod, opt.key, unticked)
                    end)
                    function check:Refresh()
                        local unticked = mod.db[opt.key]
                        self:SetChecked(not (unticked and unticked[name]))
                    end
                    AddItem(check, 28, -4)
                    check.mod = mod
                    outer.widgets[#outer.widgets + 1] = check
                end
            end
            if w then
                w.mod = mod
                outer.widgets[#outer.widgets + 1] = w
            end
        end
    end
    outer:ApplyWidth()
    return outer
end


---------------------------------------------------------------------------
-- Sections and tabs
---------------------------------------------------------------------------

-- Sections in the order of their first module, each with its modules.
local function Sections()
    local sections, bySection = {}, {}
    for _, mod in ipairs(TW.order) do
        local section = SectionOf(mod)
        if not bySection[section] then
            bySection[section] = {}
            sections[#sections + 1] = section
        end
        table.insert(bySection[section], mod)
    end
    return sections, bySection
end

-- Tab bar over the panel, one tab per module of the section. A section of one module has none.
-- Tabs that do not fit on one line go on to the next.
local function BuildTabBar(section, mods)
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("TOPLEFT", window, "TOPLEFT", LIST_W + 34, PANEL_TOP)
    bar:SetPoint("RIGHT", window, "RIGHT", -22, 0)
    bar:SetHeight(1)
    bar:Hide()
    bar.tabs, bar.height = {}, 0
    tabBars[section] = bar
    if #mods < 2 then return end

    for _, mod in ipairs(mods) do
        local tab = CreateFrame("Button", nil, bar)
        tab.mod = mod
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER", 0, 1)
        tab.text:SetText(mod.title or mod.key)
        tab:SetSize(tab.text:GetStringWidth() + 26, TAB_H)
        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.14)
        tab.line = tab:CreateTexture(nil, "ARTWORK")
        tab.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        tab.line:SetHeight(2)
        tab.line:SetPoint("BOTTOMLEFT")
        tab.line:SetPoint("BOTTOMRIGHT")
        tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        tab:SetScript("OnClick", function() Select(mod) end)
        bar.tabs[#bar.tabs + 1] = tab
    end
    local rule = GoldRule(bar)
    rule:SetPoint("BOTTOMLEFT", 0, 6)
    rule:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

    function bar:Layout()
        local width = window:GetWidth() - (LIST_W + 34) - 22
        local x, y = 0, 0
        for _, tab in ipairs(self.tabs) do
            local w = tab:GetWidth()
            if x > 0 and x + w > width then x, y = 0, y - TAB_H - TAB_GAP end
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
            x = x + w + TAB_GAP
        end
        self.height = -y + TAB_H + 14
        self:SetHeight(self.height)
    end
    bar:Layout()
end

local function PlacePanel(panel, dx)
    local bar = tabBars[panel.section]
    dx = dx or 0
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", window, "TOPLEFT", LIST_W + 34 + dx, PANEL_TOP - (bar and bar.height or 0))
    panel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22 + dx, 52)
end

---------------------------------------------------------------------------
-- Search: matches module titles, descriptions, sections and option labels.
---------------------------------------------------------------------------

local searchText = {} -- module key -> lowercase text searched

-- string.lower leaves accented capitals as they are: "É" must match "é".
local ACCENTED_CAPITALS = {
    ["À"] = "à", ["Â"] = "â", ["Ç"] = "ç", ["É"] = "é", ["È"] = "è", ["Ê"] = "ê", ["Ë"] = "ë",
    ["Î"] = "î", ["Ï"] = "ï", ["Ô"] = "ô", ["Ù"] = "ù", ["Û"] = "û", ["Ü"] = "ü",
}
local function Lower(s)
    return (s:lower():gsub("\195[\128-\159]", ACCENTED_CAPITALS))
end

local function SearchTextOf(mod)
    if searchText[mod.key] then return searchText[mod.key] end
    local parts = { mod.title or mod.key, mod.desc or "", SectionOf(mod) }
    for _, opt in ipairs(mod.options or {}) do
        if opt.label then parts[#parts + 1] = opt.label end
        for _, v in ipairs(opt.values or {}) do parts[#parts + 1] = tostring(v[2]) end
    end
    searchText[mod.key] = Lower(table.concat(parts, "\n"))
    return searchText[mod.key]
end

local function Query()
    return searchBox and Lower(strtrim(searchBox:GetText() or "")) or ""
end

local function Matches(mod, query)
    return SearchTextOf(mod):find(query, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

-- Panels slide in from the right when switching modules.
local slide = { t = 1 }
function Select(mod)
    selected = mod
    local section = SectionOf(mod)
    sectionSel[section] = mod
    local existing = panels[mod.key]
    if existing and existing.signature ~= ChecklistSignature(mod) then
        existing:Hide()
        panels[mod.key] = nil
    end
    if not panels[mod.key] then panels[mod.key] = BuildPanel(mod) end
    for key, panel in pairs(panels) do panel:SetShown(key == mod.key) end
    for name, bar in pairs(tabBars) do bar:SetShown(name == section and #bar.tabs > 0) end
    PlacePanel(panels[mod.key])
    slide.panel, slide.t = panels[mod.key], 0
    PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    TW:RefreshConfig()
end

-- List row: stripe, gold bar when selected, round icon with a gold ring, name.
local function NewRow(parent, icon, text)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(LIST_W - 30, 30)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.stripe:SetBlendMode("ADD")
    row.stripe:SetAllPoints()
    row.stripe:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    row.bar:SetSize(3, 26)
    row.bar:SetPoint("LEFT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexture(icon or DEFAULT_ICON)
    RoundMask(row.icon, row)
    row.ring = row:CreateTexture(nil, "BORDER") -- thin gold circle around the round icon
    row.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    row.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
    row.ring:SetSize(26, 26)
    row.ring:SetPoint("CENTER", row.icon, "CENTER")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetText(text)
    return row
end

-- Colors a row: selected, on, or off.
local function PaintRow(row, on, isSel)
    row.stripe:SetAlpha(isSel and 0.35 or 0)
    row.bar:SetShown(isSel)
    row.icon:SetDesaturated(not on)
    row.icon:SetAlpha(on and 1 or 0.6)
    if isSel then
        row.text:SetTextColor(1, 0.95, 0.8)
    elseif on then
        row.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else
        row.text:SetTextColor(0.5, 0.45, 0.4)
    end
end

-- A section in the list: its modules' on count on the right.
local function BuildSectionRow(section, mods, parent)
    local row = NewRow(parent, mods[1].icon, section)
    row.section, row.mods = section, mods
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnClick", function() Select(sectionSel[section] or mods[1]) end)
    sectionRows[#sectionRows + 1] = row
end

-- A module in the search results, with its on/off pip.
local function BuildRow(mod, parent)
    local row = NewRow(parent, mod.icon, mod.title or mod.key)
    row.mod = mod

    -- on/off pip: click to toggle the module without selecting it
    row.pip = CreateFrame("Button", nil, row)
    row.pip:SetSize(16, 16)
    row.pip:SetShown(not mod.alwaysEnabled)
    row.pip:SetPoint("RIGHT", -4, 0)
    row.pip.tex = row.pip:CreateTexture(nil, "ARTWORK")
    row.pip.tex:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    row.pip.tex:SetSize(8, 8)
    row.pip.tex:SetPoint("CENTER")
    row.pip.glow = row.pip:CreateTexture(nil, "BACKGROUND")
    row.pip.glow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    row.pip.glow:SetBlendMode("ADD")
    row.pip.glow:SetSize(12, 12)
    row.pip.glow:SetPoint("CENTER")
    row.pip:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        TW:SetModuleEnabled(mod, not mod.active)
        TW:RefreshConfig()
    end)
    row.pip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(mod.active and L["Click to disable"] or L["Click to enable"])
        GameTooltip:Show()
    end)
    row.pip:SetScript("OnLeave", GameTooltip_Hide)

    -- the section, small and muted, under the name
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
    row.sub:SetText(SectionOf(mod))
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 5)
    row.text:SetPoint("RIGHT", row, "RIGHT", -24, 5)

    row:SetScript("OnClick", function() Select(mod) end)
    rows[#rows + 1] = row
end

-- Sections when the search box is empty, else the matching modules.
local function LayoutList()
    local query = Query()
    local y = -4
    for _, row in ipairs(sectionRows) do
        row:SetShown(query == "")
        if query == "" then
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, y)
            y = y - 34
        end
    end
    local found = 0
    for _, row in ipairs(rows) do
        local show = query ~= "" and Matches(row.mod, query)
        row:SetShown(show)
        if show then
            found = found + 1
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, y)
            y = y - 34
        end
    end
    noResult:SetShown(query ~= "" and found == 0)
    list:SetHeight(-y + 4)
end

local function BuildSearch(inset)
    searchBox = CreateFrame("EditBox", nil, inset, "InputBoxTemplate")
    searchBox:SetPoint("TOPLEFT", 16, -10)
    searchBox:SetPoint("TOPRIGHT", -10, -10)
    searchBox:SetHeight(22)
    searchBox:SetAutoFocus(false)
    local hint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText(L["Search..."])
    local function UpdateHint()
        hint:SetShown(searchBox:GetText() == "" and not searchBox:HasFocus())
    end
    searchBox:SetScript("OnEditFocusGained", UpdateHint)
    searchBox:SetScript("OnEditFocusLost", UpdateHint)
    searchBox:SetScript("OnTextChanged", function()
        UpdateHint()
        LayoutList()
        TW:RefreshConfig()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    -- Enter opens the first result.
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        for _, row in ipairs(rows) do
            if row:IsShown() then return Select(row.mod) end
        end
    end)
end

local function BuildWindow()
    window = CreateFrame("Frame", "TinkerwiseConfigFrame", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    tinsert(UISpecialFrames, "TinkerwiseConfigFrame") -- close with Escape
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local theme = TW.theme
    window:SetBackdropColor(theme.backdrop[1], theme.backdrop[2], theme.backdrop[3], 1)
    TW:AddSolidBackground(window, theme.solid[1], theme.solid[2], theme.solid[3])
    window:SetToplevel(true) -- comes in front as a whole when shown or clicked
    CreateFrame("Button", nil, window, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)
    window:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
    window:SetScript("OnHide", function(self)
        if not self.ready then return end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)

    -- Header: round emblem, title, tagline
    local emblem = window:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(44, 44)
    emblem:SetPoint("TOPLEFT", 26, -22)
    emblem:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
    RoundMask(emblem, window)
    local emblemRing = window:CreateTexture(nil, "BORDER")
    emblemRing:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    emblemRing:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    emblemRing:SetSize(50, 50)
    emblemRing:SetPoint("CENTER", emblem, "CENTER")

    local title = window:CreateFontString(nil, "OVERLAY")
    title:SetFont(TITLE_FONT, 32, "")
    title:SetTextColor(TITLE[1], TITLE[2], TITLE[3])
    title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 16, 4)
    title:SetText("Tinkerwise")
    local tagline = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -2)
    tagline:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("Tinkerwise", "Version") or ""
    tagline:SetText(Spaced(L["PERSONAL TOOLBOX"]) .. "   |cff998866v" .. version .. "|r")

    local headRule = GoldRule(window)
    headRule:SetPoint("TOPLEFT", 22, -80)
    headRule:SetPoint("RIGHT", window, "RIGHT", -22, 0)

    -- Section list in a dark inset, with the search box on top
    local inset = CreateFrame("Frame", nil, window, "BackdropTemplate")
    inset:SetPoint("TOPLEFT", 16, -88)
    inset:SetPoint("BOTTOMLEFT", 16, 46)
    inset:SetWidth(LIST_W + 6)
    inset:SetBackdrop(CARD_BACKDROP)
    inset:SetBackdropColor(0.04, 0.03, 0.02, 0.8)
    inset:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.9)
    BuildSearch(inset)

    -- The list scrolls when there are more rows than fit.
    local listScroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 6, -40)
    listScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    list = CreateFrame("Frame", nil, listScroll)
    list:SetWidth(LIST_W - 24)
    listScroll:SetScrollChild(list)
    noResult = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noResult:SetPoint("TOPLEFT", 10, -10)
    noResult:SetText(L["No results"])

    local sections, bySection = Sections()
    for _, section in ipairs(sections) do
        BuildSectionRow(section, bySection[section], list)
        BuildTabBar(section, bySection[section])
    end
    for _, mod in ipairs(TW.order) do BuildRow(mod, list) end
    LayoutList()

    -- Footer: active modules count and close button
    footer = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("BOTTOMLEFT", 26, 22)
    footer:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", -22, 16)
    close:SetText(L["Close"])
    close:SetScript("OnClick", function() window:Hide() end)

    -- Resize grip, bottom right. The size is saved per character.
    local saved = TinkerwiseCharDB.configSize
    if saved then window:SetSize(math.max(saved.w, MIN_WIDTH), math.max(saved.h, MIN_HEIGHT)) end
    window:SetResizable(true)
    if window.SetResizeBounds then
        window:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    elseif window.SetMinResize then
        window:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    window:SetScript("OnSizeChanged", function()
        for _, bar in pairs(tabBars) do
            if bar.Layout then bar:Layout() end
        end
        for _, panel in pairs(panels) do
            panel:ApplyWidth()
            PlacePanel(panel)
        end
    end)
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        TinkerwiseCharDB.configSize = { w = window:GetWidth(), h = window:GetHeight() }
    end)

    window:SetScript("OnUpdate", function(_, elapsed)
        if slide.t >= 1 or not slide.panel then return end
        slide.t = math.min(1, slide.t + elapsed / 0.2)
        local p = 1 - (1 - slide.t) ^ 3
        slide.panel:SetAlpha(p)
        PlacePanel(slide.panel, (1 - p) * 16)
    end)

    if TW.order[1] then Select(TW.order[1]) end
    window:Hide() -- ToggleConfig shows it
    window.ready = true
end

function TW:RefreshConfig()
    if not window then return end
    local active = 0
    for _, mod in ipairs(TW.order) do
        if mod.active then active = active + 1 end
    end
    local selSection = selected and SectionOf(selected)

    for _, row in ipairs(sectionRows) do
        local on = 0
        for _, mod in ipairs(row.mods) do
            if mod.active then on = on + 1 end
        end
        PaintRow(row, on > 0, row.section == selSection)
        row.count:SetText(on .. "/" .. #row.mods)
        row.count:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    end
    for _, row in ipairs(rows) do
        local on = row.mod.active
        PaintRow(row, on, row.mod == selected)
        if on then
            row.pip.tex:SetVertexColor(0.36, 0.62, 0.3)
            row.pip.glow:SetVertexColor(0.36, 0.62, 0.3, 0.15)
            row.pip.glow:Show()
        else
            row.pip.tex:SetVertexColor(0.35, 0.3, 0.25)
            row.pip.glow:Hide()
        end
    end
    -- Tabs: the selected one underlined, the modules turned off in grey.
    local bar = selSection and tabBars[selSection]
    for _, tab in ipairs(bar and bar.tabs or {}) do
        local isSel = tab.mod == selected
        tab.line:SetShown(isSel)
        tab.bg:SetShown(isSel)
        if isSel then
            tab.text:SetTextColor(1, 0.95, 0.8)
        elseif tab.mod.active then
            tab.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else
            tab.text:SetTextColor(0.5, 0.45, 0.4)
        end
    end
    footer:SetText(Spaced(format(L["%d / %d ACTIVE MODULES"], active, #TW.order)))

    local panel = selected and panels[selected.key]
    if panel then
        panel.switch:SetOn(selected.active)
        for _, w in ipairs(panel.widgets) do
            if w.Refresh then w:Refresh() end
        end
    end
end

function TW:ToggleConfig()
    if not window then BuildWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        if selected and panels[selected.key].signature ~= ChecklistSignature(selected) then Select(selected) end
        self:RefreshConfig()
    end
end

-- Colors follow the theme (gold or class color). The window is built with them, so a change
-- rebuilds it, on the same module and at the same place.
TW:OnTheme(function(theme)
    GOLD, TITLE, MUTED, BORDER = theme.accent, theme.title, theme.muted, theme.border
    if not window then return end
    local old, wasShown, current = window, window:IsShown(), selected
    local point = { old:GetPoint() }
    old.ready = false -- no closing sound
    old:Hide()
    rows, panels, sectionRows, tabBars, selected = {}, {}, {}, {}, nil
    BuildWindow()
    if point[1] then
        window:ClearAllPoints()
        window:SetPoint(point[1], UIParent, point[3], point[4], point[5])
    end
    if current then Select(current) end
    if wasShown then
        window:Show()
        TW:RefreshConfig()
    end
end)
