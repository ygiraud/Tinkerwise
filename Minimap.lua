-- Tinkerwise minimap button: left click opens the configuration, drag to move it around the minimap.

local _, ns = ...
local TW = ns.TW

local button = TW:CreateRoundButton("TinkerwiseMinimapButton", Minimap, "Interface\\Icons\\INV_Misc_Wrench_01")
button:RegisterForDrag("LeftButton")
button:Hide()

local function Place()
    local angle = math.rad(TinkerwiseCharDB.minimap.angle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    TinkerwiseCharDB.minimap.angle = math.deg(math.atan2(my / scale - cy, mx / scale - cx))
    Place()
end

button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
button:SetScript("OnClick", function(_, mouse)
    if IsShiftKeyDown() then
        TW:SetEditMode(not TW.editMode)
    elseif mouse == "RightButton" and TW.modules.Checkup and TW.modules.Checkup.active then
        TW.modules.Checkup:Open()
    else
        TW:ToggleConfig()
    end
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Tinkerwise")
    GameTooltip:AddLine("Clic gauche : configuration", 1, 1, 1)
    if TW.modules.Checkup and TW.modules.Checkup.active then
        GameTooltip:AddLine("Clic droit : check-up", 1, 1, 1)
    end
    GameTooltip:AddLine("Maj + clic : déplacer les fenêtres", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer autour de la minicarte", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    TinkerwiseCharDB.minimap = TinkerwiseCharDB.minimap or { angle = 200 }
    Place()
    button:Show()
end)
