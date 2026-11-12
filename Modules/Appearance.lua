-- Appearance: colors of the configuration and check-up windows, gold or the class color.
-- The colors themselves are in Core.lua (TW:SetClassTheme, TW:OnTheme).

local _, ns = ...
local L = ns.L
local TW = ns.TW

local mod = TW:NewModule("Appearance", {
    title = L["Appearance"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    section = "Configuration",
    alwaysEnabled = true,
    accountWide = true,
    desc = L["Colors of the Tinkerwise windows (configuration and check-up): the gold of the interface, or the color of the class you play. Each character gets its own class color."],
    defaults = { classColors = true },
    options = {
        { type = "toggle", key = "classColors", label = L["Class colors"] },
    },
})

function mod:OnEnable()
    TW:SetClassTheme(self.db.classColors)
end

function mod:OnOptionChanged(key)
    if key == "classColors" then TW:SetClassTheme(self.db.classColors) end
end
