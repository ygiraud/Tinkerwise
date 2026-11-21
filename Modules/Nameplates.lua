-- Nameplates: tunes the game's nameplates without replacing them. Sizes and class colors go through
-- the game's own settings (changed out of combat only, and given back when the module is turned
-- off); the health texture, the arrows around the target and the health percentage are added to
-- the game's plates. Plates the game keeps to itself (friendly plates in dungeons) are left alone.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local TEXTURES = {
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8x8",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local issecretvalue = _G.issecretvalue
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local mod, db

---------------------------------------------------------------------------
-- Game settings
---------------------------------------------------------------------------

local function Exists(cvar)
    return GetCVar(cvar) ~= nil
end

-- cvar -> value wanted with the current options, nil to give back the player's own value.
local function WantedCVars()
    local on = mod.active
    return {
        nameplateSelectedScale = on and format("%.2f", db.targetScale / 100) or nil,
        nameplateGlobalScale = on and format("%.2f", db.scale / 100) or nil,
    }
end

local pendingCVars = false

local function ApplyCVars()
    if InCombatLockdown() then
        pendingCVars = true
        return
    end
    pendingCVars = false
    db.savedCVars = db.savedCVars or {}
    for cvar, value in pairs(WantedCVars()) do
        if Exists(cvar) then
            if db.savedCVars[cvar] == nil then db.savedCVars[cvar] = GetCVar(cvar) end
            if GetCVar(cvar) ~= value then SetCVar(cvar, value) end
        end
    end
end

-- Puts back the values the player had before the module changed them.
local function RestoreCVars()
    if InCombatLockdown() then
        pendingCVars = true
        return
    end
    pendingCVars = false
    for cvar, value in pairs(db.savedCVars or {}) do
        if Exists(cvar) and GetCVar(cvar) ~= value then SetCVar(cvar, value) end
    end
    db.savedCVars = nil
end

---------------------------------------------------------------------------
-- Plates
---------------------------------------------------------------------------

local extras = {}        -- game unit frame -> our arrows and text
local originalTexture = {} -- health bar -> the game's texture
local textured = {}        -- health bars that carry our texture

local function UnitFrameOf(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    local frame = plate and plate.UnitFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    return frame
end

local function HealthBarOf(frame)
    return frame.healthBar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
end

local function Extras(frame, bar)
    local e = extras[frame]
    if e then return e end
    e = {}
    e.left = bar:CreateTexture(nil, "OVERLAY")
    e.left:SetTexture(ARROW)
    e.left:SetSize(14, 14)
    e.left:SetPoint("RIGHT", bar, "LEFT", -2, 0)
    e.right = bar:CreateTexture(nil, "OVERLAY")
    e.right:SetTexture(ARROW)
    e.right:SetTexCoord(1, 0, 0, 1) -- pointing left, towards the plate
    e.right:SetSize(14, 14)
    e.right:SetPoint("LEFT", bar, "RIGHT", 2, 0)
    e.percent = bar:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    e.percent:SetPoint("CENTER", bar, "CENTER", 0, 0)
    extras[frame] = e
    return e
end

local function SetTexture(bar)
    if not originalTexture[bar] then
        local texture = bar:GetStatusBarTexture()
        originalTexture[bar] = texture and (texture:GetAtlas() or texture:GetTexture()) or false
    end
    local path = mod.active and TEXTURES[db.texture]
    if path then
        bar:SetStatusBarTexture(path)
        textured[bar] = true
    elseif textured[bar] then
        textured[bar] = nil
        if originalTexture[bar] then bar:SetStatusBarTexture(originalTexture[bar]) end
    end
end

local function UpdatePercent(unit, frame)
    frame = frame or UnitFrameOf(unit)
    local e = frame and extras[frame]
    if not e then return end
    if not (mod.active and db.percent) then
        e.percent:Hide()
        return
    end
    -- Health can be a secret value: the game then formats it itself.
    local ok = pcall(function()
        if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            e.percent:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
        else
            local health, maxHealth = Plain(UnitHealth(unit)), Plain(UnitHealthMax(unit))
            if not (health and maxHealth and maxHealth > 0) then error("hidden") end
            e.percent:SetFormattedText("%d%%", health / maxHealth * 100 + 0.5)
        end
    end)
    e.percent:SetShown(ok)
end

local function UpdateArrows()
    local target = UnitFrameOf("target")
    for frame, e in pairs(extras) do
        local shown = mod.active and db.arrows and frame == target
        e.left:SetShown(shown)
        e.right:SetShown(shown)
    end
end

-- Class colors are applied here: the game's own setting has no effect on this client. The game keeps
-- the last color it set and only sets it again when it changes, so ours stays.
local classColored = {} -- health bar -> true while it carries a class color

local function PaintClassColor(unit, bar)
    local r, g, b
    if mod.active and Plain(UnitIsPlayer(unit)) then
        local friend = Plain(UnitIsFriend("player", unit))
        if (friend and db.friendlyClassColor) or (not friend and db.enemyClassColor) then
            local class = Plain(select(2, UnitClass(unit)))
            local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
            local c = class and colors and colors[class]
            if c then r, g, b = c.r, c.g, c.b end
        end
    end
    if r then
        bar:SetStatusBarColor(r, g, b)
        classColored[bar] = true
    elseif classColored[bar] then
        classColored[bar] = nil
        bar:SetStatusBarColor(UnitSelectionColor(unit, true)) -- the game's color: hostile, neutral, friendly
    end
end

local function SetupPlate(unit)
    local frame = UnitFrameOf(unit)
    local bar = frame and HealthBarOf(frame)
    if not bar then return end
    SetTexture(bar)
    Extras(frame, bar)
    PaintClassColor(unit, bar)
    UpdatePercent(unit, frame)
end

local function SetupAll()
    if not C_NamePlate then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local frame = plate.UnitFrame
        local unit = frame and Plain(frame.unit)
        if unit then SetupPlate(unit) end
    end
    UpdateArrows()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- The game sets the color again when the unit changes (a new player in the same plate).
local colorHooked = false
local function HookHealthColor()
    if colorHooked or not CompactUnitFrame_UpdateHealthColor then return end
    colorHooked = true
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        if not mod.active or not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
        local unit = Plain(frame.unit)
        local bar = HealthBarOf(frame)
        if unit and bar and unit:find("^nameplate") then PaintClassColor(unit, bar) end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- After the game has set the plate up: it puts its own texture back when it does.
        C_Timer.After(0, function()
            if mod.active and Plain(UnitExists(unit)) then
                SetupPlate(unit)
                UpdateArrows()
            end
        end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local frame = UnitFrameOf(unit)
        local e = frame and extras[frame]
        if e then
            e.left:Hide()
            e.right:Hide()
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if type(unit) == "string" and unit:find("^nameplate") then UpdatePercent(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateArrows()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingCVars then
            if mod.active then ApplyCVars() else RestoreCVars() end
        end
    end
end)

mod = TW:NewModule("Nameplates", {
    title = L["Nameplates"],
    icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    section = L["Interface"],
    desc = L["Tunes the game's nameplates without replacing them: size of the target and of the others, class colors, health texture, arrows around your target and health percentage. Size and color settings change out of combat, and turning the module off gives back your own."],
    defaults = {
        targetScale = 120, scale = 100,
        enemyClassColor = true, friendlyClassColor = true,
        texture = "smooth", arrows = true, percent = true,
    },
    options = {
        { type = "header", label = L["Size"] },
        { type = "slider", key = "targetScale", label = L["Target size (%)"], min = 100, max = 160, step = 5 },
        { type = "slider", key = "scale", label = L["Size of the others (%)"], min = 60, max = 150, step = 5 },
        { type = "header", label = L["Colors"] },
        { type = "toggle", key = "enemyClassColor", label = L["Enemy players in their class color"] },
        { type = "toggle", key = "friendlyClassColor", label = L["Friendly players in their class color"] },
        { type = "header", label = L["Look"] },
        { type = "select", key = "texture", label = L["Bar texture"], values = {
            { "blizzard", L["The game's"] },
            { "smooth", L["Smooth"] },
            { "flat", L["Flat"] },
            { "raid", L["Raid frames"] },
        } },
        { type = "toggle", key = "arrows", label = L["Arrows around your target"] },
        { type = "toggle", key = "percent", label = L["Health percentage"] },
    },
})

function mod:OnEnable()
    db = self.db
    HookHealthColor()
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
        "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    ApplyCVars()
    SetupAll()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    events:RegisterEvent("PLAYER_REGEN_ENABLED") -- to give the settings back after a fight
    RestoreCVars()
    SetupAll()
    for _, e in pairs(extras) do e.percent:Hide() end
end

function mod:OnOptionChanged()
    ApplyCVars()
    SetupAll()
end
