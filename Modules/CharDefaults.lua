-- CharDefaults: keeps auto loot on and applies a default setup to new characters
-- (action bars, Blizzard edit mode layout). Each character is only set up once.

local _, ns = ...
local TW = ns.TW

local NEW_CHARACTER_LEVEL = 1
local FIRST_BAR, LAST_BAR = 2, 8

local db

local function CheckAutoLoot()
    if db.autoLoot and GetCVar("autoLootDefault") ~= "1" then
        SetCVar("autoLootDefault", "1")
        TW:Print("fouille automatique activée.")
    end
end

local function ApplyActionBars()
    if not db.applyBars then return end

    -- Newer settings panel: one setting per bar, numbered like the Blizzard options.
    local getSetting = Settings and Settings.GetSetting
    if getSetting and getSetting("PROXY_SHOW_ACTIONBAR_2") then
        for n = FIRST_BAR, LAST_BAR do
            local setting = getSetting("PROXY_SHOW_ACTIONBAR_" .. n)
            if setting then setting:SetValue(db["bar" .. n] and true or false) end
        end
        return
    end

    -- Otherwise: 7 bar values on recent clients, 4 on older ones. Trailing values are kept.
    if not (SetActionBarToggles and GetActionBarToggles) then return end
    local count = select("#", GetActionBarToggles())
    local toggles = { GetActionBarToggles() }
    for i = 1, count >= 7 and 7 or 4 do
        toggles[i] = db["bar" .. (i + 1)] and true or false
    end
    SetActionBarToggles(unpack(toggles, 1, count))
    if MultiActionBar_Update then MultiActionBar_Update() end
end

-- Blizzard edit mode only exists on some game versions.
local function ApplyLayout()
    local wanted = strtrim(db.layout or "")
    if wanted == "" then return true end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout) then
        TW:Print("le mode édition de Blizzard n'existe pas sur cette version du jeu.")
        return true
    end
    -- Active layout indexes count Blizzard's presets first, then the saved layouts.
    local presets = {}
    if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    end
    for i, layout in ipairs(presets) do
        if layout.layoutName == wanted then
            C_EditMode.SetActiveLayout(i)
            return true
        end
    end
    local offset = #presets > 0 and #presets or 2
    for i, layout in ipairs(C_EditMode.GetLayouts().layouts) do
        if layout.layoutName == wanted then
            C_EditMode.SetActiveLayout(i + offset)
            return true
        end
    end
    TW:Print(format("profil de mode édition « %s » introuvable.", wanted))
    return false
end

local function ApplyProfile()
    if InCombatLockdown() then
        TW:Print("impossible d'appliquer les réglages en combat.")
        return false
    end
    ApplyActionBars()
    return ApplyLayout() -- false: tried again at the next login
end

local function CharacterKey()
    return TW:PlayerName() .. "-" .. GetRealmName()
end

-- Characters already played when first seen are recorded but left untouched.
local function CheckNewCharacter()
    local key = CharacterKey()
    if db.seen[key] then return end
    if UnitLevel("player") > NEW_CHARACTER_LEVEL then
        db.seen[key] = true
    elseif ApplyProfile() then
        db.seen[key] = true
        TW:Print("réglages par défaut appliqués à ce nouveau personnage.")
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    CheckAutoLoot()
    -- Short delay: the game finishes restoring its own bar settings after login.
    C_Timer.After(1, function()
        if db then CheckNewCharacter() end
    end)
end)

local mod = TW:NewModule("CharDefaults", {
    title = "Réglages par défaut",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    section = "Configuration",
    alwaysEnabled = true,
    accountWide = true,
    desc = "Garde la fouille automatique activée et prépare les nouveaux personnages (niveau 1) : barres d'action et profil du mode édition. Les personnages existants ne changent que si vous cliquez sur « Appliquer à ce personnage ».",
    defaults = {
        autoLoot = true,
        applyBars = true,
        bar2 = true,
        bar3 = true,
        bar4 = false,
        bar5 = false,
        bar6 = false,
        bar7 = false,
        bar8 = false,
        layout = "",
    },
    options = {
        { type = "toggle", key = "autoLoot", label = "Toujours activer la fouille automatique" },
        { type = "header", label = "Barres d'action" },
        { type = "toggle", key = "applyBars", label = "Régler les barres d'action" },
        { type = "toggle", key = "bar2", label = "Barre d'actions 2" },
        { type = "toggle", key = "bar3", label = "Barre d'actions 3" },
        { type = "toggle", key = "bar4", label = "Barre d'actions 4" },
        { type = "toggle", key = "bar5", label = "Barre d'actions 5" },
        { type = "toggle", key = "bar6", label = "Barre d'actions 6", recentOnly = true },
        { type = "toggle", key = "bar7", label = "Barre d'actions 7", recentOnly = true },
        { type = "toggle", key = "bar8", label = "Barre d'actions 8", recentOnly = true },
        { type = "header", label = "Mode édition de Blizzard" },
        { type = "input", key = "layout", label = "Nom du profil (vide = ne rien changer)" },
        { type = "execute", label = "Appliquer à ce personnage", func = function()
            if not db then return end
            if ApplyProfile() then
                db.seen[CharacterKey()] = true
                TW:Print("réglages appliqués.")
            end
        end },
    },
})

-- Bars 6 to 8 only exist on recent clients.
if not _G.MultiBar5 then
    for i = #mod.options, 1, -1 do
        if mod.options[i].recentOnly then table.remove(mod.options, i) end
    end
end

function mod:OnEnable()
    db = self.db
    db.seen = db.seen or {}
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if IsLoggedIn() then CheckAutoLoot() end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
end

function mod:OnOptionChanged(key)
    if key == "autoLoot" then CheckAutoLoot() end
end
