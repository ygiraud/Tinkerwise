-- Appearance: the style of the configuration window (night or grimoire), its size, and the colors of
-- the Tinkerwise windows, gold or the class color. The colors themselves are in Core.lua
-- (TW:SetClassTheme, TW:OnTheme), the styles in Config.lua.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local mod = TW:NewModule("Appearance", {
    title = L["Appearance"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    section = L["System"],
    alwaysEnabled = true,
    accountWide = true,
    desc = L["Style of the configuration window, night or grimoire, and the colors of the Tinkerwise windows (configuration and check-up): the gold of the interface, or the color of the class you play. Each character gets its own class color."],
    defaults = { classColors = true, style = "night", configScale = 100 },
    options = {
        { type = "select", key = "style", label = L["Style of the configuration window"],
          values = { { "night", L["Night"] }, { "grimoire", L["Grimoire"] } } },
        { type = "toggle", key = "classColors", label = L["Class colors"] },
        { type = "slider", key = "configScale", label = L["Size of the configuration window (%)"], min = 70, max = 130, step = 5 },
        { type = "execute", label = L["Run the setup again"], func = function() if ns.OpenSetup then ns.OpenSetup(1) end end },
    },
})

function mod:OnEnable()
    TW:SetClassTheme(self.db.classColors)
end

function mod:OnOptionChanged(key)
    if key == "classColors" then
        TW:SetClassTheme(self.db.classColors) -- the window follows through TW:OnTheme
    elseif key == "configScale" then
        if ns.ApplyConfigScale then ns.ApplyConfigScale() end
    elseif ns.RebuildConfig then
        ns.RebuildConfig()
    end
end
