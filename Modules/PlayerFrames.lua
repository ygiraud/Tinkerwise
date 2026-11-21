-- PlayerFrames: dresses the game's unit frames (player, target, focus, their targets, pet, party)
-- without rebuilding them: class or reaction colored health, bar texture, class colored names,
-- class icon instead of the portrait. Nothing is moved or resized and only secure hooks are used,
-- so the frames keep working in combat and Edit Mode keeps their layout. With the Dark Theme
-- module, their borders get darker too.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local TAPPED = { 0.5, 0.5, 0.5 }

local TEXTURES = {
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8x8",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}

local issecretvalue = _G.issecretvalue
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local mod, db
local groupOf = {}      -- unit frame -> option key of its group (player, target...)
local frameOfBar = {}   -- health or power bar -> its unit frame
local frameOfPortrait = {} -- portrait texture -> its unit frame
local original = {}     -- bar, name or portrait -> what it looked like before
local hooked = {}
local applying = false

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------

local function Collect()
    local function Add(frame, group)
        if type(frame) == "string" then frame = _G[frame] end
        if not frame or groupOf[frame] then return end
        groupOf[frame] = group
        if frame.healthbar then frameOfBar[frame.healthbar] = frame end
        if frame.manabar then frameOfBar[frame.manabar] = frame end
        local portrait = frame.portrait or frame.Portrait
        if portrait then frameOfPortrait[portrait] = frame end
    end
    Add("PlayerFrame", "player")
    Add("PetFrame", "pet")
    Add("TargetFrame", "target")
    Add("TargetFrameToT", "target")
    Add("FocusFrame", "focus")
    Add("FocusFrameToT", "focus")
    for i = 1, MAX_PARTY_MEMBERS or 4 do
        local member = (PartyFrame and PartyFrame["Member" .. i]) or _G["PartyMemberFrame" .. i]
        Add(member, "party")
        if member and member.PetFrame then Add(member.PetFrame, "party") end
    end
end

local function Wanted(frame)
    return mod.active and frame and db[groupOf[frame]]
end

local function UnitOf(frame)
    local unit = frame and Plain(frame.unit)
    if unit and Plain(UnitExists(unit)) then return unit end
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    class = Plain(class)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if c then return c.r, c.g, c.b end
end

local function IsPlayer(unit)
    return Plain(UnitIsPlayer(unit)) and true or false
end

---------------------------------------------------------------------------
-- Health and power bars
---------------------------------------------------------------------------

local function HealthColor(unit)
    if IsPlayer(unit) then
        if db.classColor then return ClassColor(unit) end
        return
    end
    if not db.reactionColor then return end
    if Plain(UnitIsTapDenied(unit)) then return TAPPED[1], TAPPED[2], TAPPED[3] end
    local reaction = Plain(UnitReaction(unit, "player"))
    local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
end

local function Remember(bar)
    if original[bar] then return end
    local texture = bar:GetStatusBarTexture()
    local r, g, b = bar:GetStatusBarColor()
    original[bar] = {
        r = r, g = g, b = b,
        desaturated = texture and texture:IsDesaturated(),
        atlas = texture and texture:GetAtlas(),
        file = texture and texture:GetTexture(),
    }
end

local function SetTexture(bar, wanted)
    local path = wanted and TEXTURES[db.texture]
    local o = original[bar]
    if path then
        if bar:GetStatusBarTexture() and bar:GetStatusBarTexture():GetTexture() ~= path then
            bar:SetStatusBarTexture(path)
        end
    elseif o and o.changedTexture then
        local texture = bar:GetStatusBarTexture()
        if o.atlas and texture then texture:SetAtlas(o.atlas) elseif o.file then bar:SetStatusBarTexture(o.file) end
    end
    o.changedTexture = path and true or nil
end

local function PaintHealth(frame)
    local bar = frame and frame.healthbar
    if not bar or not bar.GetStatusBarTexture then return end
    local wanted, unit = Wanted(frame), UnitOf(frame)
    Remember(bar)
    applying = true
    SetTexture(bar, wanted)
    local r, g, b
    if wanted and unit then r, g, b = HealthColor(unit) end
    local texture = bar:GetStatusBarTexture()
    local o = original[bar]
    if r then
        if texture then texture:SetDesaturated(true) end
        bar:SetStatusBarColor(r, g, b)
        o.colored = true
    elseif o.colored or o.changedTexture then
        -- Back to the game's color; a replaced texture needs one: the usual green.
        if texture then texture:SetDesaturated(o.desaturated) end
        if o.changedTexture then bar:SetStatusBarColor(0, 0.8, 0) else bar:SetStatusBarColor(o.r, o.g, o.b) end
        o.colored = nil
    end
    applying = false
end

-- The game's power textures are already colored; a replaced texture takes the power's color.
local function PaintPower(frame)
    local bar = frame and frame.manabar
    if not bar or not bar.GetStatusBarTexture then return end
    local wanted, unit = Wanted(frame), UnitOf(frame)
    Remember(bar)
    local o = original[bar]
    local hadTexture = o.changedTexture
    applying = true
    SetTexture(bar, wanted)
    if o.changedTexture and unit then
        local powerType, token = UnitPowerType(unit)
        local c = PowerBarColor and (PowerBarColor[Plain(token)] or PowerBarColor[Plain(powerType)])
        if c then bar:SetStatusBarColor(c.r, c.g, c.b) end
    elseif hadTexture then
        bar:SetStatusBarColor(o.r, o.g, o.b)
    end
    applying = false
end

---------------------------------------------------------------------------
-- Names and portraits
---------------------------------------------------------------------------

local function PaintName(frame)
    local name = frame and frame.name
    if not name or not name.SetTextColor then return end
    if not original[name] then original[name] = { name:GetTextColor() } end
    local unit = UnitOf(frame)
    local r, g, b
    if Wanted(frame) and db.classNames and unit and IsPlayer(unit) then r, g, b = ClassColor(unit) end
    if r then
        name:SetTextColor(r, g, b)
        original[name].colored = true
    elseif original[name].colored then
        local o = original[name]
        name:SetTextColor(o[1], o[2], o[3])
        o.colored = nil
    end
end

local function PaintPortrait(frame)
    local portrait = frame and (frame.portrait or frame.Portrait)
    if not portrait or not portrait.SetTexCoord then return end
    local unit = UnitOf(frame)
    local class
    if unit then class = Plain(select(2, UnitClass(unit))) end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if Wanted(frame) and db.portrait == "class" and unit and IsPlayer(unit) and coords then
        portrait:SetTexture(CLASS_ICONS)
        portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        original[portrait] = true
    elseif original[portrait] then
        original[portrait] = nil
        portrait:SetTexCoord(0, 1, 0, 1)
        if unit then SetPortraitTexture(portrait, unit) end
    end
end

local function PaintFrame(frame)
    PaintHealth(frame)
    PaintPower(frame)
    PaintName(frame)
    PaintPortrait(frame)
end

local function PaintAll()
    Collect()
    for frame in pairs(groupOf) do PaintFrame(frame) end
end

---------------------------------------------------------------------------
-- Hooks (once; they check that the module is active)
---------------------------------------------------------------------------

local function OnBarColorSet(bar)
    if applying then return end
    local frame = frameOfBar[bar]
    if not (frame and Wanted(frame)) then return end
    if bar == frame.healthbar then PaintHealth(frame) else PaintPower(frame) end
end

local function HookBars()
    for bar in pairs(frameOfBar) do
        if not hooked[bar] then
            hooked[bar] = true
            hooksecurefunc(bar, "SetStatusBarColor", OnBarColorSet)
            hooksecurefunc(bar, "SetStatusBarTexture", OnBarColorSet)
        end
    end
end

local function OnFrameUpdate(frame)
    if groupOf[frame] and mod.active then PaintFrame(frame) end
end

local function HookGame()
    if hooked.game then return end
    hooked.game = true
    if UnitFrame_Update then hooksecurefunc("UnitFrame_Update", OnFrameUpdate) end
    -- Some frames (target of target) set their portrait without UnitFramePortrait_Update.
    if SetPortraitTexture then
        hooksecurefunc("SetPortraitTexture", function(texture)
            local frame = frameOfPortrait[texture]
            if frame and mod.active then PaintPortrait(frame) end
        end)
    end
    if UnitFramePortrait_Update then
        hooksecurefunc("UnitFramePortrait_Update", function(frame)
            if groupOf[frame] and mod.active then PaintPortrait(frame) end
        end)
    end
    if UnitFrameHealthBar_Update then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar)
            local frame = frameOfBar[bar]
            if frame and mod.active then PaintHealth(frame) end
        end)
    end
    if UnitFrameManaBar_UpdateType then
        hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
            local frame = frameOfBar[bar]
            if frame and mod.active then PaintPower(frame) end
        end)
    end
end

local pending = false
local function QueuePaint()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        PaintAll()
        HookBars()
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", QueuePaint)

mod = TW:NewModule("PlayerFrames", {
    title = L["Unit Frames"],
    icon = "Interface\\Icons\\Achievement_Character_Human_Male",
    section = L["Interface"],
    desc = L["Dresses the game's unit frames without rebuilding them: health colored by class or by reaction, bar texture, class colored names and class icon instead of the portrait. Nothing is moved or resized, so the frames keep working in combat and Edit Mode keeps their layout. With the Dark Theme module, their borders get darker too."],
    defaults = {
        classColor = true, reactionColor = true, texture = "blizzard", classNames = true, portrait = "blizzard",
        player = true, target = true, focus = true, party = true, pet = true,
    },
    options = {
        { type = "header", label = L["Bars"] },
        { type = "toggle", key = "classColor", label = L["Players' health in their class color"] },
        { type = "toggle", key = "reactionColor", label = L["Creatures' health by reaction (hostile, neutral, friendly)"] },
        { type = "select", key = "texture", label = L["Bar texture"], values = {
            { "blizzard", L["The game's"] },
            { "smooth", L["Smooth"] },
            { "flat", L["Flat"] },
            { "raid", L["Raid frames"] },
        } },
        { type = "header", label = L["Name and portrait"] },
        { type = "toggle", key = "classNames", label = L["Players' names in their class color"] },
        { type = "select", key = "portrait", label = L["Portrait"], values = {
            { "blizzard", L["The game's"] },
            { "class", L["Class icon (players)"] },
        } },
        { type = "header", label = L["Frames"] },
        { type = "toggle", key = "player", label = L["Player"] },
        { type = "toggle", key = "target", label = L["Target and target of target"] },
        { type = "toggle", key = "focus", label = L["Focus and its target"] },
        { type = "toggle", key = "party", label = L["Party"] },
        { type = "toggle", key = "pet", label = L["Pet"] },
    },
})

function mod:OnEnable()
    db = self.db
    HookGame()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE", "UNIT_PET", "UNIT_TARGET", "UNIT_FACTION", "UNIT_DISPLAYPOWER" }) do
        pcall(events.RegisterEvent, events, event) -- some events don't exist in every game version
    end
    QueuePaint()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    PaintAll()
end

function mod:OnOptionChanged()
    PaintAll()
    HookBars()
end
