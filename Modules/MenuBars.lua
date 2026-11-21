-- MenuBars (Interface Elements): shows the micro menu, the bags bar and the quest tracker always, never,
-- or only while the mouse is over them. Only their transparency changes: they are never hidden or
-- moved, so Edit Mode keeps their layout and nothing is blocked in combat. While Edit Mode is open,
-- they all show. Its error messages option is in ErrorMessages.lua.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local CHECK_EVERY = 0.05
local FADE_STEP = 0.2 -- alpha per check: about a quarter of a second for a full fade

-- The first frame found for each bar (recent clients, then older ones).
local BARS = {
    { key = "microMenu", names = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" } },
    { key = "bagsBar", names = { "BagsBar" } },
    { key = "questTracker", names = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" } },
}

local mod, db, ticker
local touched = {} -- frame -> true once its alpha was changed

local function FrameOf(bar)
    for _, name in ipairs(bar.names) do
        if _G[name] then return _G[name] end
    end
end

local function EditModeOpen()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

-- Whether the quest tracker is folded (recent clients, then older ones). Fields are only read.
local function IsCollapsed(frame)
    if frame.IsCollapsed then
        local ok, collapsed = pcall(frame.IsCollapsed, frame)
        if ok then return collapsed and true or false end
    end
    if frame.isCollapsed ~= nil then return frame.isCollapsed and true or false end
    return frame.collapsed and true or false
end

local function WantedAlpha(bar, frame, mode)
    if mode == "always" or EditModeOpen() then return 1 end
    if mode == "never" then return 0 end
    -- An unfolded quest tracker stays shown: the mouseover only applies once it is folded.
    if bar.key == "questTracker" and not IsCollapsed(frame) then return 1 end
    return frame:IsMouseOver() and 1 or 0
end

local function Update()
    for _, bar in ipairs(BARS) do
        local frame = FrameOf(bar)
        if frame then
            local mode = mod.active and db[bar.key] or "always"
            local wanted = WantedAlpha(bar, frame, mode)
            local alpha = frame:GetAlpha()
            if alpha ~= wanted and (mode ~= "always" or touched[frame]) then
                touched[frame] = true
                if wanted > alpha then
                    frame:SetAlpha(math.min(wanted, alpha + FADE_STEP))
                else
                    frame:SetAlpha(math.max(wanted, alpha - FADE_STEP))
                end
            end
        end
    end
end

local function NeedsTicker()
    if not mod.active then return false end
    for _, bar in ipairs(BARS) do
        if db[bar.key] ~= "always" then return true end
    end
    return false
end

local function Apply()
    if NeedsTicker() then
        if not ticker then ticker = C_Timer.NewTicker(CHECK_EVERY, Update) end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
    -- Back to fully shown at once when nothing needs watching any more.
    if not ticker then
        for frame in pairs(touched) do frame:SetAlpha(1) end
        wipe(touched)
    end
end

local CHOICES = {
    { "always", L["Always"] },
    { "hover", L["On mouseover"] },
    { "never", L["Never"] },
}

mod = TW:NewModule("MenuBars", {
    title = L["Interface Elements"],
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    section = L["Interface"],
    desc = L["Shows the micro menu (character, spells, talents...), the bags bar and the quest tracker always, never or only when the mouse is over them (the quest tracker only once folded). They are only made transparent, never moved: Edit Mode keeps their place, and they show while it is open. Can also hide the red error messages and the voice that goes with them."],
    defaults = { microMenu = "hover", bagsBar = "hover", questTracker = "always", hideErrors = true, combatOnly = false },
    replaces = { ErrorMessages = "hideErrors" }, -- Error Messages used to be a module of its own
    whenTurnedOnByReplaced = { microMenu = "always", bagsBar = "always", questTracker = "always" },
    options = {
        { type = "header", label = L["Visibility"] },
        { type = "select", key = "microMenu", label = L["Micro menu"], values = CHOICES },
        { type = "select", key = "bagsBar", label = L["Bags bar"], values = CHOICES },
        { type = "select", key = "questTracker", label = L["Quest tracker"], values = CHOICES },
        { type = "header", label = L["Error Messages"] },
        { type = "toggle", key = "hideErrors", label = L["Hide the red error messages"] },
        { type = "toggle", key = "combatOnly", label = L["Only in combat"] },
    },
})

local function ApplyErrors()
    local hide = mod.active and db.hideErrors
    ns.SetErrorsHidden(hide and (db.combatOnly and "combat" or "always") or nil)
end

function mod:OnEnable()
    db = self.db
    Apply()
    ApplyErrors()
end

function mod:OnDisable()
    Apply()
    ApplyErrors()
end

function mod:OnOptionChanged()
    Apply()
    ApplyErrors()
end
