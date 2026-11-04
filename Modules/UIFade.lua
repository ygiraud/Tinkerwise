-- UIFade: the "hide interface" key (Alt+Z) fades the interface in and out.
-- In combat the normal key behavior is left in place, as addons may not hide the interface then.

local _, ns = ...
local TW = ns.TW

local db
local fading, from, to, elapsedTime = false, 1, 1, 0

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
    elapsedTime = elapsedTime + elapsed
    local p = math.min(elapsedTime / db.duration, 1)
    UIParent:SetAlpha(from + (to - from) * p)
    if p >= 1 then
        fading = false
        self:Hide()
        if to == 0 then
            SetUIVisibility(false)
            UIParent:SetAlpha(1) -- ready for any other way of showing it again
        end
    end
end)

local function Fade(a, b)
    from, to, elapsedTime, fading = a, b, 0, true
    driver:Show()
end

local toggle = CreateFrame("Button", "TinkerwiseUIFadeToggle")
toggle:SetScript("OnClick", function()
    if fading then return end
    if UIParent:IsShown() then
        Fade(1, 0)
    else
        UIParent:SetAlpha(0)
        SetUIVisibility(true)
        Fade(0, 1)
    end
end)

local function ApplyBinding()
    ClearOverrideBindings(toggle)
    if not db or InCombatLockdown() then return end
    local key1, key2 = GetBindingKey("TOGGLEUI")
    if key1 then SetOverrideBindingClick(toggle, false, key1, "TinkerwiseUIFadeToggle") end
    if key2 then SetOverrideBindingClick(toggle, false, key2, "TinkerwiseUIFadeToggle") end
end

local function CancelFade()
    if not fading then return end
    fading = false
    driver:Hide()
    UIParent:SetAlpha(1)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        CancelFade()
        ClearOverrideBindings(toggle)
    else
        ApplyBinding()
    end
end)

local mod = TW:NewModule("UIFade", {
    title = "Fondu de l'interface",
    icon = "Interface\\Icons\\Spell_Shadow_Twilight",
    section = "Immersion",
    desc = "La touche qui masque l'interface (Alt+Z par défaut) la fait apparaître et disparaître en fondu. En combat, elle garde son comportement normal.",
    defaults = { duration = 0.5 },
    options = {
        { type = "slider", key = "duration", label = "Durée du fondu (s)", min = 0.1, max = 2, step = 0.1 },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("UPDATE_BINDINGS")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    ApplyBinding()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    CancelFade()
    ClearOverrideBindings(toggle)
end
