-- Error messages, an option of Interface Elements (MenuBars.lua): hides the red error messages at the
-- top of the screen ("Not enough mana", "Out of range"...) and the character's voice that goes with
-- them. Yellow messages (quest progress, information) stay.

local _, ns = ...

local ERROR_EVENT = "UI_ERROR_MESSAGE"

local mode -- nil (shown), "always" or "combat"
local hidden = false
local inCombat = false

-- Only the frame's event is switched off: nothing is written into the game's frame.
local function SetHidden(hide)
    if hide == hidden or not UIErrorsFrame then return end
    hidden = hide
    if hide then
        UIErrorsFrame:UnregisterEvent(ERROR_EVENT)
    else
        UIErrorsFrame:RegisterEvent(ERROR_EVENT)
    end
end

local function Update()
    SetHidden(mode == "always" or (mode == "combat" and inCombat))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    Update()
end)

function ns.SetErrorsHidden(newMode)
    mode = newMode
    if mode then
        inCombat = InCombatLockdown() and true or false
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        events:UnregisterAllEvents()
    end
    Update()
end
