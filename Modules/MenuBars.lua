-- MenuBars: shows the micro menu and the bags bar always, never, or only while the mouse is over them.
-- Only their transparency changes: they are never hidden or moved, so Edit Mode keeps their layout
-- and nothing is blocked in combat. While Edit Mode is open, both show.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local CHECK_EVERY = 0.05
local FADE_STEP = 0.2 -- alpha per check: about a quarter of a second for a full fade

-- The first frame found for each bar (recent clients, then older ones).
local BARS = {
    { key = "microMenu", names = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" } },
    { key = "bagsBar", names = { "BagsBar" } },
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

local function WantedAlpha(frame, mode)
    if mode == "always" or EditModeOpen() then return 1 end
    if mode == "never" then return 0 end
    return frame:IsMouseOver() and 1 or 0
end

local function Update()
    for _, bar in ipairs(BARS) do
        local frame = FrameOf(bar)
        if frame then
            local mode = mod.active and db[bar.key] or "always"
            local wanted = WantedAlpha(frame, mode)
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
    return mod.active and (db.microMenu ~= "always" or db.bagsBar ~= "always")
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
    title = L["Menu and Bags Bar"],
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    section = L["Interface"],
    desc = L["Shows the micro menu (character, spells, talents...) and the bags bar always, never or only when the mouse is over them. They are only made transparent, never moved: Edit Mode keeps their place, and they show while it is open."],
    defaults = { microMenu = "hover", bagsBar = "hover" },
    options = {
        { type = "select", key = "microMenu", label = L["Micro menu"], values = CHOICES },
        { type = "select", key = "bagsBar", label = L["Bags bar"], values = CHOICES },
    },
})

function mod:OnEnable()
    db = self.db
    Apply()
end

function mod:OnDisable()
    Apply()
end

function mod:OnOptionChanged()
    Apply()
end
