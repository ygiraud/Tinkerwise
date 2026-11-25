-- Journal: keeps, for each character, the date of the zones seen for the first time, the levels, the
-- deaths and the bosses. Shown with /tw journal. Saved for the account, so that a lost Hardcore
-- character can still be read.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local MAX_ENTRIES = 2000

-- strong: written in its own color.
local KINDS = {
    zone = { icon = "Interface\\Icons\\INV_Misc_Map_01", text = L["Discovered %s"], label = L["Zones"],
             color = { 0.25, 0.36, 0.22 } },
    level = { icon = "Interface\\Icons\\Spell_Holy_BorrowedTime", text = L["Reached level %s"], label = L["Levels"],
              color = { 0.62, 0.4, 0.05 }, strong = true },
    death = { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", text = L["Died in %s"], label = L["Deaths"],
              color = { 0.5, 0.06, 0.05 }, strong = true },
    boss = { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", text = L["Defeated %s"], label = L["Bosses"],
             color = { 0.33, 0.14, 0.42 }, strong = true },
}

local db -- nil while the module is off
local win, rows, shownKey = nil, {}, nil
local filter -- the only kind shown, or nil
local pageAt = 1 -- the page of entries shown
local Refresh

local function Store()
    TinkerwiseDB.journal = TinkerwiseDB.journal or {}
    return TinkerwiseDB.journal
end

-- The character's record: { name, class, entries = { { kind, text, time, level } }, zones = { [name] = true } }.
local function Own()
    local key = ns.CharacterKey()
    local record = Store()[key]
    -- The realm sometimes reads empty on WoW Forever: the record already there is the same character's.
    if not record and key:sub(-3) == " - " then
        for other, r in pairs(Store()) do
            if other:sub(1, #key) == key then record, key = r, other break end
        end
    end
    if not record then
        record = { entries = {}, zones = {}, deaths = 0 }
        Store()[key] = record
    end
    record.name = TW:PlayerName()
    record.className, record.class = UnitClass("player")
    record.level = UnitLevel("player")
    return record, key
end

local function Add(kind, text)
    if not db or not db[kind] or type(text) ~= "string" or text == "" then return end
    local record = Own()
    local entries = record.entries
    if kind == "level" then record.level = tonumber(text) end -- the game may be a step behind
    entries[#entries + 1] = { kind, text, time(), record.level }
    if #entries > MAX_ENTRIES then table.remove(entries, 1) end
    Refresh()
end

local function ZoneName()
    local name = ns.Spells.Plain(GetRealZoneText())
    return name ~= "" and name or nil
end

local function NoteZone()
    local zone = ZoneName()
    if not db or not zone then return end
    local record = Own()
    if record.zones[zone] then return end
    record.zones[zone] = true
    Add("zone", zone)
end

local function NoteDeath()
    local record = Own()
    record.deaths = record.deaths + 1
    Add("death", ZoneName() or "?")
end

ns.Journal = {}

-- The character's deaths since the journal exists, and the time of their last level (or nil).
function ns.Journal.Deaths()
    return db and Own().deaths or nil
end

function ns.Journal.LevelTime(level)
    if not db then return end
    local entries = Own().entries
    for i = #entries, 1, -1 do
        if entries[i][1] == "level" and entries[i][2] == tostring(level) then return entries[i][3] end
    end
end

---------------------------------------------------------------------------
-- Window: an open book. On the left page the character, in 3D for the one being played, with the
-- totals, which filter the entries when clicked. On the right page the entries, newest first, day by
-- day along a line of ink. The bookmarks on the side open the other characters' books.
---------------------------------------------------------------------------

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local TEXT_FONT = STANDARD_TEXT_FONT
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local PAGE_W, PAGE_H, MARGIN = 322, 460, 20
local LIST_W = PAGE_W - 48
local LIST_TOP, LIST_H = 88, 328
local DAY_H, ROW_H = 34, 42
local LINE_X = 18
local MARKS, MARK_H = 9, 47
local STAND, WAVE = 0, 67
local INK, FADED = { 0.2, 0.11, 0.04 }, { 0.42, 0.29, 0.16 }

local function Text(parent, font, size, color)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    fs:SetFont(font, size, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetWordWrap(false)
    return fs
end

local function SortedKeys()
    local keys = {}
    for key in pairs(Store()) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function SetClassIcon(texture, class)
    local atlas = class and "classicon-" .. class:lower()
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        return
    end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    if coords then texture:SetTexCoord(unpack(coords)) end
end

local function Round(texture, parent)
    local ok, mask = pcall(parent.CreateMaskTexture, parent)
    if not ok or not mask then return end
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

local function DayText(stamp)
    local day = date("%Y%m%d", stamp)
    if day == date("%Y%m%d") then return L["Today"] end
    if day == date("%Y%m%d", time() - 86400) then return L["Yesterday"] end
    local d = date("*t", stamp)
    local weekdays, months = CALENDAR_WEEKDAY_NAMES, CALENDAR_FULLDATE_MONTH_NAMES
    if weekdays and months and weekdays[d.wday] and months[d.month] then
        return format(L["%1$s, %3$s %2$d, %4$d"], weekdays[d.wday], d.day, months[d.month], d.year)
    end
    return date(L["%m/%d/%Y"], stamp)
end

local function Paper(parent)
    local paper = parent:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
        paper:SetAtlas("QuestBG-Parchment")
    else
        paper:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
        paper:SetVertexColor(1, 0.92, 0.78)
    end
    return paper
end

local function Page(side)
    local page = CreateFrame("Frame", nil, win)
    page:SetSize(PAGE_W, PAGE_H)
    page:SetPoint(side == "left" and "TOPLEFT" or "TOPRIGHT", side == "left" and MARGIN or -MARGIN, -MARGIN)
    Paper(page)
    -- The fold: darker towards the middle of the book.
    local fold = page:CreateTexture(nil, "BORDER")
    fold:SetTexture("Interface\\Buttons\\WHITE8X8")
    fold:SetWidth(46)
    fold:SetPoint(side == "left" and "TOPRIGHT" or "TOPLEFT")
    fold:SetPoint(side == "left" and "BOTTOMRIGHT" or "BOTTOMLEFT")
    local dark, clear = CreateColor(0.1, 0.05, 0, 0.5), CreateColor(0.1, 0.05, 0, 0)
    if side == "left" then
        fold:SetGradient("HORIZONTAL", clear, dark)
    else
        fold:SetGradient("HORIZONTAL", dark, clear)
    end
    -- Worn edges.
    local edge, none = CreateColor(0.25, 0.13, 0.03, 0.45), CreateColor(0.25, 0.13, 0.03, 0)
    local function Edge(orientation, from, to, a, b)
        local t = page:CreateTexture(nil, "BORDER")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetSize(26, 26)
        t:SetPoint(a)
        t:SetPoint(b)
        t:SetGradient(orientation, from, to)
    end
    Edge("VERTICAL", none, edge, "TOPLEFT", "TOPRIGHT")
    Edge("VERTICAL", edge, none, "BOTTOMLEFT", "BOTTOMRIGHT")
    if side == "left" then
        Edge("HORIZONTAL", edge, none, "TOPLEFT", "BOTTOMLEFT")
    else
        Edge("HORIZONTAL", none, edge, "TOPRIGHT", "BOTTOMRIGHT")
    end
    return page
end

-- A line of ink fading at both ends.
local function Ornament(parent, y)
    for _, half in ipairs({ -1, 1 }) do
        local t = parent:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetSize(115, 1)
        t:SetPoint(half < 0 and "RIGHT" or "LEFT", parent, "TOP", half * 6, y)
        local ink, clear = CreateColor(INK[1], INK[2], INK[3], 0.7), CreateColor(INK[1], INK[2], INK[3], 0)
        if half < 0 then t:SetGradient("HORIZONTAL", clear, ink) else t:SetGradient("HORIZONTAL", ink, clear) end
    end
    local dot = parent:CreateTexture(nil, "ARTWORK")
    dot:SetTexture(CIRCLE)
    dot:SetSize(5, 5)
    dot:SetPoint("CENTER", parent, "TOP", 0, y)
    dot:SetVertexColor(INK[1], INK[2], INK[3], 0.8)
end

local function Fade(frame)
    local group = frame:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.35)
    alpha:SetSmoothing("OUT")
    return group
end

---------------------------------------------------------------------------
-- The leaf that turns: the sheet is cut in strips, whose corners are moved each frame to draw it
-- bending around the fold, seen from above with some perspective.
---------------------------------------------------------------------------

local STRIPS, TURN_TIME = 14, 0.65
local BEND = 0.75      -- how much the pulled edge runs ahead, in radians
local DISTANCE = 6     -- of the eye, in page widths
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Puts the corners of a 1 x 1 texture at the given places (from the top of the fold).
local function Quad(texture, x1, top1, bottom1, x2, top2, bottom2)
    if x2 < x1 then -- seen from behind
        x1, top1, bottom1, x2, top2, bottom2 = x2, top2, bottom2, x1, top1, bottom1
    end
    texture:SetVertexOffset(UPPER_LEFT_VERTEX or 1, x1, top1)
    texture:SetVertexOffset(LOWER_LEFT_VERTEX or 2, x1, bottom1 + 1)
    texture:SetVertexOffset(UPPER_RIGHT_VERTEX or 3, x2 - 1, top2)
    texture:SetVertexOffset(LOWER_RIGHT_VERTEX or 4, x2 - 1, bottom2 + 1)
end

local function Corner(parent, layer)
    local t = parent:CreateTexture(nil, layer)
    t:SetSize(1, 1)
    t:SetPoint("TOPLEFT")
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

-- Draws the leaf at an angle from 0 (on the right page) to pi (on the left one).
local function Pose(leaf, angle)
    local lead = BEND * math.sin(angle) * leaf.pull
    local x, z = 0, 0
    local function Project()
        local scale = DISTANCE / (DISTANCE - z)
        local over = (scale - 1) * PAGE_H / 2
        return x * PAGE_W * scale, over, -PAGE_H - over
    end
    local x1, top1, bottom1 = Project()
    for i, strip in ipairs(leaf.strips) do
        local slope = angle + lead * ((i - 0.5) / STRIPS * 2 - 1)
        slope = math.max(0, math.min(slope, math.pi))
        x, z = x + math.cos(slope) / STRIPS, z + math.sin(slope) / STRIPS
        local x2, top2, bottom2 = Project()
        Quad(strip.paper, x1, top1, bottom1, x2, top2, bottom2)
        if x2 < x1 then
            strip.paper:SetTexCoord(strip.to, strip.from, strip.top, strip.bottom)
        else
            strip.paper:SetTexCoord(strip.from, strip.to, strip.top, strip.bottom)
        end
        -- Upright, the paper is in the shade.
        local light = 0.55 + 0.45 * math.abs(math.cos(slope))
        strip.paper:SetVertexColor(light, light, light)
        for _, ink in ipairs(strip.inks) do
            ink:SetShown(slope < math.pi / 2)
            Quad(ink, x1, top1 + (bottom1 - top1) * ink.v1, top1 + (bottom1 - top1) * ink.v2,
                x2, top2 + (bottom2 - top2) * ink.v1, top2 + (bottom2 - top2) * ink.v2)
        end
        x1, top1, bottom1 = x2, top2, bottom2
    end
    -- It shades the page it hangs over, and melts into the left one when it lies on it.
    leaf.shadeRight:SetAlpha(math.sin(angle) * (angle < math.pi / 2 and 0.6 or 0.25))
    leaf.shadeLeft:SetAlpha(math.sin(angle) * (angle < math.pi / 2 and 0.1 or 0.5))
    leaf:SetAlpha(math.min(1, (math.pi - angle) / 0.35))
end

local function Leaf(page, left)
    local leaf = CreateFrame("Frame", nil, page)
    leaf:SetAllPoints()
    leaf:SetFrameLevel(win:GetFrameLevel() + 15)
    leaf:Hide()
    leaf.strips = {}
    for side, under in pairs({ shadeRight = page, shadeLeft = left }) do
        local t = leaf:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(WHITE)
        t:SetAllPoints(under)
        local dark, clear = CreateColor(0.05, 0.02, 0, 0.9), CreateColor(0.05, 0.02, 0, 0)
        if side == "shadeRight" then
            t:SetGradient("HORIZONTAL", dark, clear)
        else
            t:SetGradient("HORIZONTAL", clear, dark)
        end
        leaf[side] = t
    end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment")
    local file = info and (info.file or info.filename) or "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"
    local l, r = info and info.leftTexCoord or 0, info and info.rightTexCoord or 1
    local top, bottom = info and info.topTexCoord or 0, info and info.bottomTexCoord or 1
    for i = 1, STRIPS do
        local strip = CreateFrame("Frame", nil, leaf)
        strip:SetAllPoints()
        strip:SetFrameLevel(leaf:GetFrameLevel() + i) -- the edge passes over the rest
        strip.paper = Corner(strip, "BACKGROUND")
        strip.paper:SetTexture(file)
        strip.from, strip.to = l + (r - l) * (i - 1) / STRIPS, l + (r - l) * i / STRIPS
        strip.top, strip.bottom = top, bottom
        strip.inks = {}
        -- Written lines, as far as they can be told while the page moves.
        for line = 1, 7 do
            for part = 1, 2 do
                local last = part == 1 and STRIPS - 1 - line % 4 or math.floor(STRIPS / 2)
                if i > 3 and i <= last then
                    local ink = Corner(strip, "ARTWORK")
                    ink:SetTexture(WHITE)
                    ink:SetVertexColor(INK[1], INK[2], INK[3], part == 1 and 0.4 or 0.22)
                    ink.v1 = (LIST_TOP + DAY_H + (line - 1) * ROW_H + (part == 1 and 10 or 27)) / PAGE_H
                    ink.v2 = ink.v1 + (part == 1 and 5 or 3) / PAGE_H
                    strip.inks[#strip.inks + 1] = ink
                end
            end
        end
        leaf.strips[i] = strip
    end
    leaf:SetScript("OnUpdate", function(self, elapsed)
        self.progress = math.min(self.progress + elapsed / TURN_TIME, 1)
        local eased = (1 - math.cos(self.progress * math.pi)) / 2
        Pose(self, math.pi * (self.pull > 0 and eased or 1 - eased))
        if self.progress == 1 then self:Finish() end
    end)
    -- Going back, the entries change once the leaf lies on them.
    function leaf:Finish()
        self:Hide()
        if self.pull < 0 then Refresh() end
    end
    function leaf:Turn(forward)
        if self:IsShown() then self:Finish() end
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
        if not self.strips[1].paper.SetVertexOffset then return Refresh() end
        self.pull, self.progress = forward and 1 or -1, 0
        Pose(self, forward and 0 or math.pi)
        self:Show()
        if forward then Refresh() end -- under the leaf
    end
    return leaf
end

local function TurnTo(number)
    if number < 1 or number > #win.pages or number == pageAt then return end
    local forward = number > pageAt
    pageAt = number
    win.leaf:Turn(forward)
end

-- Turns to another book or another filter.
local function TurnPage(both)
    pageAt = 1
    win.leaf:Turn(true)
    if both then
        win.whoFade:Stop()
        win.whoFade:Play()
    end
end

local function BuildStats(page)
    win.stats = {}
    for i, kind in ipairs({ "zone", "level", "boss", "death" }) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(132, 48)
        b:SetPoint("TOPLEFT", 27 + (i - 1) % 2 * 137, -336 - math.floor((i - 1) / 2) * 53)
        b.under = b:CreateTexture(nil, "ARTWORK") -- the one that filters
        b.under:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.under:SetSize(122, 2)
        b.under:SetPoint("BOTTOMLEFT", 4, 0)
        local color = KINDS[kind].color
        b.under:SetGradient("HORIZONTAL", CreateColor(color[1], color[2], color[3], 0.9),
            CreateColor(color[1], color[2], color[3], 0))
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        hover:SetAllPoints()
        b.disk = b:CreateTexture(nil, "BORDER")
        b.disk:SetTexture(CIRCLE)
        b.disk:SetSize(38, 38)
        b.disk:SetPoint("LEFT", 5, 0)
        b.disk:SetVertexColor(color[1], color[2], color[3], 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(33, 33)
        b.icon:SetPoint("CENTER", b.disk)
        b.icon:SetTexture(KINDS[kind].icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Round(b.icon, b)
        b.number = Text(b, TITLE_FONT, 22, INK)
        b.number:SetPoint("TOPLEFT", 52, -5)
        b.label = Text(b, TEXT_FONT, 11, FADED)
        b.label:SetPoint("BOTTOMLEFT", 52, 7)
        b.label:SetPoint("RIGHT", -4, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetText(KINDS[kind].label)
        b:SetScript("OnClick", function()
            filter = filter ~= kind and kind or nil
            TurnPage()
        end)
        win.stats[kind] = b
    end
end

local function BuildLeft()
    local page = Page("left")
    win.leftPage = page
    local who = CreateFrame("Frame", nil, page)
    who:SetAllPoints()
    win.whoFade = Fade(who)

    win.name = Text(who, TITLE_FONT, 25, INK)
    win.name:SetPoint("TOPLEFT", 20, -24)
    win.name:SetPoint("TOPRIGHT", -20, -24)
    win.info = Text(who, TEXT_FONT, 12, FADED)
    win.info:SetPoint("TOP", win.name, "BOTTOM", 0, -5)
    Ornament(who, -78)

    local stage = CreateFrame("Frame", nil, who)
    stage:SetPoint("TOPLEFT", 40, -84)
    stage:SetPoint("TOPRIGHT", -40, -84)
    stage:SetHeight(226)
    win.shadow = stage:CreateTexture(nil, "BACKGROUND") -- at the feet
    win.shadow:SetTexture(CIRCLE)
    win.shadow:SetSize(150, 26)
    win.shadow:SetPoint("BOTTOM", 0, 2)
    win.shadow:SetVertexColor(0.15, 0.08, 0.02, 0.3)
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, stage)
    if ok and model then
        model:SetAllPoints()
        model:EnableMouse(false)
        model:SetScript("OnAnimFinished", function(self) pcall(self.SetAnimation, self, STAND) end)
        win.model = model
    end
    -- The other characters: the medallion of their class.
    win.rim = stage:CreateTexture(nil, "BORDER")
    win.rim:SetTexture(CIRCLE)
    win.rim:SetSize(132, 132)
    win.rim:SetPoint("CENTER")
    win.medal = stage:CreateTexture(nil, "ARTWORK")
    win.medal:SetSize(122, 122)
    win.medal:SetPoint("CENTER")
    Round(win.medal, stage)

    Ornament(who, -322)
    BuildStats(who)
end

local function BuildRight()
    local page = Page("right")
    win.heading = Text(page, TITLE_FONT, 25, INK)
    win.heading:SetPoint("TOP", 0, -24)
    win.sub = Text(page, TEXT_FONT, 12, FADED)
    win.sub:SetPoint("TOP", win.heading, "BOTTOM", 0, -5)
    Ornament(page, -78)

    win.list = CreateFrame("Frame", nil, page)
    win.list:SetPoint("TOPLEFT", 24, -LIST_TOP)
    win.list:SetSize(LIST_W, LIST_H)
    win.listFade = Fade(win.list)
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta) TurnTo(pageAt - delta) end)

    win.leaf = Leaf(page, win.leftPage)
    win.number = Text(page, TITLE_FONT, 14, FADED)
    win.number:SetPoint("BOTTOM", 0, 20)
    for _, side in ipairs({ { "Prev", -1, "BOTTOMLEFT", 16 }, { "Next", 1, "BOTTOMRIGHT", -16 } }) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(30, 30)
        b:SetPoint(side[3], side[4], 11)
        local file = "Interface\\Buttons\\UI-SpellbookIcon-" .. side[1] .. "Page-"
        b:SetNormalTexture(file .. "Up")
        b:SetPushedTexture(file .. "Down")
        b:SetDisabledTexture(file .. "Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function() TurnTo(pageAt + side[2]) end)
        win[side[1]] = b
    end

    win.blank = Text(page, TITLE_FONT, 16, FADED)
    win.blank:SetPoint("CENTER", 0, -20)
    win.blank:SetWidth(LIST_W)
    win.blank:SetWordWrap(true)
end

-- The bookmarks, as the side tabs of the old spellbook; the wheel reaches those that do not fit.
local function BuildMarks()
    win.marks, win.markOffset = {}, 0
    local strip = CreateFrame("Frame", nil, win)
    strip:SetPoint("TOPLEFT", win, "TOPRIGHT", -4, -44)
    strip:SetSize(40, MARKS * MARK_H)
    strip:EnableMouseWheel(true)
    strip:SetScript("OnMouseWheel", function(_, delta)
        win.markOffset = math.max(0, math.min(win.markOffset - delta, #SortedKeys() - MARKS))
        Refresh()
    end)
    for i = 1, MARKS do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(32, 32)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * MARK_H)
        local leather = b:CreateTexture(nil, "BACKGROUND")
        leather:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        leather:SetSize(64, 64)
        leather:SetPoint("TOPLEFT", -3, 11)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.chosen = b:CreateTexture(nil, "OVERLAY")
        b.chosen:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.chosen:SetBlendMode("ADD")
        b.chosen:SetAllPoints()
        b:SetScript("OnClick", function(self)
            if self.key == shownKey then return end
            shownKey = self.key
            TurnPage(true)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label, self.color.r, self.color.g, self.color.b)
            if self.detail then GameTooltip:AddLine(self.detail, 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        win.marks[i] = b
    end
end

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, win.list)
    r:SetWidth(LIST_W)
    r.line = r:CreateTexture(nil, "BACKGROUND")
    r.line:SetColorTexture(INK[1], INK[2], INK[3], 0.35)
    r.line:SetWidth(2)
    r.line:SetPoint("TOP", r, "TOPLEFT", LINE_X, 0)
    r.line:SetPoint("BOTTOM", r, "BOTTOMLEFT", LINE_X, 0)
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetTexture(CIRCLE)
    r.dot:SetSize(9, 9)
    r.dot:SetPoint("CENTER", r, "LEFT", LINE_X, 0)
    r.dot:SetVertexColor(INK[1], INK[2], INK[3], 1)
    r.day = Text(r, TITLE_FONT, 17, INK)
    r.day:SetPoint("LEFT", LINE_X + 20, 0)
    r.day:SetPoint("RIGHT")
    r.day:SetJustifyH("LEFT")

    r.disk = r:CreateTexture(nil, "BORDER")
    r.disk:SetTexture(CIRCLE)
    r.disk:SetSize(34, 34)
    r.disk:SetPoint("CENTER", r, "LEFT", LINE_X, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(29, 29)
    r.icon:SetPoint("CENTER", r.disk)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Round(r.icon, r)
    r.level = Text(r, TITLE_FONT, 17, { 1, 0.95, 0.8 })
    r.level:SetPoint("CENTER", r.disk)
    r.text = Text(r, TEXT_FONT, 13, INK)
    r.text:SetPoint("TOPLEFT", LINE_X + 26, -5)
    r.text:SetPoint("RIGHT")
    r.text:SetJustifyH("LEFT")
    r.detail = Text(r, TEXT_FONT, 11, FADED)
    r.detail:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    -- A name cut by the edge of the page is read in full.
    r:SetScript("OnEnter", function(self)
        if not (self.full and self.text.IsTruncated and self.text:IsTruncated()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.full)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local function FillRow(r, item, y)
    local entry = item.entry
    r:SetHeight(item.height)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r.line:SetPoint("BOTTOM", r, item.last and "LEFT" or "BOTTOMLEFT", LINE_X, 0)
    r.day:SetShown(not entry)
    r.dot:SetShown(not entry)
    r.disk:SetShown(entry ~= nil)
    r.icon:SetShown(entry ~= nil and entry[1] ~= "level")
    r.level:SetShown(entry ~= nil and entry[1] == "level")
    r.text:SetShown(entry ~= nil)
    r.detail:SetShown(entry ~= nil)
    r.full = nil
    if not entry then
        r.day:SetText(item.day)
    else
        local kind = KINDS[entry[1]] or KINDS.zone
        local color = kind.color
        r.disk:SetVertexColor(color[1], color[2], color[3], 1)
        r.icon:SetTexture(kind.icon)
        r.level:SetText(entry[2])
        r.full = format(kind.text, entry[2])
        r.text:SetText(r.full)
        if kind.strong then r.text:SetTextColor(color[1], color[2], color[3]) else r.text:SetTextColor(INK[1], INK[2], INK[3]) end
        local hour = date("%H:%M", entry[3])
        local level = entry[1] ~= "level" and entry[4]
        r.detail:SetText(level and format(L["%s, level %d"], hour, level) or hour)
    end
    r:Show()
end

local function Build()
    win = CreateFrame("Frame", "TinkerwiseJournalFrame", UIParent, "BackdropTemplate")
    win:SetSize(PAGE_W * 2 + MARGIN * 2, PAGE_H + MARGIN * 2)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(10)
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    win:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end)
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local leather = TW:AddSolidBackground(win, 0.14, 0.1, 0.06)
    TW:OnTheme(function(theme)
        win:SetBackdropColor(theme.backdrop[1], theme.backdrop[2], theme.backdrop[3], 1)
        leather:SetColorTexture(theme.solid[1], theme.solid[2], theme.solid[3], 1)
    end)
    tinsert(UISpecialFrames, "TinkerwiseJournalFrame")

    win.pages = {}
    BuildLeft()
    BuildRight()
    BuildMarks()
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetFrameLevel(win:GetFrameLevel() + 40)
end

local function RefreshCharacter(record)
    local color = RAID_CLASS_COLORS[record.class] or NORMAL_FONT_COLOR
    win.name:SetText(record.name)
    local class = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[record.class] or ""
    win.info:SetText(record.level and format(L["%s, level %d"], record.className or class, record.level) or class)
    local own = win.model ~= nil and shownKey == win.ownKey
    win.shadow:SetShown(own)
    win.rim:SetShown(not own)
    win.medal:SetShown(not own)
    if own then
        -- Not again at each new entry: the character would start over.
        if not win.model:IsShown() or win.modelStale then
            win.modelStale = false
            win.model:Show()
            pcall(function()
                win.model:SetUnit("player")
                win.model:SetPortraitZoom(0)
                win.model:SetCamDistanceScale(1.1)
                win.model:SetRotation(0.2)
                win.model:SetAnimation(win.model:HasAnimation(WAVE) and WAVE or STAND)
            end)
        end
    else
        if win.model then win.model:Hide() end
        win.rim:SetVertexColor(color.r * 0.7, color.g * 0.7, color.b * 0.7, 1)
        SetClassIcon(win.medal, record.class)
    end
end

local function RefreshMarks()
    local keys, store = SortedKeys(), Store()
    win.markOffset = math.max(0, math.min(win.markOffset, #keys - MARKS))
    for i, b in ipairs(win.marks) do
        local key = #keys > 1 and keys[i + win.markOffset] or nil
        local record = key and store[key]
        b:SetShown(record ~= nil)
        if record then
            local color = RAID_CLASS_COLORS[record.class] or NORMAL_FONT_COLOR
            local chosen = key == shownKey
            b.key, b.label, b.color = key, record.name, color
            b.detail = record.level and format(L["Level %d"], record.level)
            SetClassIcon(b.icon, record.class)
            b.icon:SetDesaturated(not chosen)
            b.icon:SetAlpha(chosen and 1 or 0.8)
            b.chosen:SetShown(chosen)
        end
    end
end

function Refresh()
    if not win or not win:IsShown() then return end
    local record = Store()[shownKey]
    if not record then
        record, shownKey = Own()
    end
    RefreshCharacter(record)
    RefreshMarks()

    local entries = record.entries
    local counts = { zone = 0, level = 0, boss = 0, death = 0 }
    for _, entry in ipairs(entries) do counts[entry[1]] = (counts[entry[1]] or 0) + 1 end
    counts.death = math.max(counts.death, record.deaths or 0)
    for kind, b in pairs(win.stats) do
        b.number:SetText(counts[kind])
        b:SetAlpha(filter and filter ~= kind and 0.5 or 1)
        b.under:SetShown(filter == kind)
    end

    -- The pages: the entries newest first, with a heading per day, again on top of each page.
    local pages, page, y, day, shown = win.pages, nil, 0, nil, 0
    wipe(pages)
    local function Put(item, height)
        item.height = height
        page[#page + 1] = item
        y = y + height
    end
    local function NewPage()
        page, y, day = {}, 0, nil
        pages[#pages + 1] = page
    end
    NewPage()
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if not filter or entry[1] == filter then
            local this = date("%Y%m%d", entry[3])
            if y + ROW_H + (this ~= day and DAY_H or 0) > LIST_H then NewPage() end
            if this ~= day then
                day = this
                Put({ day = DayText(entry[3]) }, DAY_H)
            end
            Put({ entry = entry }, ROW_H)
            shown = shown + 1
        end
    end
    if shown > 0 and y + DAY_H <= LIST_H then Put({ day = L["Here the journey begins"], last = true }, DAY_H) end

    pageAt = math.min(pageAt, #pages)
    local top = 0
    for i, item in ipairs(pages[pageAt]) do
        FillRow(Row(i), item, top)
        top = top + item.height
    end
    for i = #pages[pageAt] + 1, #rows do rows[i]:Hide() end
    win.number:SetText(#pages > 1 and format("%d / %d", pageAt, #pages) or "")
    win.Prev:SetShown(#pages > 1)
    win.Next:SetShown(#pages > 1)
    win.Prev:SetEnabled(pageAt > 1)
    win.Next:SetEnabled(pageAt < #pages)
    win.heading:SetText(filter and KINDS[filter].label or L["Travel Journal"])
    win.sub:SetText(entries[1] and format(L["Since %s"], date(L["%m/%d/%Y"], entries[1][3])) or "")
    win.blank:SetShown(shown == 0)
    win.blank:SetText(filter and L["Nothing of the kind yet."] or L["These pages are still blank. Your travels will fill them."])
end

local function Toggle()
    if not win then Build() end
    if win:IsShown() then return win:Hide() end
    shownKey = select(2, Own())
    win.ownKey, win.modelStale, filter = shownKey, true, nil
    win.leaf:Hide()
    pageAt = 1
    win:Show()
    PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
    Refresh()
    win.listFade:Play()
    win.whoFade:Play()
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, arg2, _, _, arg5)
    if event == "PLAYER_LEVEL_UP" then
        Add("level", tostring(arg1))
    elseif event == "PLAYER_DEAD" then
        NoteDeath()
    elseif event == "ENCOUNTER_END" then
        if ns.Spells.Plain(arg5) == 1 then Add("boss", ns.Spells.Plain(arg2)) end
    else
        C_Timer.After(2, NoteZone) -- the name is not always ready at once
    end
end)

local mod = TW:NewModule("Journal", {
    title = L["Travel Journal"],
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    section = L["Character"],
    desc = L["Keeps the date of the zones you enter for the first time, your levels, your deaths and the bosses you defeat, for each character, from the day the module is on. Read it with /tw journal."],
    defaults = { zone = true, level = true, death = true, boss = true },
    options = {
        { type = "toggle", key = "zone", label = L["New zones"] },
        { type = "toggle", key = "level", label = L["Levels"] },
        { type = "toggle", key = "death", label = L["Deaths"] },
        { type = "toggle", key = "boss", label = L["Bosses"] },
        { type = "execute", label = L["Open the journal"], func = function() Toggle() end },
    },
})

TW.commands.journal = function()
    if mod.active then Toggle() else TW:Print(L["the Travel Journal module is off."]) end
end

function mod:OnEnable()
    db = self.db
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_DEAD", "ENCOUNTER_END" }) do
        pcall(events.RegisterEvent, events, e)
    end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if win then win:Hide() end
    db = nil
end
