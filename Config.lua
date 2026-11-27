-- Tinkerwise configuration window: a dark "night" or a light "grimoire" style (Appearance module),
-- rounded panels drawn with the textures of Media. On the left, the pages by section with a dot that
-- turns each module on or off, and a search box; on the right, a welcome page of tiles or the page
-- chosen, its options in cards of rows (label on the left, control on the right); at the bottom, the
-- style, the size of the window and a button to reload the interface.
--
-- Option entries declared by modules:
--   { type = "toggle",  key, label }
--   { type = "slider",  key, label, min, max, step }
--     (locked(): true while the slider cannot be moved)
--   { type = "color",   key, label }    db[key] holds { r, g, b }; opens the game's color wheel
--   { type = "input",   key, label }
--   { type = "select",  key, label, values = { { value, label }, ... } }
--   { type = "execute", label, func }   consecutive buttons share a line
--   { type = "header",  label }         starts a new card
--   { type = "checklist", key, items }  items() returns names; db[key] holds the unticked ones
-- With editMode = "only", an option shows in the window of the game's Edit Mode (EditMode.lua) and not
-- here; with editMode = "never", the other way round.
-- A header with page = { key, title, icon, desc } starts a page of its own in the list: it and the
-- options after it, to the end of the module or the next such header. The module stays one: its
-- switch is the same on all its pages.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local MEDIA = "Interface\\AddOns\\Tinkerwise\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local WIDTH, HEIGHT = 1000, 680
local MIN_WIDTH, MIN_HEIGHT = 860, 520
local SIDE_W = 236
local BODY_LEFT = SIDE_W + 34 -- from the left of the window
local FOOTER_H = 46
local ROW_H = 28

---------------------------------------------------------------------------
-- The pages, by section, in the order of the list. A page is a module, or a part of one (see page =
-- above). A module missing here goes at the end of the last section.
---------------------------------------------------------------------------

local LAYOUT = {
    { L["Interface"], { "PlayerFrames", "Nameplates", "SquareMinimap", "Chat", "MenuBars", "MenuBars.errors", "DarkTheme" } },
    { L["Character"], { "Bags", "Journal", "StatDelta", "ClassBar" } },
    { L["Adventure"], { "Checkup", "Courtesy.reminders", "PotionReminder" } },
    { L["Items"], { "AutoVendor", "ItemCompare", "ItemCompare.wowhead", "SoulShards" } },
    { L["Group"], { "Courtesy", "GroupComfort", "TradeSupplies" } },
    { L["Ambiance"], { "Immersion", "Moments", "AwayModes" } },
    { L["System"], { "Appearance", "Profiles", "CharDefaults", "MinimapButton" } },
}

-- One line on the tiles of the welcome page.
local SUMMARY = {
    PlayerFrames = L["Class colors, textures and icons on the unit frames."],
    Nameplates = L["Size, colors and look of the nameplates."],
    SquareMinimap = L["A square minimap, its icons lined up or in a drawer."],
    Chat = L["Easier typing, readable lines, copy and tabs by theme."],
    MenuBars = L["Micro menu, bags bar and quest tracker on mouseover."],
    ["MenuBars.errors"] = L["Hides the red error messages and their voice."],
    DarkTheme = L["Darkens the game's frames, bars and windows."],
    Bags = L["Level, gold and bags of all your characters."],
    Journal = L["Zones, levels, deaths and bosses, day by day."],
    StatDelta = L["Stat gains and losses as your gear changes."],
    ClassBar = L["The utility spells of your class on one bar."],
    Checkup = L["Checks you are ready before heading out."],
    ["Courtesy.reminders"] = L["Weapon stone, buff food, pet or demon."],
    PotionReminder = L["Your best potion when it is not on your bars."],
    AutoVendor = L["Sells junk and repairs at merchants."],
    ItemCompare = L["What you gain or lose, in item tooltips."],
    ["ItemCompare.wowhead"] = L["Ctrl + C gives the Wowhead address of a tooltip."],
    SoulShards = L["Keeps only the soul shards you want."],
    Courtesy = L["Buff yourself and your group, thank who buffs you."],
    GroupComfort = L["Accepts invitations, resurrections and summons."],
    TradeSupplies = L["Puts conjured food or a healthstone in trades."],
    Immersion = L["Black bars and a bare screen when the interface hides."],
    Moments = L["A short scene when you die or gain a level."],
    AwayModes = L["A slow camera when you are away or in flight."],
    Appearance = L["Style and colors of the Tinkerwise windows."],
    Profiles = L["Share or copy the settings between characters."],
    CharDefaults = L["Auto loot, and new characters set up."],
    MinimapButton = L["The Tinkerwise button by the minimap."],
}

---------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------

local function Mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
local function Alpha(c, a) return { c[1], c[2], c[3], a } end

local NIGHT_GOLD = { 0.86, 0.68, 0.32 }

-- The night style, around an accent: the gold, or the class color (Appearance).
local function Night(accent)
    return {
        dark = true,
        win = { 0.055, 0.065, 0.1, 0.97 }, line = Alpha(accent, 0.6), innerLine = Alpha(accent, 0.16),
        side = { 0, 0, 0, 0.3 }, sideText = { 0.88, 0.85, 0.78 }, sideMuted = { 0.5, 0.48, 0.44 },
        sideSel = { 1, 1, 1, 0.07 }, sideSelText = Mix(accent, { 1, 1, 1 }, 0.45), sideBar = accent,
        sideCtrl = { 0.02, 0.025, 0.045, 0.9 }, logo = Mix(accent, { 1, 1, 1 }, 0.3),
        sect = Alpha(accent, 0.95), title = Mix(accent, { 1, 0.97, 0.9 }, 0.35),
        text = { 0.9, 0.87, 0.8 }, muted = { 0.56, 0.54, 0.5 },
        card = { 0.085, 0.1, 0.15, 0.9 }, cardLine = Alpha(accent, 0.22),
        ctrl = { 0.03, 0.04, 0.07, 1 }, ctrlLine = Alpha(accent, 0.38),
        on = accent, off = { 0.24, 0.22, 0.2 }, knob = { 0.96, 0.94, 0.9 },
        sel = accent, selText = { 0.08, 0.06, 0.03 }, primary = accent, primaryText = { 0.08, 0.06, 0.03 },
        hover = { 1, 0.92, 0.7, 0.06 }, found = Mix(accent, { 1, 1, 1 }, 0.25),
        ok = { 0.42, 0.82, 0.42 }, dotOff = { 0.36, 0.34, 0.31 },
    }
end

-- The grimoire style: parchment pages, a leather spine, dark red ink.
local GRIMOIRE = {
    win = { 0.92, 0.86, 0.73, 0.98 }, line = { 0.42, 0.29, 0.14, 1 }, innerLine = { 0.42, 0.29, 0.14, 0.25 },
    side = { 0.2, 0.13, 0.07, 0.97 }, sideText = { 0.9, 0.83, 0.68 }, sideMuted = { 0.62, 0.52, 0.38 },
    sideSel = { 0.92, 0.86, 0.73, 0.95 }, sideSelText = { 0.36, 0.12, 0.06 }, sideBar = { 0.85, 0.66, 0.38 },
    sideCtrl = { 0.11, 0.07, 0.035, 0.95 }, logo = { 0.95, 0.82, 0.5 },
    sect = { 0.85, 0.66, 0.38, 1 }, title = { 0.42, 0.12, 0.07 },
    text = { 0.24, 0.15, 0.08 }, muted = { 0.47, 0.37, 0.26 },
    card = { 1, 0.98, 0.93, 0.45 }, cardLine = { 0.7, 0.56, 0.36, 0.9 },
    ctrl = { 0.87, 0.79, 0.63, 1 }, ctrlLine = { 0.6, 0.46, 0.28, 1 },
    on = { 0.55, 0.27, 0.09 }, off = { 0.72, 0.64, 0.52 }, knob = { 1, 0.98, 0.94 },
    sel = { 0.42, 0.12, 0.07 }, selText = { 0.97, 0.91, 0.77 }, primary = { 0.42, 0.12, 0.07 }, primaryText = { 0.97, 0.91, 0.77 },
    hover = { 0.4, 0.2, 0.05, 0.08 }, found = { 0.62, 0.16, 0.06 },
    ok = { 0.25, 0.55, 0.2 }, dotOff = { 0.62, 0.55, 0.45 },
}

local P -- the palette in use

local function Appearance()
    local mod = TW.modules.Appearance
    return mod and mod.db or {}
end

local function CurrentPalette()
    local look = Appearance()
    if look.style == "grimoire" then return GRIMOIRE end
    return Night(look.classColors and TW.theme.accent or NIGHT_GOLD)
end

local function Color(texture, c, a)
    texture:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function TextColor(fs, c, a)
    fs:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local Spaced = ns.Spaced

local function Font(parent, size, color, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(font or BODY_FONT, size, "")
    fs:SetShadowOffset(0, 0)
    if color then TextColor(fs, color) end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function TextWidth(fs)
    return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

-- string.upper leaves accented letters as they are: "é" must give "É".
local ACCENTED_SMALL = {
    ["à"] = "À", ["â"] = "Â", ["ç"] = "Ç", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
    ["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü",
}
local function Upper(s)
    return (s:upper():gsub("\195[\160-\191]", ACCENTED_SMALL))
end

local function Slice(t, margin)
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(margin, margin, margin, margin)
        if t.SetTextureSliceMode then t:SetTextureSliceMode(0) end
    end
end

-- A rounded box (fill or 1 pixel line) over the whole of a frame, or of the given points.
local function Box(parent, kind, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    t:SetTexture(MEDIA .. (kind == "line" and "round_line" or kind == "small" and "round_small" or "round_fill"))
    Slice(t, kind == "small" and 8 or 16)
    t:SetAllPoints()
    if color then Color(t, color) end
    return t
end

-- A capsule of the given height: two half discs and a middle.
local function Pill(parent, height, layer, sublevel)
    local p = {}
    p.l = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    p.l:SetTexture(MEDIA .. "disc")
    p.l:SetTexCoord(0, 0.5, 0, 1)
    p.r = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    p.r:SetTexture(MEDIA .. "disc")
    p.r:SetTexCoord(0.5, 1, 0, 1)
    p.m = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    p.m:SetTexture(WHITE)
    function p:Place(frame, inset)
        inset = inset or 0
        local h = height - 2 * inset
        self.l:SetSize(h / 2, h)
        self.r:SetSize(h / 2, h)
        self.l:SetPoint("LEFT", frame, "LEFT", inset, 0)
        self.r:SetPoint("RIGHT", frame, "RIGHT", -inset, 0)
        self.m:SetPoint("TOPLEFT", self.l, "TOPRIGHT")
        self.m:SetPoint("BOTTOMRIGHT", self.r, "BOTTOMLEFT")
        return self
    end
    function p:SetColor(c, a)
        for _, t in ipairs({ self.l, self.m, self.r }) do Color(t, c, a) end
    end
    function p:SetShown(shown)
        for _, t in ipairs({ self.l, self.m, self.r }) do t:SetShown(shown) end
    end
    return p
end

-- A capsule with a 1 pixel edge.
local function FramedPill(frame, height, fill, edge, layer)
    local outer = Pill(frame, height, layer or "BACKGROUND", 1):Place(frame)
    local inner = Pill(frame, height, layer or "BACKGROUND", 2):Place(frame, 1)
    outer:SetColor(edge)
    inner:SetColor(fill)
    return inner, outer
end

local function Disc(parent, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(MEDIA .. "disc")
    t:SetSize(size, size)
    if color then Color(t, color) end
    return t
end

local function RoundIcon(parent, size, icon, ringColor)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexture(icon or DEFAULT_ICON)
    if parent.CreateMaskTexture then
        local mask = parent:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(t)
        t:AddMaskTexture(mask)
    end
    local ring = parent:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(MEDIA .. "ring")
    ring:SetSize(size + 4, size + 4)
    ring:SetPoint("CENTER", t)
    Color(ring, ringColor or P.line)
    t.ring = ring
    return t
end

local function Rule(parent, color, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetHeight(1)
    if CreateColor then
        t:SetGradient("HORIZONTAL", CreateColor(color[1], color[2], color[3], alpha), CreateColor(color[1], color[2], color[3], 0))
    else
        Color(t, color, alpha)
    end
    return t
end

-- Motion over a control also counts as over its row.
local function PassMotion(frame)
    if frame.SetPropagateMouseMotion then frame:SetPropagateMouseMotion(true) end
end

---------------------------------------------------------------------------
-- Widgets: one row each, the label on the left and the control on the right. They take a palette, so
-- the windows of the game's Edit Mode (always dark) can use them too.
---------------------------------------------------------------------------

local function NewRow(parent, label, pal, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(320, height or ROW_H)
    row.pal = pal
    row.hover = Box(row, "small", pal.hover, "BACKGROUND")
    row.hover:Hide()
    row.label = Font(row, 12, pal.text)
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetText(label or "")
    row.labelText = label or ""
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if self.tooltip then GameTooltip:Hide() end
    end)
    row.controlW = 0
    function row:MinWidth() return TextWidth(self.label) + self.controlW + 30 end
    function row:SetLayoutWidth(width)
        self:SetWidth(width)
        self.label:SetWidth(math.max(width - self.controlW - 28, 40))
        if self.OnWidth then self:OnWidth(width) end
    end
    -- Search: the rows whose label matches stand out.
    function row:SetFound(found)
        TextColor(self.label, found and pal.found or pal.text)
    end
    return row
end

local function Sound(on)
    PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

-- A switch: a capsule track whose knob slides to the right when on.
local function NewSwitch(parent, pal, w, h)
    w, h = w or 34, h or 18
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(w, h)
    s.track = Pill(s, h, "ARTWORK", 1):Place(s)
    s.knob = Disc(s, h - 4, pal.knob, "ARTWORK")
    s.knob:SetDrawLayer("ARTWORK", 3)
    s.pos = 0
    local function Draw(self)
        self.knob:ClearAllPoints()
        self.knob:SetPoint("LEFT", 2 + (w - h) * self.pos, 0)
        local c = Mix(pal.off, pal.on, self.pos)
        self.track:SetColor(c)
    end
    function s:SetOn(on, instant)
        self.goal = on and 1 or 0
        if instant then
            self.pos = self.goal
            Draw(self)
        end
    end
    s:SetScript("OnUpdate", function(self, elapsed)
        if not self.goal or self.pos == self.goal then return end
        local step = elapsed / 0.12
        self.pos = self.goal > self.pos and math.min(self.goal, self.pos + step) or math.max(self.goal, self.pos - step)
        Draw(self)
    end)
    Draw(s)
    return s
end

local function NewToggleRow(parent, label, pal, get, set)
    local row = NewRow(parent, label, pal)
    row.switch = NewSwitch(row, pal)
    row.switch:SetPoint("RIGHT", -8, 0)
    row.controlW = 34
    row:SetScript("OnClick", function()
        local on = not get()
        Sound(on)
        set(on)
        row.switch:SetOn(on)
    end)
    function row:Refresh() self.switch:SetOn(get() and true or false, not self:IsVisible()) end
    return row
end

-- Numbers as the step shows them: 5, 0.5, 0.25.
local function FormatValue(v, step)
    if step >= 1 then return tostring(math.floor(v + 0.5)) end
    local text = format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    return text
end

local function NewSliderRow(parent, opt, mod, pal)
    local row = NewRow(parent, opt.label, pal)
    row.controlW = 190
    local value = Font(row, 12, pal.text)
    value:SetPoint("RIGHT", -8, 0)
    value:SetWidth(42)
    value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(130, 16)
    s:SetPoint("RIGHT", value, "LEFT", -10, 0)
    s:SetMinMaxValues(opt.min, opt.max)
    s:SetValueStep(opt.step)
    s:SetObeyStepOnDrag(true)
    s:SetHitRectInsets(-4, -4, -6, -6)
    PassMotion(s)
    local track = Pill(s, 6, "BACKGROUND", 1):Place(s)
    track:SetColor(pal.dark and pal.ctrl or pal.off)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(MEDIA .. "disc")
    thumb:SetSize(14, 14)
    Color(thumb, pal.knob)
    s:SetThumbTexture(thumb)
    local ring = Disc(s, 18, pal.on, "ARTWORK")
    ring:SetPoint("CENTER", thumb)
    local fill = s:CreateTexture(nil, "BORDER")
    fill:SetTexture(WHITE)
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track.l, "LEFT", 1, 0)
    fill:SetPoint("RIGHT", thumb, "CENTER")
    Color(fill, pal.on)

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / opt.step + 0.5) * opt.step
        value:SetText(FormatValue(v, opt.step))
        if not row.refreshing then TW:SetOption(row.mod or mod, opt.key, v) end
    end)

    function row:Refresh()
        local m = self.mod or mod
        self.refreshing = true
        s:SetValue(m.db[opt.key])
        value:SetText(FormatValue(m.db[opt.key], opt.step))
        self.refreshing = false
        if opt.locked then -- set by another option
            local locked = opt.locked() and true or false
            s:SetEnabled(not locked)
            self:SetAlpha(locked and 0.45 or 1)
        end
    end
    function row:OnWidth(width)
        -- The track gives way to a long label.
        local free = width - TextWidth(self.label) - 90
        s:SetWidth(math.max(70, math.min(150, free)))
        self.label:SetWidth(width - s:GetWidth() - 80)
    end
    return row
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

local function NewColorRow(parent, opt, mod, pal)
    local row = NewRow(parent, opt.label, pal)
    row.controlW = 40
    local swatch = CreateFrame("Frame", nil, row)
    swatch:SetSize(40, 20)
    swatch:SetPoint("RIGHT", -8, 0)
    local inner = FramedPill(swatch, 20, { 1, 1, 1 }, pal.ctrlLine, "ARTWORK")
    function row:Refresh()
        local c = (self.mod or mod).db[opt.key]
        inner:SetColor({ c.r, c.g, c.b })
    end
    row:SetScript("OnClick", function(self)
        local m = self.mod or mod
        OpenColorPicker(m.db[opt.key], function(r, g, b)
            TW:SetOption(m, opt.key, { r = r, g = g, b = b })
            self:Refresh()
        end)
    end)
    return row
end

local function NewInputRow(parent, opt, mod, pal)
    local row = NewRow(parent, opt.label, pal)
    row.controlW = 180
    local holder = CreateFrame("Frame", nil, row)
    holder:SetSize(180, 22)
    holder:SetPoint("RIGHT", -8, 0)
    FramedPill(holder, 22, pal.ctrl, pal.ctrlLine)
    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", 10, 0)
    box:SetPoint("BOTTOMRIGHT", -10, 0)
    box:SetFont(BODY_FONT, 12, "")
    box:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
    box:SetAutoFocus(false)
    PassMotion(box)
    local function Mod() return row.mod or mod end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    if opt.live then -- a button reads it while it is still being typed
        box:SetScript("OnTextChanged", function(self, byUser)
            if byUser then Mod().db[opt.key] = self:GetText() end
        end)
    end
    box:SetScript("OnEditFocusLost", function(self)
        if Mod().db[opt.key] ~= self:GetText() or opt.live then TW:SetOption(Mod(), opt.key, self:GetText()) end
    end)
    box:SetScript("OnEscapePressed", function(self) row:Refresh(); self:ClearFocus() end)
    row:SetScript("OnClick", function() box:SetFocus() end)
    function row:Refresh() box:SetText(Mod().db[opt.key] or "") end
    return row
end

local function LabelOf(values, value)
    for _, v in ipairs(values) do
        if v[1] == value then return v[2] end
    end
    return tostring(value)
end

-- A choice: a segmented capsule for up to three short ones, else "<  value  >".
local function NewSelectRow(parent, opt, mod, pal)
    local row = NewRow(parent, opt.label, pal)
    local function Mod() return row.mod or mod end
    local function Choose(value)
        Sound(true)
        TW:SetOption(Mod(), opt.key, value)
        row:Refresh()
    end

    local probe = Font(row, 11)
    local segmentW, total = 0, 0
    for _, v in ipairs(opt.values) do
        probe:SetText(v[2])
        segmentW = math.max(segmentW, probe:GetStringWidth() + 20)
    end
    probe:Hide()
    total = segmentW * #opt.values

    if #opt.values <= 3 and total <= 240 then
        segmentW = math.max(segmentW, 56)
        local bar = CreateFrame("Frame", nil, row)
        bar:SetSize(segmentW * #opt.values + 4, 22)
        bar:SetPoint("RIGHT", -8, 0)
        FramedPill(bar, 22, pal.ctrl, pal.ctrlLine)
        row.controlW = bar:GetWidth()
        local segments = {}
        for i, v in ipairs(opt.values) do
            local b = CreateFrame("Button", nil, bar)
            b:SetSize(segmentW, 18)
            b:SetPoint("LEFT", 2 + (i - 1) * segmentW, 0)
            b.fill = Pill(b, 18, "ARTWORK", 1):Place(b)
            b.fill:SetColor(pal.sel)
            b.text = Font(b, 11, pal.text)
            b.text:SetPoint("CENTER")
            b.text:SetJustifyH("CENTER")
            b.text:SetText(v[2])
            b:SetScript("OnClick", function() Choose(v[1]) end)
            PassMotion(b)
            segments[i] = b
        end
        function row:Refresh()
            local current = Mod().db[opt.key]
            for i, b in ipairs(segments) do
                local on = opt.values[i][1] == current
                b.fill:SetShown(on)
                TextColor(b.text, on and pal.selText or pal.text)
            end
        end
        row:SetScript("OnClick", nil)
        return row
    end

    local width = math.min(math.max(segmentW + 44, 130), 230)
    local bar = CreateFrame("Frame", nil, row)
    bar:SetSize(width, 22)
    bar:SetPoint("RIGHT", -8, 0)
    FramedPill(bar, 22, pal.ctrl, pal.ctrlLine)
    row.controlW = width
    local text = Font(bar, 11, pal.text)
    text:SetPoint("LEFT", 22, 0)
    text:SetPoint("RIGHT", -22, 0)
    text:SetJustifyH("CENTER")
    local function Step(delta)
        local values, current, at = opt.values, Mod().db[opt.key], 1
        if #values == 0 then return end
        for i, v in ipairs(values) do
            if v[1] == current then at = i end
        end
        Choose(values[(at - 1 + delta) % #values + 1][1])
    end
    for _, side in ipairs({ { "<", -1, "LEFT", 4 }, { ">", 1, "RIGHT", -4 } }) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(18, 18)
        b:SetPoint(side[3], side[4], 0)
        local glyph = Font(b, 13, pal.muted)
        glyph:SetPoint("CENTER", 0, 1)
        glyph:SetText(side[1])
        b:SetScript("OnEnter", function() TextColor(glyph, pal.on) end)
        b:SetScript("OnLeave", function() TextColor(glyph, pal.muted) end)
        b:SetScript("OnClick", function() Step(side[2]) end)
        PassMotion(b)
    end
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(_, button) Step(button == "RightButton" and -1 or 1) end)
    function row:Refresh() text:SetText(LabelOf(opt.values, Mod().db[opt.key])) end
    return row
end

-- A capsule button; primary: filled with the accent.
local function NewButton(parent, label, pal, primary, height)
    height = height or 24
    local b = CreateFrame("Button", nil, parent)
    b.text = Font(b, 12, primary and pal.primaryText or pal.text)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    local fill = FramedPill(b, height, primary and pal.primary or pal.ctrl, primary and pal.primary or pal.ctrlLine)
    local glow = Pill(b, height, "HIGHLIGHT"):Place(b)
    glow:SetColor(pal.dark and { 1, 1, 1 } or { 0.4, 0.2, 0.05 }, primary and 0.18 or 0.08)
    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetSize(self.text:GetStringWidth() + 32, height)
    end
    b:SetLabel(label)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER") end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    b.fill = fill
    return b
end

local function NewExecute(parent, opt, mod, pal)
    local b = NewButton(parent, opt.label, pal)
    local function Mod() return b.mod or mod end
    if opt.confirm then -- two clicks: the first one asks
        local asked
        local width = b:GetWidth()
        b:SetLabel(L["Click again to confirm"])
        local confirmW = b:GetWidth()
        b:SetLabel(opt.label)
        b:SetWidth(math.max(width, confirmW))
        local function Forget()
            asked = nil
            b.text:SetText(opt.label)
        end
        b:SetScript("OnClick", function()
            if asked then
                Forget()
                opt.func(Mod())
                return
            end
            local this = {}
            asked = this
            b.text:SetText(L["Click again to confirm"])
            C_Timer.After(4, function()
                if asked == this then Forget() end
            end)
        end)
        b:SetScript("OnHide", Forget)
    else
        b:SetScript("OnClick", function() opt.func(Mod()) end)
    end
    function b:Refresh() self:SetEnabled(Mod().active and true or false) end -- actions need an active module
    return b
end

-- The widget of an option, its height, its horizontal offset in a card and whether it is a button.
-- Nothing for the headers and the checklists, which hold several.
local function CreateOption(parent, opt, mod, pal)
    pal = pal or Night(NIGHT_GOLD)
    if opt.type == "toggle" then
        local row
        row = NewToggleRow(parent, opt.label, pal,
            function() return (row.mod or mod).db[opt.key] end,
            function(on) TW:SetOption(row.mod or mod, opt.key, on) end)
        return row, ROW_H + 2, 0
    elseif opt.type == "slider" then
        return NewSliderRow(parent, opt, mod, pal), ROW_H + 2, 0
    elseif opt.type == "color" then
        return NewColorRow(parent, opt, mod, pal), ROW_H + 2, 0
    elseif opt.type == "input" then
        return NewInputRow(parent, opt, mod, pal), ROW_H + 2, 0
    elseif opt.type == "select" then
        return NewSelectRow(parent, opt, mod, pal), ROW_H + 2, 0
    elseif opt.type == "execute" then
        return NewExecute(parent, opt, mod, pal), 30, 0, true
    end
end
ns.CreateOption = CreateOption -- also for the windows of EditMode.lua

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local window, selected, searchBox, list, noResult, home, bodyArea
local pages, pageByKey = {}, {}
local sideRows, sideHeads, tiles, panels = {}, {}, {}, {}
local Select

-- Lists the pages of every module, in the order of LAYOUT.
local function BuildPages()
    wipe(pages)
    wipe(pageByKey)
    local found = {}
    for _, mod in ipairs(TW.order) do
        found[mod.key] = { key = mod.key, mod = mod, title = mod.title or mod.key, icon = mod.icon, desc = mod.desc }
        for _, opt in ipairs(mod.options or {}) do
            if opt.type == "header" and opt.page then
                local key = mod.key .. "." .. opt.page.key
                found[key] = { key = key, mod = mod, sub = opt.page.key, title = opt.page.title,
                               icon = opt.page.icon or mod.icon, desc = opt.page.desc }
            end
        end
    end
    local placed = {}
    for _, section in ipairs(LAYOUT) do
        for _, key in ipairs(section[2]) do
            local page = found[key]
            if page then
                page.section = section[1]
                pages[#pages + 1] = page
                placed[key] = true
            end
        end
    end
    for key, page in pairs(found) do -- not in LAYOUT
        if not placed[key] then
            page.section = LAYOUT[#LAYOUT][1]
            pages[#pages + 1] = page
        end
    end
    for _, page in ipairs(pages) do
        pageByKey[page.key] = page
        page.summary = SUMMARY[page.key]
        if page.sub then page.parent = found[page.mod.key] end
    end
end

-- The options of a page: those of its part of the module.
local function PageOptions(page)
    local result, current = {}, nil
    for _, opt in ipairs(page.mod.options or {}) do
        if opt.type == "header" and opt.page then current = opt.page.key end
        if current == page.sub then result[#result + 1] = opt end
    end
    return result
end

-- Identifies the options of a page, to rebuild it when they change.
local function Signature(page)
    local parts = {}
    for _, opt in ipairs(PageOptions(page)) do
        parts[#parts + 1] = opt.type .. (opt.label or "")
        if opt.type == "checklist" then parts[#parts + 1] = table.concat(opt.items(), "\n") end
        if opt.type == "select" then -- the profiles come and go
            for _, v in ipairs(opt.values) do parts[#parts + 1] = tostring(v[2]) end
        end
    end
    return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Search: titles, descriptions, sections and option labels.
---------------------------------------------------------------------------

-- string.lower leaves accented capitals as they are: "É" must match "é".
local ACCENTED_CAPITALS = {
    ["À"] = "à", ["Â"] = "â", ["Ç"] = "ç", ["É"] = "é", ["È"] = "è", ["Ê"] = "ê", ["Ë"] = "ë",
    ["Î"] = "î", ["Ï"] = "ï", ["Ô"] = "ô", ["Ù"] = "ù", ["Û"] = "û", ["Ü"] = "ü",
}
local function Lower(s)
    return (s:lower():gsub("\195[\128-\159]", ACCENTED_CAPITALS))
end

local function Query()
    return searchBox and Lower(strtrim(searchBox:GetText() or "")) or ""
end

local function Matches(page, query)
    local parts = { page.title, page.desc or "", page.section, page.summary or "" }
    for _, opt in ipairs(PageOptions(page)) do
        if opt.label then parts[#parts + 1] = opt.label end
        for _, v in ipairs(type(opt.values) == "table" and opt.values or {}) do parts[#parts + 1] = tostring(v[2]) end
    end
    return Lower(table.concat(parts, "\n")):find(query, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Cards of a page
---------------------------------------------------------------------------

-- Places a card's rows on two columns and returns the card's height. A row too wide for half the card
-- takes a whole line. Buttons flow on their own lines.
local function LayoutCard(card, cardW)
    local PAD, GAP = 12, 14
    local colW = (cardW - 2 * PAD - GAP) / 2
    local cy, rowH, leftUsed, bx = -36, 0, false, nil

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
            if leftUsed or (bx and bx + w:GetWidth() > cardW - PAD) then EndRow() end
            bx = bx or PAD + 4
            Place(item, bx)
            bx = bx + w:GetWidth() + 8
        else
            if bx then EndRow() end
            local width
            if w:MinWidth() <= colW then
                width = colW
                Place(item, leftUsed and PAD + colW + GAP or PAD)
                if leftUsed then EndRow() else leftUsed = true end
            else
                if leftUsed then EndRow() end
                width = cardW - 2 * PAD
                Place(item, PAD)
                EndRow()
            end
            w:SetLayoutWidth(width)
        end
    end
    EndRow()
    return -cy + 10
end

-- A scroll frame moved by the wheel, with a thin bar on the right.
local function NewScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetWidth(3)
    Color(thumb, P.line, 0.5)
    local function Update()
        local range = scroll:GetVerticalScrollRange()
        local h = scroll:GetHeight()
        if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(math.max(0, range)) end
        thumb:SetShown(range > 1)
        if range <= 1 then return end
        local size = math.max(24, h * h / (h + range))
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -(h - size) * scroll:GetVerticalScroll() / range)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 50)))
        Update()
    end)
    scroll:SetScript("OnScrollRangeChanged", Update)
    scroll:SetScript("OnSizeChanged", Update)
    scroll.content, scroll.Update = content, Update
    return scroll
end

-- The frame of a window in this style: shadow, fill, a light from the top, a double edge.
local function Chrome(frame, shineHeight)
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(MEDIA .. "shadow")
    Slice(shadow, 30)
    shadow:SetPoint("TOPLEFT", -26, 26)
    shadow:SetPoint("BOTTOMRIGHT", 26, -30)
    shadow:SetVertexColor(0, 0, 0, 0.75)
    Box(frame, "fill", P.win, "BACKGROUND", -6)
    local shine = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    shine:SetTexture(MEDIA .. "shine")
    shine:SetPoint("TOPLEFT", 6, -6)
    shine:SetPoint("TOPRIGHT", -6, -6)
    shine:SetHeight(shineHeight or 200)
    shine:SetVertexColor(1, 1, 1, P.dark and 0.05 or 0.35)
    Box(frame, "line", P.line, "BORDER", 1)
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT", 5, -5)
    inner:SetPoint("BOTTOMRIGHT", -5, 5)
    Box(inner, "line", P.innerLine, "BORDER", 1)
end

-- For the other windows in this style (WhatsNew.lua). Palette() picks the colors in use; the
-- drawing functions then follow them.
ns.UI = {
    Palette = function() P = CurrentPalette() return P end,
    Chrome = Chrome, Box = Box, Pill = Pill, FramedPill = FramedPill, Font = Font, Disc = Disc, Rule = Rule,
    NewButton = NewButton, NewScroll = NewScroll, Upper = Upper, Color = Color, TextColor = TextColor,
    TITLE_FONT = TITLE_FONT, WHITE = WHITE,
}
ns.styleListeners = {} -- called when the style or the colors change

local function NewCard(parent, label)
    local card = CreateFrame("Frame", nil, parent)
    card.items = {}
    Box(card, "fill", P.card, "BACKGROUND", 1)
    Box(card, "line", P.cardLine, "BACKGROUND", 2)
    local head = Font(card, 10, P.title)
    head:SetPoint("TOPLEFT", 16, -14)
    head:SetText(Spaced(Upper(label or "")))
    local rule = Rule(card, P.line, 0.5)
    rule:SetPoint("LEFT", head, "RIGHT", 10, 0)
    rule:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    return card
end

local function ModuleStatus(page)
    local mod = page.mod
    local parts = { Upper(page.section) }
    if page.parent then parts[#parts + 1] = format(L["Part of %s"], page.parent.title) end
    if mod.alwaysEnabled then
        parts[#parts + 1] = L["Always on"]
    else
        parts[#parts + 1] = mod.active and L["Active"] or L["Inactive"]
    end
    return table.concat(parts, "   ·   ")
end

local function BuildPanel(page)
    local mod = page.mod
    local panel = CreateFrame("Frame", nil, bodyArea)
    panel:SetAllPoints()
    panel.signature = Signature(page)
    panel.widgets = {}

    -- Header: icon, title, status line, switch, description
    local icon = RoundIcon(panel, 46, page.icon, P.line)
    icon:SetPoint("TOPLEFT", 4, -6)
    local title = Font(panel, 24, P.title, TITLE_FONT)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, 2)
    title:SetText(page.title)
    panel.status = Font(panel, 10, P.muted)
    panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)

    if not mod.alwaysEnabled then
        local holder = CreateFrame("Button", nil, panel)
        holder:SetSize(120, 26)
        holder:SetPoint("TOPRIGHT", -4, -14)
        panel.switch = NewSwitch(holder, P, 42, 22)
        panel.switch:SetPoint("RIGHT")
        local label = Font(holder, 12, P.text)
        label:SetPoint("RIGHT", panel.switch, "LEFT", -10, 0)
        label:SetText(L["Enabled"])
        holder:SetScript("OnClick", function()
            Sound(not mod.active)
            TW:SetModuleEnabled(mod, not mod.active)
            TW:RefreshConfig()
        end)
    end

    local desc = Font(panel, 12, P.text)
    desc:SetWordWrap(true)
    desc:SetSpacing(3)
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    desc:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    desc:SetText(page.desc or "")

    local scroll = NewScroll(panel)
    scroll:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    local content = scroll.content

    local cards = {}
    function panel:ApplyWidth()
        local w = math.max(scroll:GetWidth(), 300)
        content:SetWidth(w)
        local y = 0
        for _, c in ipairs(cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, y)
            c:SetWidth(w)
            local height = LayoutCard(c, w)
            c:SetHeight(height)
            y = y - height - 12
        end
        content:SetHeight(-y + 4)
        scroll.Update()
    end
    scroll:HookScript("OnSizeChanged", function() panel:ApplyWidth() end)

    local card
    local function Add(widget, height, isButton)
        card.items[#card.items + 1] = { widget = widget, height = height, isButton = isButton }
        widget.mod = mod
        panel.widgets[#panel.widgets + 1] = widget
    end
    for _, opt in ipairs(PageOptions(page)) do
        if opt.type == "header" then
            card = NewCard(content, opt.label)
            cards[#cards + 1] = card
        elseif opt.editMode ~= "only" then
            if not card then
                card = NewCard(content, L["Settings"])
                cards[#cards + 1] = card
            end
            local w, height, _, isButton = CreateOption(card, opt, mod, P)
            if w then
                Add(w, height, isButton)
            elseif opt.type == "checklist" then
                -- one switch per item; db[key] holds the unticked names, so new items start on
                for _, name in ipairs(opt.items()) do
                    local row = NewToggleRow(card, name, P,
                        function() local off = mod.db[opt.key] return not (off and off[name]) end,
                        function(on)
                            local off = mod.db[opt.key] or {}
                            off[name] = not on or nil
                            TW:SetOption(mod, opt.key, off)
                        end)
                    Add(row, ROW_H + 2)
                end
            end
        end
    end
    if #cards == 0 then
        local none = Font(content, 12, P.muted)
        none:SetPoint("TOPLEFT", 4, -4)
        none:SetText(L["Nothing to set: it does its job by itself."])
    end
    panel:ApplyWidth()
    return panel
end

---------------------------------------------------------------------------
-- Welcome page: a tile per page, by section.
---------------------------------------------------------------------------

local function ToggleModule(mod)
    Sound(not mod.active)
    TW:SetModuleEnabled(mod, not mod.active)
    TW:RefreshConfig()
end

local function NewDot(parent, mod)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.disc = Disc(b, 8)
    b.disc:SetPoint("CENTER")
    b.glow = Disc(b, 14, nil, "BORDER")
    b.glow:SetPoint("CENTER")
    b:SetScript("OnClick", function() ToggleModule(mod) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(mod.active and L["Click to disable"] or L["Click to enable"])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    function b:Paint()
        Color(self.disc, mod.active and P.ok or P.dotOff)
        Color(self.glow, P.ok, 0.18)
        self.glow:SetShown(mod.active)
    end
    b:SetShown(not mod.alwaysEnabled)
    return b
end

local TILE_H = 66

local function BuildHome()
    home = CreateFrame("Frame", nil, bodyArea)
    home:SetAllPoints()
    local title = Font(home, 26, P.title, TITLE_FONT)
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText(L["Welcome to Tinkerwise"])
    -- The setup again, for a character already set up.
    local again = NewButton(home, L["Run the setup again"], P)
    again:SetPoint("TOPRIGHT", -4, -6)
    again:SetScript("OnClick", function()
        window:Hide()
        if ns.OpenSetup then ns.OpenSetup(1) end
    end)
    local news = NewButton(home, L["What's new"], P)
    news:SetPoint("RIGHT", again, "LEFT", -8, 0)
    news:SetScript("OnClick", function()
        if ns.ShowNews then ns.ShowNews(true) end
    end)
    local sub = Font(home, 12, P.muted)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetPoint("RIGHT", home, "RIGHT", -4, 0)
    sub:SetWordWrap(true)
    sub:SetText(L["All your tools at a glance: click one to set it up, or its dot to turn it on or off. Search names, descriptions and settings on the left."])

    local scroll = NewScroll(home)
    scroll:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    local content = scroll.content

    local items = {} -- section captions and tiles, in order
    local lastSection
    for _, page in ipairs(pages) do
        if page.section ~= lastSection then
            lastSection = page.section
            local cap = Font(content, 10, P.title)
            cap:SetText(Spaced(Upper(page.section)))
            items[#items + 1] = { caption = cap }
        end
        local t = CreateFrame("Button", nil, content)
        t:SetHeight(TILE_H)
        Box(t, "fill", P.card, "BACKGROUND", 1)
        Box(t, "line", P.cardLine, "BACKGROUND", 2)
        local hl = Box(t, "fill", P.hover, "HIGHLIGHT")
        hl:SetBlendMode("BLEND")
        t.icon = RoundIcon(t, 34, page.icon, P.line)
        t.icon:SetPoint("LEFT", 14, 0)
        t.name = Font(t, 13, P.title)
        t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 12, 2)
        t.name:SetPoint("RIGHT", t, "RIGHT", -28, 0)
        t.name:SetText(page.title)
        t.summary = Font(t, 11, P.muted)
        t.summary:SetWordWrap(true)
        t.summary:SetMaxLines(2)
        t.summary:SetSpacing(1)
        t.summary:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -4)
        t.summary:SetPoint("RIGHT", t, "RIGHT", -12, 0)
        t.summary:SetText(page.summary or "")
        t.dot = NewDot(t, page.mod)
        t.dot:SetPoint("TOPRIGHT", -6, -6)
        t.page = page
        t:SetScript("OnClick", function() Select(page) end)
        tiles[#tiles + 1] = t
        items[#items + 1] = { tile = t }
    end

    function home:ApplyWidth()
        local w = math.max(scroll:GetWidth(), 300)
        content:SetWidth(w)
        local cols = w >= 620 and 3 or 2
        local gap = 10
        local tileW = (w - gap * (cols - 1)) / cols
        local y, col = 0, 0
        for _, item in ipairs(items) do
            if item.caption then
                if col > 0 then y, col = y - TILE_H - gap, 0 end
                y = y - (y < 0 and 8 or 0)
                item.caption:ClearAllPoints()
                item.caption:SetPoint("TOPLEFT", 2, y)
                y = y - 20
            else
                item.tile:SetWidth(tileW)
                item.tile:ClearAllPoints()
                item.tile:SetPoint("TOPLEFT", col * (tileW + gap), y)
                col = col + 1
                if col == cols then y, col = y - TILE_H - gap, 0 end
            end
        end
        if col > 0 then y = y - TILE_H end
        content:SetHeight(-y + 4)
        scroll.Update()
    end
    scroll:HookScript("OnSizeChanged", function() home:ApplyWidth() end)
    home:ApplyWidth()
end

---------------------------------------------------------------------------
-- The list on the left
---------------------------------------------------------------------------

local function BuildSideRow(page, parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(SIDE_W - 20, 30)
    row.sel = Box(row, "small", P.sideSel, "BACKGROUND", 1)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture(WHITE)
    row.bar:SetSize(3, 16)
    row.bar:SetPoint("LEFT", 0, 0)
    Color(row.bar, P.sideBar)
    local hl = Box(row, "small", P.dark and { 1, 1, 1, 0.05 } or { 1, 0.95, 0.8, 0.07 }, "HIGHLIGHT")
    hl:SetBlendMode("BLEND")
    row.icon = RoundIcon(row, 20, page.icon, P.line)
    row.icon:SetPoint("LEFT", 12, 0)
    row.text = Font(row, 12, P.sideText)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -24, 0)
    row.text:SetText(page.title)
    row.dot = NewDot(row, page.mod)
    row.dot:SetPoint("RIGHT", -4, 0)
    row.page = page
    row:SetScript("OnClick", function() Select(page) end)
    sideRows[#sideRows + 1] = row
end

-- The sections and their pages, or the pages that match the search.
local function LayoutList()
    local query = Query()
    local y = -2
    local section
    local found = 0
    for _, head in ipairs(sideHeads) do head:Hide() end
    for _, row in ipairs(sideRows) do
        local show = query == "" or Matches(row.page, query)
        row:SetShown(show)
        if show then
            found = found + 1
            if query == "" and row.page.section ~= section then
                section = row.page.section
                local head = sideHeads[section]
                head:Show()
                head:ClearAllPoints()
                head:SetPoint("TOPLEFT", list, "TOPLEFT", 10, y - (y < -2 and 10 or 4))
                y = y - (y < -2 and 30 or 24)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, y)
            y = y - 31
        end
    end
    noResult:SetShown(query ~= "" and found == 0)
    list:SetHeight(-y + 6)
end

local function BuildSearch(side)
    local holder = CreateFrame("Frame", nil, side)
    holder:SetHeight(30)
    holder:SetPoint("TOPLEFT", 12, -62)
    holder:SetPoint("TOPRIGHT", -12, -62)
    FramedPill(holder, 30, P.sideCtrl, P.dark and P.ctrlLine or { 0.45, 0.32, 0.17 })
    local lens = holder:CreateTexture(nil, "OVERLAY")
    lens:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    lens:SetSize(14, 14)
    lens:SetPoint("LEFT", 12, -1)
    Color(lens, P.sideMuted)
    searchBox = CreateFrame("EditBox", nil, holder)
    searchBox:SetPoint("TOPLEFT", 32, 0)
    searchBox:SetPoint("BOTTOMRIGHT", -12, 0)
    searchBox:SetFont(BODY_FONT, 12, "")
    searchBox:SetTextColor(P.sideText[1], P.sideText[2], P.sideText[3])
    searchBox:SetAutoFocus(false)
    local hint = Font(holder, 12, P.sideMuted)
    hint:SetPoint("LEFT", 32, 0)
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
        for _, row in ipairs(sideRows) do
            if row:IsShown() then return Select(row.page) end
        end
    end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

-- Pages slide in from the right.
local slide = { t = 1 }
local function PlaceBody(frame, dx)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", bodyArea, "TOPLEFT", dx or 0, 0)
    frame:SetPoint("BOTTOMRIGHT", bodyArea, "BOTTOMRIGHT", dx or 0, 0)
end

-- page: one of pages, or nil for the welcome page.
function Select(page, silent)
    selected = page
    TinkerwiseCharDB.configPage = page and page.key or nil
    local shown
    if page then
        local existing = panels[page.key]
        if existing and existing.signature ~= Signature(page) then
            existing:Hide()
            panels[page.key] = nil
        end
        panels[page.key] = panels[page.key] or BuildPanel(page)
        shown = panels[page.key]
    else
        shown = home
    end
    home:SetShown(shown == home)
    for _, panel in pairs(panels) do panel:SetShown(panel == shown) end
    PlaceBody(shown)
    slide.frame, slide.t = shown, 0
    if not silent then PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    TW:RefreshConfig()
end

-- The size of the window, in %, kept on screen.
local function ApplyScale()
    local look = Appearance()
    local scale = (look.configScale or 100) / 100
    local fit = math.min(UIParent:GetWidth() / (window:GetWidth() + 60), UIParent:GetHeight() / (window:GetHeight() + 60))
    window:SetScale(math.min(scale, math.max(fit, 0.5)))
    if window.sizeText then window.sizeText:SetText((look.configScale or 100) .. " %") end
end

local function SetAppearance(key, value)
    local mod = TW.modules.Appearance
    if mod and mod.db then TW:SetOption(mod, key, value) end
end

local function BuildFooter()
    local footer = CreateFrame("Frame", nil, window)
    footer:SetPoint("BOTTOMLEFT", BODY_LEFT, 12)
    footer:SetPoint("BOTTOMRIGHT", -22, 12)
    footer:SetHeight(FOOTER_H - 12)
    local rule = Rule(footer, P.line, 0.35)
    rule:SetPoint("TOPLEFT", 0, 6)
    rule:SetPoint("TOPRIGHT", 0, 6)

    -- Style: two segments
    local styleLabel = Font(footer, 10, P.muted)
    styleLabel:SetPoint("LEFT", 0, 0)
    styleLabel:SetText(Spaced(Upper(L["Style"])))
    local styles = {
        options = { { "night", L["Night"] }, { "grimoire", L["Grimoire"] } },
    }
    local bar = CreateFrame("Frame", nil, footer)
    bar:SetSize(2 * 76 + 4, 24)
    bar:SetPoint("LEFT", styleLabel, "RIGHT", 10, 0)
    FramedPill(bar, 24, P.ctrl, P.ctrlLine)
    local current = Appearance().style or "night"
    for i, v in ipairs(styles.options) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(76, 20)
        b:SetPoint("LEFT", 2 + (i - 1) * 76, 0)
        local fill = Pill(b, 20, "ARTWORK", 1):Place(b)
        fill:SetColor(P.sel)
        fill:SetShown(current == v[1])
        local text = Font(b, 11, current == v[1] and P.selText or P.text)
        text:SetPoint("CENTER")
        text:SetText(v[2])
        b:SetScript("OnClick", function()
            if current ~= v[1] then
                Sound(true)
                SetAppearance("style", v[1])
            end
        end)
    end

    -- Size: - 100 % +
    local sizeLabel = Font(footer, 10, P.muted)
    sizeLabel:SetPoint("LEFT", bar, "RIGHT", 22, 0)
    sizeLabel:SetText(Spaced(Upper(L["Size"])))
    local minus = NewButton(footer, "-", P, false, 24)
    minus:SetWidth(28)
    minus:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
    window.sizeText = Font(footer, 12, P.text)
    window.sizeText:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    window.sizeText:SetWidth(44)
    window.sizeText:SetJustifyH("CENTER")
    local plus = NewButton(footer, "+", P, false, 24)
    plus:SetWidth(28)
    plus:SetPoint("LEFT", window.sizeText, "RIGHT", 6, 0)
    local function Resize(delta)
        local look = Appearance()
        look.configScale = math.max(70, math.min(130, (look.configScale or 100) + delta))
        ApplyScale()
        TW:RefreshConfig()
    end
    minus:SetScript("OnClick", function() Resize(-5) end)
    plus:SetScript("OnClick", function() Resize(5) end)

    -- Reload
    local reload = NewButton(footer, L["Reload the interface"], P, true, 26)
    reload:SetPoint("RIGHT", -6, 0)
    reload:SetScript("OnClick", ReloadUI)
    local hint = Font(footer, 11, P.muted)
    hint:SetPoint("RIGHT", reload, "LEFT", -14, 0)
    hint:SetText(L["/tw  ·  Escape to close"])
    footer:SetScript("OnSizeChanged", function(self, width)
        hint:SetShown(width > 560 + TextWidth(hint) + reload:GetWidth())
    end)
end

local function BuildWindow()
    P = CurrentPalette()
    BuildPages()
    sideRows, sideHeads, tiles, panels, selected = {}, {}, {}, {}, nil

    window = CreateFrame("Frame", "TinkerwiseConfigFrame", UIParent)
    window:Hide() -- until ToggleConfig shows it
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetToplevel(true) -- comes in front as a whole when shown or clicked
    tinsert(UISpecialFrames, "TinkerwiseConfigFrame") -- close with Escape
    window:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
    window:SetScript("OnHide", function(self)
        if self.ready then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
    end)

    -- Shadow, fill, a light from the top, a double edge.
    local shadow = window:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(MEDIA .. "shadow")
    Slice(shadow, 30)
    shadow:SetPoint("TOPLEFT", -26, 26)
    shadow:SetPoint("BOTTOMRIGHT", 26, -30)
    shadow:SetVertexColor(0, 0, 0, 0.75)
    Box(window, "fill", P.win, "BACKGROUND", -6)
    local shine = window:CreateTexture(nil, "BACKGROUND", nil, -5)
    shine:SetTexture(MEDIA .. "shine")
    shine:SetPoint("TOPLEFT", 6, -6)
    shine:SetPoint("TOPRIGHT", -6, -6)
    shine:SetHeight(220)
    shine:SetVertexColor(1, 1, 1, P.dark and 0.05 or 0.35)
    Box(window, "line", P.line, "BORDER", 1)
    local inner = CreateFrame("Frame", nil, window)
    inner:SetPoint("TOPLEFT", 5, -5)
    inner:SetPoint("BOTTOMRIGHT", -5, 5)
    Box(inner, "line", P.innerLine, "BORDER", 1)

    -- Close: a muted cross
    local close = CreateFrame("Button", nil, window)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -12, -10)
    local cross = Font(close, 20, P.muted)
    cross:SetPoint("CENTER")
    cross:SetText("×")
    close:SetScript("OnEnter", function() TextColor(cross, P.title) end)
    close:SetScript("OnLeave", function() TextColor(cross, P.muted) end)
    close:SetScript("OnClick", function() window:Hide() end)

    -- The list: logo, search, sections
    local side = CreateFrame("Frame", nil, window)
    side:SetPoint("TOPLEFT", 10, -10)
    side:SetPoint("BOTTOMLEFT", 10, 10)
    side:SetWidth(SIDE_W)
    Box(side, "fill", P.side, "BACKGROUND", 2)

    local logo = CreateFrame("Button", nil, side)
    logo:SetPoint("TOPLEFT", 14, -12)
    logo:SetSize(SIDE_W - 28, 38)
    local logoIcon = RoundIcon(logo, 30, "Interface\\Icons\\INV_Misc_Wrench_01", P.sideBar)
    logoIcon:SetPoint("LEFT", 2, 0)
    local logoText = Font(logo, 24, P.logo, TITLE_FONT)
    logoText:SetPoint("LEFT", logoIcon, "RIGHT", 10, 1)
    logoText:SetText("Tinkerwise")
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("Tinkerwise", "Version") or ""
    local versionText = Font(logo, 10, P.sideMuted)
    versionText:SetPoint("BOTTOMLEFT", logoText, "BOTTOMRIGHT", 6, 3)
    versionText:SetText("v" .. version)
    logo:SetScript("OnClick", function() Select(nil) end)
    logo:SetScript("OnEnter", function()
        GameTooltip:SetOwner(logo, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Welcome page"])
        GameTooltip:Show()
    end)
    logo:SetScript("OnLeave", GameTooltip_Hide)

    BuildSearch(side)

    local listScroll = NewScroll(side)
    listScroll:SetPoint("TOPLEFT", 6, -102)
    listScroll:SetPoint("BOTTOMRIGHT", -10, 10)
    list = listScroll.content
    list:SetWidth(SIDE_W - 16)
    noResult = Font(list, 12, P.sideMuted)
    noResult:SetPoint("TOPLEFT", 12, -8)
    noResult:SetText(L["No results"])
    for _, section in ipairs(LAYOUT) do
        local head = Font(list, 10, P.sect)
        head:SetText(Spaced(Upper(section[1])))
        sideHeads[section[1]] = head
        sideHeads[#sideHeads + 1] = head
    end
    for _, page in ipairs(pages) do BuildSideRow(page, list) end
    LayoutList()

    -- The page
    bodyArea = CreateFrame("Frame", nil, window)
    bodyArea:SetPoint("TOPLEFT", BODY_LEFT, -24)
    bodyArea:SetPoint("BOTTOMRIGHT", -22, FOOTER_H + 12)
    BuildHome()
    BuildFooter()

    -- Resize grip, bottom right. The size is saved per character.
    local saved = TinkerwiseCharDB.configSize
    if saved then window:SetSize(math.max(saved.w, MIN_WIDTH), math.max(saved.h, MIN_HEIGHT)) end
    window:SetResizable(true)
    if window.SetResizeBounds then
        window:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    elseif window.SetMinResize then
        window:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -6, 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetAlpha(0.6)
    grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        TinkerwiseCharDB.configSize = { w = window:GetWidth(), h = window:GetHeight() }
        ApplyScale()
    end)

    window:SetScript("OnUpdate", function(_, elapsed)
        if slide.t >= 1 or not slide.frame then return end
        slide.t = math.min(1, slide.t + elapsed / 0.2)
        local p = 1 - (1 - slide.t) ^ 3
        slide.frame:SetAlpha(p)
        PlaceBody(slide.frame, (1 - p) * 16)
    end)

    ApplyScale()
    Select(pageByKey[TinkerwiseCharDB.configPage or ""], true)
    window.ready = true
end

local rebuilding -- a page is being built again by RefreshConfig

function TW:RefreshConfig()
    if ns.RefreshSetup then ns.RefreshSetup() end
    if not window then return end
    local query = Query()
    for _, row in ipairs(sideRows) do
        local isSel = row.page == selected
        local on = row.page.mod.active
        row.sel:SetShown(isSel)
        row.bar:SetShown(isSel)
        TextColor(row.text, isSel and P.sideSelText or on and P.sideText or P.sideMuted)
        row.icon:SetDesaturated(not on)
        row.icon:SetAlpha(on and 1 or 0.6)
        row.dot:Paint()
    end
    for _, t in ipairs(tiles) do
        local on = t.page.mod.active
        t.icon:SetDesaturated(not on)
        t.icon:SetAlpha(on and 1 or 0.55)
        TextColor(t.name, on and P.title or P.muted)
        t.dot:Paint()
    end
    local panel = selected and panels[selected.key]
    if panel and panel.signature ~= Signature(selected) and not rebuilding then -- built again
        rebuilding = true
        Select(selected, true)
        rebuilding = false
        return
    end
    if panel then
        panel.status:SetText(ModuleStatus(selected))
        if panel.switch then panel.switch:SetOn(selected.mod.active, not panel:IsVisible()) end
        for _, w in ipairs(panel.widgets) do
            if w.Refresh then w:Refresh() end
            if w.SetFound then
                w:SetFound(query ~= "" and w.labelText and Lower(w.labelText):find(query, 1, true) ~= nil)
            end
        end
    end
end

function TW:ToggleConfig()
    if not window then BuildWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        if selected and panels[selected.key].signature ~= Signature(selected) then Select(selected, true) end
        self:RefreshConfig()
    end
end


---------------------------------------------------------------------------
-- Setup: opens by itself once for the account, and for each new character; /tw setup opens it again.
-- Quick by default: the welcome (style), then what is for this character, the tools staying as they
-- are. "Choose tool by tool" adds a step per section. A new character of an account already set up
-- only gets the last step. Each choice applies at once, so leaving half way keeps what was chosen.
---------------------------------------------------------------------------

local SETUP_W = 560

-- A few settings worth asking about, beside the switches of the modules, by section.
local SETUP_OPTIONS = {
    [L["Interface"]] = { { "MenuBars", "hideErrors" } },
    [L["Adventure"]] = { { "Courtesy", "weapon" }, { "Courtesy", "foodBuff" }, { "Courtesy", "pet" } },
    [L["Items"]] = { { "ItemCompare", "wowhead" } },
    [L["System"]] = { { "CharDefaults", "autoLoot" }, { "CharDefaults", "fastLoot" } },
}
-- Asked at the end, whatever the way: what is for this character.
local CHARACTER_OPTIONS = { { "CharDefaults", "thisLayout" }, { "CharDefaults", "applyBars" } }

local setup -- the window
local setupStep = 1
local setupMode = "quick" -- quick, full (tool by tool) or character (only the last step)

local function FindOption(mod, key)
    for _, opt in ipairs(mod.options or {}) do
        if opt.key == key and opt.type ~= "header" then return opt end
    end
end

local function OptionPairs(list)
    local pairsFound = {}
    for _, pair in ipairs(list) do
        local mod = TW.modules[pair[1]]
        local opt = mod and FindOption(mod, pair[2])
        if opt then pairsFound[#pairsFound + 1] = { mod = mod, opt = opt } end
    end
    return pairsFound
end

-- The steps of a way: the welcome, one per section when tool by tool, this character.
local function SetupSteps(mode)
    local steps = {}
    if mode ~= "character" then
        steps[1] = { welcome = true, title = L["Welcome to Tinkerwise"],
                     text = L["The quick setup keeps the tools as they are (all on at first) and only asks what is for this character. Everything can be changed later in /tw."] }
    end
    if mode == "full" then
        for _, section in ipairs(LAYOUT) do
            local step = { title = section[1], text = L["Turn on the tools you want. Their settings are in /tw."], mods = {},
                           opts = OptionPairs(SETUP_OPTIONS[section[1]] or {}) }
            for _, key in ipairs(section[2]) do
                local page = pageByKey[key]
                if page and not page.sub and not page.mod.alwaysEnabled then step.mods[#step.mods + 1] = page end
            end
            if #step.mods > 0 or #step.opts > 0 then steps[#steps + 1] = step end
        end
    end
    steps[#steps + 1] = { done = true, title = L["This character"], opts = OptionPairs(CHARACTER_OPTIONS),
                          text = L["Your choices are saved. /tw opens the settings, /tw setup these steps again. Turning a module off fully only takes effect after a reload."] }
    return steps
end

-- A module in a step: icon, name, one line, switch.
local function NewModuleRow(parent, page)
    local mod = page.mod
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(46)
    local hl = Box(row, "small", P.hover, "HIGHLIGHT")
    hl:SetBlendMode("BLEND")
    row.icon = RoundIcon(row, 28, page.icon, P.line)
    row.icon:SetPoint("LEFT", 10, 0)
    local name = Font(row, 13, P.title)
    name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 2)
    name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    name:SetText(page.title)
    local line = Font(row, 11, P.muted)
    line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    line:SetText(page.summary or "")
    row.switch = NewSwitch(row, P)
    row.switch:SetPoint("RIGHT", -10, 0)
    row:SetScript("OnClick", function()
        Sound(not mod.active)
        TW:SetModuleEnabled(mod, not mod.active)
        TW:RefreshConfig()
        if setup then setup:Refresh() end
    end)
    function row:Refresh()
        self.switch:SetOn(mod.active, not self:IsVisible())
        self.icon:SetDesaturated(not mod.active)
    end
    return row
end

local ShowStep

-- Identifies the choices of a step's options: the Edit Mode layouts arrive after login, when the
-- setup is often already open, and a select is built for the values it has.
local function StepSignature(step)
    local parts = {}
    for _, pair in ipairs(step and step.opts or {}) do
        if pair.opt.type == "select" then
            for _, v in ipairs(pair.opt.values) do parts[#parts + 1] = tostring(v[2]) end
        end
    end
    return table.concat(parts, "\n")
end

-- The options of a step under "Worth knowing", from y; returns the y under them.
local function AddSetupOptions(content, opts, y, width)
    if #opts == 0 then return y end
    y = y - 8
    local cap = Font(content, 10, P.title)
    cap:SetPoint("TOPLEFT", 10, y)
    cap:SetText(Spaced(Upper(L["Worth knowing"])))
    local line = Rule(content, P.line, 0.5)
    line:SetPoint("LEFT", cap, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    y = y - 22
    for _, pair in ipairs(opts) do
        local w, height = CreateOption(content, pair.opt, pair.mod, P)
        if w then
            w.mod = pair.mod
            w:SetPoint("TOPLEFT", 0, y)
            if w.SetLayoutWidth then w:SetLayoutWidth(width) end
            setup.widgets[#setup.widgets + 1] = w
            y = y - height
        end
    end
    return y
end

local function BuildSetup()
    P = CurrentPalette()
    if not next(pages) then BuildPages() end
    setup = CreateFrame("Frame", "TinkerwiseSetupFrame", UIParent)
    setup:Hide()
    setup:SetWidth(SETUP_W)
    setup:SetPoint("CENTER", 0, 40)
    setup:SetFrameStrata("DIALOG")
    setup:SetToplevel(true)
    setup:SetMovable(true)
    setup:SetClampedToScreen(true)
    setup:EnableMouse(true)
    setup:RegisterForDrag("LeftButton")
    setup:SetScript("OnDragStart", setup.StartMoving)
    setup:SetScript("OnDragStop", setup.StopMovingOrSizing)
    setup:SetScale(math.min((Appearance().configScale or 100) / 100, 1.2))

    local shadow = setup:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(MEDIA .. "shadow")
    Slice(shadow, 30)
    shadow:SetPoint("TOPLEFT", -26, 26)
    shadow:SetPoint("BOTTOMRIGHT", 26, -30)
    shadow:SetVertexColor(0, 0, 0, 0.75)
    Box(setup, "fill", P.win, "BACKGROUND", -6)
    local shine = setup:CreateTexture(nil, "BACKGROUND", nil, -5)
    shine:SetTexture(MEDIA .. "shine")
    shine:SetPoint("TOPLEFT", 6, -6)
    shine:SetPoint("TOPRIGHT", -6, -6)
    shine:SetHeight(160)
    shine:SetVertexColor(1, 1, 1, P.dark and 0.05 or 0.35)
    Box(setup, "line", P.line, "BORDER", 1)
    local inner = CreateFrame("Frame", nil, setup)
    inner:SetPoint("TOPLEFT", 5, -5)
    inner:SetPoint("BOTTOMRIGHT", -5, 5)
    Box(inner, "line", P.innerLine, "BORDER", 1)

    -- Head: name, step count, progress dashes
    local head = Font(setup, 11, P.muted)
    head:SetPoint("TOPLEFT", 24, -20)
    head:SetText(Spaced(Upper(L["Tinkerwise setup"])))
    setup.count = Font(setup, 11, P.muted)
    setup.count:SetPoint("TOPRIGHT", -24, -20)
    setup.count:SetJustifyH("RIGHT")
    setup.dashes = {}
    function setup:SetMode(mode)
        setupMode = mode
        self.steps = SetupSteps(mode)
        for _, d in ipairs(self.dashes) do d:Hide() end
        local n = #self.steps
        local dashW = (SETUP_W - 48 - (n - 1) * 4) / n
        for i = 1, n do
            local d = self.dashes[i] or self:CreateTexture(nil, "ARTWORK")
            d:SetTexture(WHITE)
            d:SetSize(dashW, 3)
            d:ClearAllPoints()
            d:SetPoint("TOPLEFT", 24 + (i - 1) * (dashW + 4), -40)
            d:SetShown(n > 1)
            self.dashes[i] = d
        end
    end
    setup:SetMode(setupMode)
    setup.title = Font(setup, 26, P.title, TITLE_FONT)
    setup.title:SetPoint("TOP", 0, -58)
    setup.title:SetJustifyH("CENTER")
    local rule = setup:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(WHITE)
    rule:SetSize(220, 1)
    rule:SetPoint("TOP", setup.title, "BOTTOM", 0, -8)
    if CreateColor then
        rule:SetGradient("HORIZONTAL", CreateColor(P.line[1], P.line[2], P.line[3], 0), CreateColor(P.line[1], P.line[2], P.line[3], 0))
    end
    local left = setup:CreateTexture(nil, "ARTWORK")
    left:SetTexture(WHITE)
    left:SetSize(110, 1)
    left:SetPoint("RIGHT", rule, "CENTER", -6, 0)
    local right = setup:CreateTexture(nil, "ARTWORK")
    right:SetTexture(WHITE)
    right:SetSize(110, 1)
    right:SetPoint("LEFT", rule, "CENTER", 6, 0)
    if CreateColor then
        left:SetGradient("HORIZONTAL", CreateColor(P.line[1], P.line[2], P.line[3], 0), CreateColor(P.line[1], P.line[2], P.line[3], 0.8))
        right:SetGradient("HORIZONTAL", CreateColor(P.line[1], P.line[2], P.line[3], 0.8), CreateColor(P.line[1], P.line[2], P.line[3], 0))
    end
    local gem = Disc(setup, 6, P.line, "OVERLAY")
    gem:SetPoint("CENTER", rule, "CENTER")
    setup.text = Font(setup, 12, P.text)
    setup.text:SetWordWrap(true)
    setup.text:SetSpacing(3)
    setup.text:SetJustifyH("CENTER")
    setup.text:SetPoint("TOPLEFT", 40, -112)
    setup.text:SetPoint("TOPRIGHT", -40, -112)

    -- Footer: later on the left, back and next on the right
    local later = NewButton(setup, L["Later"], P)
    later:SetPoint("BOTTOMLEFT", 24, 20)
    later:SetScript("OnClick", function()
        TinkerwiseDB.setupSeen = true
        setup:Hide()
    end)
    setup.next = NewButton(setup, L["Next"], P, true, 26)
    setup.next:SetPoint("BOTTOMRIGHT", -24, 19)
    setup.back = NewButton(setup, L["Back"], P)
    setup.back:SetPoint("RIGHT", setup.next, "LEFT", -10, 0)
    setup.back:SetScript("OnClick", function()
        Sound(true)
        ShowStep(setupStep - 1)
    end)
    setup.next:SetScript("OnClick", function()
        Sound(true)
        if setup.steps[setupStep].welcome and setupMode ~= "quick" then -- "Quick setup" from the welcome
            setup:SetMode("quick")
            ShowStep(2)
        elseif setupStep < #setup.steps then
            ShowStep(setupStep + 1)
        else
            TinkerwiseDB.setupSeen = true
            setup:Hide()
        end
    end)

    function setup:Refresh()
        for _, w in ipairs(self.widgets or {}) do
            if w.Refresh then w:Refresh() end
        end
        if self.doneText then
            local on, all = 0, 0
            for _, mod in ipairs(TW.order) do
                if not mod.alwaysEnabled then
                    all = all + 1
                    if mod.active then on = on + 1 end
                end
            end
            self.doneText:SetText(format(L["%d of %d tools turned on."], on, all))
        end
    end

    setup:SetScript("OnUpdate", function(self, elapsed)
        if not self.fade or self.fade >= 1 then return end
        self.fade = math.min(1, self.fade + elapsed / 0.25)
        local p = 1 - (1 - self.fade) ^ 3
        self.content:SetAlpha(p)
        self.content:SetPoint("TOPLEFT", 24 + (1 - p) * 14 * (self.direction or 1), self.contentY)
    end)
    tinsert(UISpecialFrames, "TinkerwiseSetupFrame")
end

-- The content of one step, built each time it shows.
function ShowStep(index)
    local steps = setup.steps
    index = math.max(1, math.min(index, #steps))
    setup.direction = index >= setupStep and 1 or -1
    setupStep = index
    local step = steps[index]
    if setup.content then setup.content:Hide() end
    setup.widgets, setup.doneText = {}, nil

    setup.count:SetText(format(L["Step %d of %d"], index, #steps))
    setup.count:SetShown(#steps > 1)
    for i = 1, #steps do
        local d = setup.dashes[i]
        Color(d, i <= index and P.on or P.off, i <= index and 1 or 0.6)
    end
    setup.title:SetText(step.title)
    setup.text:SetText(step.text)
    setup.back:SetShown(index > 1)
    setup.next:SetLabel(step.welcome and L["Quick setup"] or index == #steps and L["Finish"] or L["Next"])

    local content = CreateFrame("Frame", nil, setup)
    setup.content = content
    setup.contentY = -128 - setup.text:GetStringHeight()
    content:SetPoint("TOPLEFT", 24, setup.contentY)
    content:SetWidth(SETUP_W - 48)
    local width = SETUP_W - 48
    local y = 0

    if step.welcome then
        -- The style, chosen here first.
        local label = Font(content, 10, P.muted)
        label:SetPoint("TOP", 0, -6)
        label:SetJustifyH("CENTER")
        label:SetText(Spaced(Upper(L["Style"])))
        local current = Appearance().style or "night"
        local bar = CreateFrame("Frame", nil, content)
        bar:SetSize(2 * 96 + 4, 26)
        bar:SetPoint("TOP", 0, -24)
        FramedPill(bar, 26, P.ctrl, P.ctrlLine)
        for i, v in ipairs({ { "night", L["Night"] }, { "grimoire", L["Grimoire"] } }) do
            local b = CreateFrame("Button", nil, bar)
            b:SetSize(96, 22)
            b:SetPoint("LEFT", 2 + (i - 1) * 96, 0)
            local fill = Pill(b, 22, "ARTWORK", 1):Place(b)
            fill:SetColor(P.sel)
            fill:SetShown(current == v[1])
            local text = Font(b, 12, current == v[1] and P.selText or P.text)
            text:SetPoint("CENTER")
            text:SetText(v[2])
            b:SetScript("OnClick", function()
                if current == v[1] then return end
                Sound(true)
                SetAppearance("style", v[1]) -- the windows are built again, this one on this step
            end)
        end
        local byTool = NewButton(content, L["Choose tool by tool"], P)
        byTool:SetPoint("TOP", 0, -66)
        byTool:SetScript("OnClick", function()
            Sound(true)
            setup:SetMode("full")
            ShowStep(2)
        end)
        y = -98
    elseif step.done then
        y = AddSetupOptions(content, step.opts, 0, width)
        if #step.opts > 0 then y = y - 12 end
        setup.doneText = Font(content, 14, P.title)
        setup.doneText:SetPoint("TOP", 0, y - 4)
        setup.doneText:SetJustifyH("CENTER")
        local open = NewButton(content, L["Open the settings"], P)
        local reload = NewButton(content, L["Reload the interface"], P)
        open:SetPoint("TOPRIGHT", content, "TOP", -6, y - 36)
        reload:SetPoint("TOPLEFT", content, "TOP", 6, y - 36)
        open:SetScript("OnClick", function()
            TinkerwiseDB.setupSeen = true
            setup:Hide()
            if not (window and window:IsShown()) then TW:ToggleConfig() end
        end)
        reload:SetScript("OnClick", function()
            TinkerwiseDB.setupSeen = true
            ReloadUI()
        end)
        y = y - 72
        if setupMode == "character" then -- a new character: the tools may differ from the others
            local byTool = NewButton(content, L["Choose tool by tool"], P)
            byTool:SetPoint("TOP", 0, y)
            byTool:SetScript("OnClick", function()
                Sound(true)
                setup:SetMode("full")
                ShowStep(2)
            end)
            y = y - 34
        end
    else
        for _, page in ipairs(step.mods) do
            local row = NewModuleRow(content, page)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", content, "RIGHT")
            setup.widgets[#setup.widgets + 1] = row
            y = y - 48
        end
        y = AddSetupOptions(content, step.opts, y, width)
    end
    content:SetHeight(-y)
    setup:SetHeight(-setup.contentY - y + 74)
    setup.fade = 0
    content:SetAlpha(0)
    setup.signature = StepSignature(step)
    setup:Refresh()
end

-- The choices of the shown step changed (layouts loaded or renamed): the step is built again, in place.
ns.RefreshSetup = function()
    if not (setup and setup:IsShown() and setup.steps) then return end
    local step = setup.steps[setupStep]
    if not step or setup.signature == StepSignature(step) then return end
    ShowStep(setupStep)
    setup.fade = 1
    setup.content:SetAlpha(1)
end

-- mode: quick (the default) or character (only the last step).
local function OpenSetup(step, mode)
    if InCombatLockdown() then
        TW:Print(L["cannot open the setup in combat."])
        return
    end
    if not setup then BuildSetup() end
    setup:SetMode(mode or "quick")
    setup:Show()
    ShowStep(step or 1)
end
ns.OpenSetup = OpenSetup
TW.commands.setup = function() OpenSetup(1) end

-- The style changed: built again, on the same step.
local function RebuildSetup()
    if not setup then return end
    local wasShown, point = setup:IsShown(), { setup:GetPoint() }
    setup:Hide()
    setup:SetScript("OnUpdate", nil)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "TinkerwiseSetupFrame" then table.remove(UISpecialFrames, i) end
    end
    setup = nil
    if not wasShown then return end
    BuildSetup()
    if point[1] then
        setup:ClearAllPoints()
        setup:SetPoint(point[1], UIParent, point[3], point[4], point[5])
    end
    setup:Show()
    ShowStep(setupStep)
end

-- Opens by itself: once for the account, and for each new character (only its last step then).
local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_LOGIN")
starter:SetScript("OnEvent", function()
    local newOne = TW.newCharacter and UnitLevel("player") == 1
    if TinkerwiseDB.setupSeen and not newOne then return end
    ns.setupPending = true
    C_Timer.After(4, function()
        ns.setupPending = nil
        if not InCombatLockdown() and not (setup and setup:IsShown()) then
            OpenSetup(1, TinkerwiseDB.setupSeen and "character" or "quick")
        end
    end)
end)

-- The style or the colors changed (Appearance): the window is built again, on the same page and at
-- the same place.
local function RebuildWindow()
    if not window then return end
    local old, wasShown, current = window, window:IsShown(), selected and selected.key
    local point = { old:GetPoint() }
    old.ready = false -- no closing sound
    old:Hide()
    old:SetScript("OnUpdate", nil)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "TinkerwiseConfigFrame" then table.remove(UISpecialFrames, i) end
    end
    TinkerwiseCharDB.configPage = current
    BuildWindow()
    if point[1] then
        window:ClearAllPoints()
        window:SetPoint(point[1], UIParent, point[3], point[4], point[5])
    end
    if wasShown then
        window:Show()
        TW:RefreshConfig()
    end
end
local function Rebuild()
    RebuildSetup()
    RebuildWindow()
    for _, fn in ipairs(ns.styleListeners) do fn() end
end
ns.RebuildConfig = Rebuild
ns.ApplyConfigScale = function()
    if not window then return end
    if IsMouseButtonDown("LeftButton") then -- still dragging
        if not window.scaleWaiting then
            window.scaleWaiting = true
            local ticker
            ticker = C_Timer.NewTicker(0.1, function()
                if IsMouseButtonDown("LeftButton") then return end
                ticker:Cancel()
                window.scaleWaiting = false
                ApplyScale()
            end)
        end
        return
    end
    ApplyScale()
end

TW:OnTheme(function() Rebuild() end)
