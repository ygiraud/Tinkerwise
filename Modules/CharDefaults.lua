-- CharDefaults: keeps auto loot on and applies a default setup to new characters
-- (action bars, Blizzard edit mode layout). Each character is only set up once.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local NEW_CHARACTER_LEVEL = 1
local FIRST_BAR, LAST_BAR = 2, 8

local db

local function CheckAutoLoot()
    if db.autoLoot and GetCVar("autoLootDefault") ~= "1" then
        SetCVar("autoLootDefault", "1")
        TW:Print(L["auto loot enabled."])
    end
end

-- Only the game's own function: running Blizzard's settings or bar code from here would taint the action
-- bars, and a bar button hovered in combat would then be blocked (SetShown in UpdateShownButtons). The
-- bars follow at the next /reload or login. 7 bar values on recent clients, 4 on older ones; trailing
-- values are kept. Returns whether anything changed.
local function ApplyActionBars()
    if not (db.applyBars and SetActionBarToggles and GetActionBarToggles) then return false end
    local count = select("#", GetActionBarToggles())
    local toggles = { GetActionBarToggles() }
    local changed = false
    for i = 1, math.min(count >= 7 and 7 or 4, LAST_BAR - FIRST_BAR + 1) do
        local wanted = db["bar" .. (i + 1)] and true or false
        if (toggles[i] and true or false) ~= wanted then changed = true end
        toggles[i] = wanted
    end
    if changed then SetActionBarToggles(unpack(toggles, 1, count)) end
    return changed
end

-- Blizzard edit mode only exists on some game versions.
local function ApplyLayout()
    local wanted = strtrim(db.layout or "")
    if wanted == "" then return true end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout) then
        TW:Print(L["Blizzard's Edit Mode does not exist in this game version."])
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
    TW:Print(format(L["Edit Mode profile \"%s\" not found."], wanted))
    return false
end

local function ApplyProfile()
    if InCombatLockdown() then
        TW:Print(L["cannot apply settings in combat."])
        return false
    end
    if ApplyActionBars() then TW:Print(L["action bars changed: they show after a /reload."]) end
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
        TW:Print(L["default settings applied to this new character."])
    end
end

-- Faster loot: every slot is taken as soon as the window is ready, without waiting for the window
-- to show. Only when the game loots automatically (the auto loot key reverses it).
local FAST_LOOT_DELAY = 0.3 -- seconds: LOOT_READY can fire twice for the same corpse
local lastLoot = 0
local looter = CreateFrame("Frame")
looter:SetScript("OnEvent", function()
    if GetTime() - lastLoot < FAST_LOOT_DELAY then return end
    if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end
    lastLoot = GetTime()
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end)

local function ApplyFastLoot()
    looter:UnregisterAllEvents()
    if db and db.fastLoot then looter:RegisterEvent("LOOT_READY") end
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
    title = L["Default Settings"],
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    section = "Configuration",
    alwaysEnabled = true,
    accountWide = true,
    desc = L["Keeps auto loot on (and faster) and sets up new characters (level 1): action bars and Edit Mode profile. Existing characters only change if you click \"Apply to this character\"."],
    defaults = {
        autoLoot = true,
        fastLoot = true,
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
        { type = "toggle", key = "autoLoot", label = L["Always enable auto loot"] },
        { type = "toggle", key = "fastLoot", label = L["Faster loot"] },
        { type = "header", label = L["Action bars"] },
        { type = "toggle", key = "applyBars", label = L["Set up action bars"] },
        { type = "toggle", key = "bar2", label = L["Action bar 2"] },
        { type = "toggle", key = "bar3", label = L["Action bar 3"] },
        { type = "toggle", key = "bar4", label = L["Action bar 4"] },
        { type = "toggle", key = "bar5", label = L["Action bar 5"] },
        { type = "toggle", key = "bar6", label = L["Action bar 6"], recentOnly = true },
        { type = "toggle", key = "bar7", label = L["Action bar 7"], recentOnly = true },
        { type = "toggle", key = "bar8", label = L["Action bar 8"], recentOnly = true },
        { type = "header", label = L["Blizzard Edit Mode"] },
        { type = "input", key = "layout", label = L["Profile name (empty = change nothing)"] },
        { type = "execute", label = L["Apply to this character"], func = function()
            if not db then return end
            if ApplyProfile() then
                db.seen[CharacterKey()] = true
                TW:Print(L["settings applied."])
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
    ApplyFastLoot()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    looter:UnregisterAllEvents()
end

function mod:OnOptionChanged(key)
    if key == "autoLoot" then CheckAutoLoot() end
    if key == "fastLoot" then ApplyFastLoot() end
end
