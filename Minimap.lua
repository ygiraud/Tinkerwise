-- Tinkerwise minimap button: left click opens the configuration, drag to move it around the minimap.

local _, ns = ...
local TW = ns.TW

local button = TW:CreateRoundButton("TinkerwiseMinimapButton", Minimap, "Interface\\Icons\\INV_Misc_Wrench_01")
button:RegisterForDrag("LeftButton")
button:Hide()

local mod

local function Place()
    local angle = math.rad(mod.db.angle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    mod.db.angle = math.deg(math.atan2(my / scale - cy, mx / scale - cx))
    Place()
end

button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

-- What right click and Ctrl + click can do. Each one needs its module to be active.
local ACTIONS = {
    checkup = { label = "check-up", module = "Checkup", run = function() TW.modules.Checkup:Open() end },
    bags = { label = "sacs", module = "Bags", run = function() SlashCmdList.TINKERWISEBAGS() end },
    chars = { label = "mes personnages", module = "Bags", run = function() SlashCmdList.TINKERWISECHARS() end },
}

local function CurrentAction()
    local action = ACTIONS[mod.db.clickAction]
    local target = action and TW.modules[action.module]
    return target and target.active and action or nil
end

button:SetScript("OnClick", function(_, mouse)
    if not UIParent:IsShown() then return end -- its windows could not be seen
    local action = CurrentAction()
    if IsShiftKeyDown() then
        TW:SetEditMode(not TW.editMode)
    elseif action and (mouse == "RightButton" or IsControlKeyDown()) then
        action.run()
    else
        TW:ToggleConfig()
    end
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Tinkerwise")
    GameTooltip:AddLine("Clic gauche : configuration", 1, 1, 1)
    local action = CurrentAction()
    if action then
        GameTooltip:AddLine("Clic droit ou Ctrl + clic : " .. action.label, 1, 1, 1)
    end
    GameTooltip:AddLine("Maj + clic : déplacer les fenêtres", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer autour de la minicarte", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

mod = TW:NewModule("MinimapButton", {
    title = "Bouton de la minicarte",
    icon = "Interface\\Icons\\INV_Misc_Wrench_01",
    section = "Configuration",
    alwaysEnabled = true,
    desc = "Affiche le bouton de Tinkerwise autour de la minicarte et choisit l'action du clic droit et du Ctrl + clic. Si le module de cette action est désactivé, ces clics ouvrent la configuration.",
    defaults = { clickAction = "checkup", angle = 200 },
    options = {
        { type = "select", key = "clickAction", label = "Clic droit et Ctrl + clic", values = {
            { "checkup", "Check-up" },
            { "bags", "Sacs" },
            { "chars", "Mes personnages" },
        } },
    },
})

function mod:OnEnable()
    Place()
    button:Show()
end

function mod:OnDisable()
    button:Hide()
end
