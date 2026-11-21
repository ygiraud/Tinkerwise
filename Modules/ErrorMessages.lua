-- ErrorMessages: hides the red error messages at the top of the screen ("Not enough mana",
-- "Out of range"...) and the character's voice that goes with them. Yellow messages
-- (quest progress, information) stay.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local ERROR_EVENT = "UI_ERROR_MESSAGE"

local mod, db
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
    SetHidden(mod.active and (not db.combatOnly or inCombat) and true or false)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    Update()
end)

mod = TW:NewModule("ErrorMessages", {
    title = L["Error Messages"],
    icon = "Interface\\Icons\\Spell_Holy_Silence",
    section = L["Interface"],
    desc = L["Hides the red error messages at the top of the screen (\"Not enough mana\", \"Out of range\"...) and the voice of your character that goes with them. Quest progress and other yellow messages still show."],
    defaults = {
        combatOnly = false,
    },
    options = {
        { type = "toggle", key = "combatOnly", label = L["Only in combat"] },
    },
})

function mod:OnEnable()
    db = self.db
    inCombat = InCombatLockdown() and true or false
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Update()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    Update()
end

function mod:OnOptionChanged()
    Update()
end
