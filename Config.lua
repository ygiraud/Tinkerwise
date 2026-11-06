-- Tinkerwise configuration window, in the same style as the check-up: warm brown dialog,
-- quest-title font, gold accents. Module list on the left (grouped by section, with an
-- on/off pip), selected module on the right with its options grouped into cards.
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

local _, ns = ...
local L = ns.L
local TW = ns.TW

local WIDTH, HEIGHT = 880, 640
local MIN_WIDTH, MIN_HEIGHT = 760, 480
local LIST_W = 250
local PANEL_MARGINS = LIST_W + 34 + 22 + 30 -- window width minus the width of the option cards
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD = { 1, 0.82, 0 }
local PARCHMENT = { 0.9, 0.84, 0.72 }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local window, selected, footer
local rows, panels = {}, {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local Spaced = ns.Spaced

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
        pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(1, 0.82, 0, 0.7), CreateColor(1, 0.82, 0, 0))
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
                TW:SetOption(mod, opt.key, v[1])
                UIDropDownMenu_SetText(dd, v[2])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    function w:Refresh() UIDropDownMenu_SetText(dd, LabelOf(mod.db[opt.key])) end
    function w:MinWidth() return math.max(label:GetStringWidth(), 236) end
    return w
end

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
    outer:SetPoint("TOPLEFT", window, "TOPLEFT", LIST_W + 34, -92)
    outer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 52)
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
    section:SetText(Spaced((mod.section or L["Misc"]):upper()))
    section:SetTextColor(0.8, 0.7, 0.5)

    local title = outer:CreateFontString(nil, "OVERLAY")
    title:SetFont(TITLE_FONT, 24, "")
    title:SetTextColor(1, 0.9, 0.7)
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
        card:SetBackdropBorderColor(0.6, 0.5, 0.35, 0.9)
        local head = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", 14, -10)
        head:SetText(Spaced(label:upper()))
        local line = GoldRule(card)
        line:SetPoint("LEFT", head, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    end

    for _, opt in ipairs(mod.options or {}) do
        if opt.type == "header" then
            OpenCard(opt.label)
        else
            if not card then OpenCard(L["Settings"]) end
            local w
            if opt.type == "toggle" then
                w = CreateCheck(card, opt.label)
                w:SetScript("OnClick", function(self)
                    PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                    TW:SetOption(mod, opt.key, self:GetChecked() and true or false)
                end)
                function w:Refresh() self:SetChecked(mod.db[opt.key]) end
                AddItem(w, 28, -4)
            elseif opt.type == "slider" then
                w = CreateSlider(card, opt)
                AddItem(w, 54)
            elseif opt.type == "color" then
                w = CreateColorOption(card, opt, mod)
                AddItem(w, 30)
            elseif opt.type == "input" then
                w = CreateInput(card, opt, mod)
                AddItem(w, 50)
            elseif opt.type == "select" then
                w = CreateSelect(card, opt, mod)
                AddItem(w, 56)
            elseif opt.type == "execute" then
                w = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
                w:SetText(opt.label)
                w:SetSize(w:GetFontString():GetStringWidth() + 30, 22)
                w:SetScript("OnClick", function() opt.func(mod) end)
                function w:Refresh() self:SetEnabled(mod.active and true or false) end -- actions need an active module
                AddItem(w, 28, 0, true)
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
-- Window
---------------------------------------------------------------------------

-- Panels slide in from the right when switching modules.
local slide = { t = 1 }
local function Select(mod)
    selected = mod
    local existing = panels[mod.key]
    if existing and existing.signature ~= ChecklistSignature(mod) then
        existing:Hide()
        panels[mod.key] = nil
    end
    if not panels[mod.key] then panels[mod.key] = BuildPanel(mod) end
    for key, panel in pairs(panels) do panel:SetShown(key == mod.key) end
    slide.panel, slide.t = panels[mod.key], 0
    PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    TW:RefreshConfig()
end

local function BuildRow(mod, y, parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(LIST_W - 30, 30)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    row.mod = mod

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
    row.icon:SetTexture(mod.icon or DEFAULT_ICON)
    RoundMask(row.icon, row)
    row.ring = row:CreateTexture(nil, "BORDER") -- thin gold circle around the round icon
    row.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    row.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
    row.ring:SetSize(26, 26)
    row.ring:SetPoint("CENTER", row.icon, "CENTER")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -24, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetText(mod.title or mod.key)

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

    row:SetScript("OnClick", function() Select(mod) end)
    rows[#rows + 1] = row
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
    window:SetBackdropColor(0.45, 0.32, 0.2, 1)
    TW:AddSolidBackground(window, 0.14, 0.1, 0.06)
    window:SetToplevel(true) -- comes in front as a whole when shown or clicked
    CreateFrame("Button", nil, window, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)
    window:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
    window:SetScript("OnHide", function(self)
        if self.ready then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
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
    title:SetTextColor(1, 0.9, 0.7)
    title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 16, 4)
    title:SetText("Tinkerwise")
    local tagline = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -2)
    tagline:SetTextColor(0.8, 0.7, 0.5)
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("Tinkerwise", "Version") or ""
    tagline:SetText(Spaced(L["PERSONAL TOOLBOX"]) .. "   |cff998866v" .. version .. "|r")

    local headRule = GoldRule(window)
    headRule:SetPoint("TOPLEFT", 22, -80)
    headRule:SetPoint("RIGHT", window, "RIGHT", -22, 0)

    -- Module list in a dark inset
    local inset = CreateFrame("Frame", nil, window, "BackdropTemplate")
    inset:SetPoint("TOPLEFT", 16, -88)
    inset:SetPoint("BOTTOMLEFT", 16, 46)
    inset:SetWidth(LIST_W + 6)
    inset:SetBackdrop(CARD_BACKDROP)
    inset:SetBackdropColor(0.04, 0.03, 0.02, 0.8)
    inset:SetBackdropBorderColor(0.6, 0.5, 0.35, 0.9)

    local sections, bySection = {}, {}
    for _, mod in ipairs(TW.order) do
        local section = mod.section or L["Misc"]
        if not bySection[section] then
            bySection[section] = {}
            sections[#sections + 1] = section
        end
        table.insert(bySection[section], mod)
    end

    -- The list scrolls when there are more modules than fit.
    local listScroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 6, -6)
    listScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local list = CreateFrame("Frame", nil, listScroll)
    list:SetWidth(LIST_W - 24)
    listScroll:SetScrollChild(list)

    local y = -4
    for _, section in ipairs(sections) do
        local head = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y - 4)
        head:SetText(Spaced(section:upper()))
        local line = GoldRule(list, "OVERLAY")
        line:SetPoint("LEFT", head, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", list, "RIGHT", -4, 0)
        y = y - 24
        for _, mod in ipairs(bySection[section]) do
            BuildRow(mod, y, list)
            y = y - 34
        end
        y = y - 10
    end
    list:SetHeight(-y + 4)

    -- Footer: active modules count and close button
    footer = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("BOTTOMLEFT", 26, 22)
    footer:SetTextColor(0.8, 0.7, 0.5)
    local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", -22, 16)
    close:SetText(L["Close"])
    close:SetScript("OnClick", function() window:Hide() end)
    local edit = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    edit:SetSize(160, 22)
    edit:SetPoint("RIGHT", close, "LEFT", -6, 0)
    edit:SetText(L["Move windows"])
    edit:SetScript("OnClick", function() TW:SetEditMode(true) end)

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
        for _, panel in pairs(panels) do panel:ApplyWidth() end
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
        slide.panel:ClearAllPoints()
        slide.panel:SetPoint("TOPLEFT", window, "TOPLEFT", LIST_W + 34 + (1 - p) * 16, -92)
        slide.panel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22 + (1 - p) * 16, 52)
    end)

    if TW.order[1] then Select(TW.order[1]) end
    window:Hide() -- ToggleConfig shows it
    window.ready = true
end

function TW:RefreshConfig()
    if not window then return end
    local active = 0
    for _, row in ipairs(rows) do
        local on, isSel = row.mod.active, row.mod == selected
        if on then active = active + 1 end
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
        if on then
            row.pip.tex:SetVertexColor(0.36, 0.62, 0.3)
            row.pip.glow:SetVertexColor(0.36, 0.62, 0.3, 0.15)
            row.pip.glow:Show()
        else
            row.pip.tex:SetVertexColor(0.35, 0.3, 0.25)
            row.pip.glow:Hide()
        end
    end
    footer:SetText(Spaced(format(L["%d / %d ACTIVE MODULES"], active, #rows)))

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
