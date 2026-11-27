-- Shows frames of Tinkerwise in the game's Edit Mode: the blue box to drag, and a small window with
-- the settings of the module when the box is clicked.
--
-- The frames are not registered as systems of the game, and none of its functions is called to
-- select, save or undo: that would taint Edit Mode and the action bars with it. The position and
-- the settings stay in the module's own options, saved at once.

local _, ns = ...
local L = ns.L

local systems = {}
local active = false
local selected

local DIALOG_WIDTH = 380

---------------------------------------------------------------------------
-- The settings window
---------------------------------------------------------------------------

local function BuildDialog(system)
    local d = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    d:SetFrameStrata("FULLSCREEN") -- above every box
    d:SetFrameLevel(200)
    d:SetPoint("RIGHT", UIParent, "RIGHT", -120, 0)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide()
    local ok, border = pcall(CreateFrame, "Frame", nil, d, "DialogBorderTranslucentTemplate")
    if ok and border then
        border:SetAllPoints()
    else
        d:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 11, top = 11, bottom = 11 },
        })
    end

    local title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -17)
    title:SetText(system.label)
    local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() system:Deselect() end)

    d.widgets = {}
    local y, buttonX = -50, nil
    local width = DIALOG_WIDTH
    -- Its first options, or those of the card named by the system: the rest is only in /tw.
    local inCard = system.card == nil
    for _, opt in ipairs(system.mod.options) do
        if opt.type == "header" then
            if inCard then break end
            inCard = opt.label == system.card
        elseif inCard and opt.editMode ~= "never" then
            local w, height, _, isButton = ns.CreateOption(d, opt, system.mod)
            if w then
                w.mod = system.mod
                d.widgets[#d.widgets + 1] = w
                if w.MinWidth then width = math.max(width, w:MinWidth() + 48) end
                if isButton and buttonX and buttonX + w:GetWidth() <= DIALOG_WIDTH - 24 then
                    w:SetPoint("TOPLEFT", buttonX, y + height) -- on the line of the previous button
                    buttonX = buttonX + w:GetWidth() + 6
                else
                    w:SetPoint("TOPLEFT", 24, y)
                    buttonX = isButton and 24 + w:GetWidth() + 6 or nil
                    y = y - height
                end
            end
        end
    end
    -- The rows take the width of the widest one.
    for _, w in ipairs(d.widgets) do
        if w.SetLayoutWidth then w:SetLayoutWidth(width - 48) end
    end
    d:SetSize(width, -y + 24)
    return d
end

---------------------------------------------------------------------------
-- The box around the frame
---------------------------------------------------------------------------

local function BuildSelection(system)
    -- The game's own box, with scripts that don't talk to its manager.
    local ok, s = pcall(CreateFrame, "Frame", nil, system.frame, "EditModeSystemSelectionTemplate")
    if not ok or not s or not s.ShowHighlighted then
        s = CreateFrame("Frame", nil, system.frame, "BackdropTemplate")
        s:EnableMouse(true)
        s:RegisterForDrag("LeftButton")
        s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        function s:ShowHighlighted()
            self:SetBackdropColor(0.1, 0.6, 1, 0.2)
            self:SetBackdropBorderColor(0.1, 0.6, 1, 1)
            self:Show()
        end
        function s:ShowSelected()
            self:SetBackdropColor(1, 0.8, 0.1, 0.2)
            self:SetBackdropBorderColor(1, 0.8, 0.1, 1)
            self:Show()
        end
    end
    s.system = { GetSystemName = function() return system.label end }
    s:SetFrameStrata(system.frame:GetFrameStrata())
    s:SetFrameLevel(1000) -- above the buttons of the frame
    s:ClearAllPoints()
    s:SetAllPoints(system.frame)
    s:SetScript("OnMouseDown", function() system:Select() end)
    s:SetScript("OnDragStart", function() system:StartMove() end)
    s:SetScript("OnDragStop", function() system:StopMove() end)
    s:Hide()
    return s
end

---------------------------------------------------------------------------
-- Snapping, when "Snap" is ticked in Edit Mode: to the screen, to the grid while it shows, to the
-- game's frames and to the other ones here. What the game knows is read, none of it is called.
---------------------------------------------------------------------------

local issecretvalue = _G.issecretvalue

-- The edges of a frame in the units of UIParent, and the scale between both.
local function Edges(frame)
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    if not ok or (issecretvalue and (issecretvalue(left) or issecretvalue(width))) or not left then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return {
        x = { left * scale, (left + width) * scale },
        y = { bottom * scale, (bottom + height) * scale },
        scale = scale,
    }
end

-- The frames to snap to: those the game snaps its own to, and the other systems here.
local function Neighbours(system)
    local list = {}
    local function Add(frame)
        if frame == system.frame or frame == UIParent then return end
        local ok, visible = pcall(frame.IsVisible, frame)
        local edges = ok and visible and Edges(frame)
        if edges then list[#list + 1] = edges end
    end
    local magnetism = EditModeMagnetismManager
    for frame in pairs(magnetism and magnetism.magneticFrames or {}) do Add(frame) end
    for _, other in ipairs(systems) do
        if other.editing then Add(other.frame) end
    end
    return list
end

-- On one axis: how far to go to the closest line in range, and where that line is.
local function Closest(axis, edges, neighbours, range)
    local cross = axis == "x" and "y" or "x"
    local low, high = edges[axis][1], edges[axis][2]
    local middle = (low + high) / 2
    local best, at
    local function Try(from, line)
        local distance = line - from
        if math.abs(distance) <= range and (not best or math.abs(distance) < math.abs(best)) then
            best, at = distance, line
        end
    end

    local size = axis == "x" and UIParent:GetWidth() or UIParent:GetHeight()
    Try(low, 0)
    Try(high, size)
    for _, from in ipairs({ middle, low, high }) do Try(from, size / 2) end

    local grid = EditModeMagnetismManager and EditModeMagnetismManager.magneticGridLines
    for _, line in pairs(grid and grid[axis == "x" and "vertical" or "horizontal"] or {}) do
        if type(line) == "number" then
            for _, from in ipairs({ middle, low, high }) do Try(from, line) end
        end
    end

    for _, other in ipairs(neighbours) do
        local otherLow, otherHigh = other[axis][1], other[axis][2]
        -- Side by side, or one above the other.
        if edges[cross][1] <= other[cross][2] + range and edges[cross][2] >= other[cross][1] - range then
            Try(low, otherHigh)
            Try(high, otherLow)
            Try(low, otherLow)
            Try(high, otherHigh)
            Try(middle, (otherLow + otherHigh) / 2)
        end
    end
    return best, at
end

-- How far the frame would jump on each axis (nil: not at all), and the lines it would rest on.
local function FindSnap(system, neighbours)
    local manager = EditModeManagerFrame
    if not (manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then return end
    local edges = Edges(system.frame)
    if not edges then return end
    local range = (EditModeMagnetismManager and EditModeMagnetismManager.magnetismRange or 8) / UIParent:GetEffectiveScale()
    local dx, atX = Closest("x", edges, neighbours, range)
    local dy, atY = Closest("y", edges, neighbours, range)
    return dx, dy, atX, atY, edges.scale
end

-- The red lines, only while a frame is dragged.
local guides

local function BuildGuides()
    guides = CreateFrame("Frame", nil, UIParent)
    guides:SetAllPoints()
    guides:SetFrameStrata("FULLSCREEN")
    guides:Hide()
    guides.vertical = guides:CreateTexture(nil, "OVERLAY")
    guides.vertical:SetColorTexture(1, 0, 0, 0.9)
    guides.vertical:SetWidth(1.5)
    guides.horizontal = guides:CreateTexture(nil, "OVERLAY")
    guides.horizontal:SetColorTexture(1, 0, 0, 0.9)
    guides.horizontal:SetHeight(1.5)
    guides:SetScript("OnUpdate", function(self)
        local _, _, x, y = FindSnap(self.system, self.neighbours)
        self.vertical:SetShown(x ~= nil)
        if x then
            self.vertical:ClearAllPoints()
            self.vertical:SetPoint("TOP", UIParent, "TOPLEFT", x, 0)
            self.vertical:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, 0)
        end
        self.horizontal:SetShown(y ~= nil)
        if y then
            self.horizontal:ClearAllPoints()
            self.horizontal:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, y)
            self.horizontal:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, y)
        end
    end)
end

---------------------------------------------------------------------------
-- Systems
---------------------------------------------------------------------------

local System = {}
System.__index = System

function System:IsEditing() return self.editing end

function System:Select()
    if not self.editing then return end
    if selected and selected ~= self then selected:Deselect() end
    selected = self
    self.selection:ShowSelected()
    self.dialog = self.dialog or BuildDialog(self)
    self.dialog:Show()
    self:RefreshDialog()
end

function System:Deselect()
    if selected == self then selected = nil end
    if self.dialog then self.dialog:Hide() end
    if self.editing then self.selection:ShowHighlighted() end
end

function System:RefreshDialog()
    if not (self.dialog and self.dialog:IsShown()) then return end
    for _, w in ipairs(self.dialog.widgets) do
        if w.Refresh then w:Refresh() end
    end
end

function System:StartMove()
    if InCombatLockdown() or not self.editing then return end
    self:Select()
    self.moving = true
    self.frame:StartMoving()
    if not guides then BuildGuides() end
    guides.system, guides.neighbours = self, Neighbours(self)
    guides.vertical:Hide()
    guides.horizontal:Hide()
    guides:Show()
end

function System:StopMove()
    if not self.moving then return end
    self.moving = nil
    guides:Hide()
    local dx, dy, _, _, scale = FindSnap(self, guides.neighbours)
    self.frame:StopMovingOrSizing()
    local point, _, _, x, y = self.frame:GetPoint()
    if dx or dy then
        x, y = x + (dx or 0) / scale, y + (dy or 0) / scale
        self.frame:ClearAllPoints()
        self.frame:SetPoint(point, UIParent, point, x, y)
    end
    if self.Save then
        self.Save(point, x, y)
    else
        local db = self.mod.db
        db.point, db.x, db.y = point, x, y
    end
    if self.OnMoved then self.OnMoved() end
end

-- Shows or hides the box, when Edit Mode opens or closes or when the module changes.
function System:Update()
    local wanted = active and self.mod.active and (not self.IsAvailable or self.IsAvailable()) and true or false
    if wanted == (self.editing or false) then return end
    self.editing = wanted
    if self.frame.SetUnlocked then self.frame:SetUnlocked(wanted) end
    if wanted then
        self.selection = self.selection or BuildSelection(self)
        self.selection:ShowHighlighted()
    else
        self:StopMove()
        self:Deselect()
        self.selection:Hide()
    end
    if self.OnEditing and self.mod.active then self.OnEditing(wanted) end
end

-- The settings shown here are not repeated in the configuration window: a button leads to Edit Mode.
local function KeepOutOfConfig(system)
    local options = system.mod.options
    local first
    local inCard = system.card == nil
    for i, opt in ipairs(options) do
        if opt.type == "header" then
            if inCard then break end
            inCard = opt.label == system.card
            if inCard then first = i + 1 end
        elseif inCard then
            if opt.toEditMode then return end -- done for another frame of the module
            first = first or i
            if opt.editMode ~= "never" then opt.editMode = "only" end
        end
    end
    table.insert(options, first or 1, {
        type = "execute", label = L["Settings in Edit Mode"], editMode = "never", toEditMode = true,
        func = function() SlashCmdList.TINKERWISEEDIT() end,
    })
end

-- info: frame, mod, label; and if needed card (the options to show: those under that header),
-- IsAvailable(), OnEditing(on) (to show or hide a preview), OnMoved(), Save(point, x, y).
-- While it is edited, a frame with the mover of TW:CreateMover answers true to IsUnlocked().
function ns.AddToEditMode(info)
    local system = setmetatable(info, System)
    KeepOutOfConfig(system)
    systems[#systems + 1] = system
    return system
end

-- Called by the core when a module is turned on or off, and when one of its options changes.
function ns.UpdateEditMode(mod)
    for _, system in ipairs(systems) do
        if system.mod == mod then
            system:Update()
            system:RefreshDialog()
        end
    end
end

---------------------------------------------------------------------------
-- When Edit Mode opens and closes
---------------------------------------------------------------------------

local function SetActive(on)
    if on and InCombatLockdown() then return end
    if active == on then return end
    active = on
    for _, system in ipairs(systems) do system:Update() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    local manager = EditModeManagerFrame
    if not manager then return end
    if event == "PLAYER_REGEN_DISABLED" then
        SetActive(false) -- the last moment the frames may still change
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetActive(manager:IsShown())
    else
        manager:HookScript("OnShow", function() SetActive(true) end)
        manager:HookScript("OnHide", function() SetActive(false) end)
        -- Only one thing is selected at a time.
        if manager.SelectSystem then
            hooksecurefunc(manager, "SelectSystem", function()
                if selected then selected:Deselect() end
            end)
        end
    end
end)
