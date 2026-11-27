-- CharDefaults: keeps auto loot on, sets up the action bars of new characters (each one only once),
-- and picks the Edit Mode layout of this character (asked by the setup, which every new one goes through).

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

-- Blizzard's Edit Mode layouts, when this game version has them: Blizzard's presets first, then the
-- saved ones, as the game counts them. Kept in place for the select of the options.
local HAS_EDIT_MODE = C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout
local layoutNames = {} -- { name, name } for the select
local layoutIndex = {} -- name -> index for SetActiveLayout

local function ReadLayouts()
    wipe(layoutNames)
    wipe(layoutIndex)
    if not HAS_EDIT_MODE then return end
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then return end
    local presets = {}
    if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}
    end
    local function Add(name, index)
        if type(name) ~= "string" or name == "" or layoutIndex[name] then return end
        layoutIndex[name] = index
        layoutNames[#layoutNames + 1] = { name, name }
    end
    for i, layout in ipairs(presets) do Add(layout.layoutName, i) end
    local offset = #presets > 0 and #presets or 2
    local active
    for i, layout in ipairs(info.layouts) do
        Add(layout.layoutName, i + offset)
        if info.activeLayout == i + offset then active = layout.layoutName end
    end
    if not active then
        local preset = presets[info.activeLayout]
        active = preset and preset.layoutName
    end
    if db then db.thisLayout = active or "" end
end

-- Uses the layout for this character, at once (the game keeps the choice per character).
local function UseLayout(name)
    local index = layoutIndex[name or ""]
    if not index then return end
    if InCombatLockdown() then
        TW:Print(L["cannot apply settings in combat."])
        ReadLayouts()
        return
    end
    C_EditMode.SetActiveLayout(index)
    TW:Print(format(L["Edit Mode layout \"%s\" used for this character."], name))
end

local function ApplyProfile()
    if InCombatLockdown() then
        TW:Print(L["cannot apply settings in combat."])
        return false
    end
    if ApplyActionBars() then TW:Print(L["action bars changed: they show after a /reload."]) end
    return true
end

local function CharacterKey()
    return TW:PlayerName() .. "-" .. GetRealmName()
end

-- The realm sometimes reads empty on WoW Forever: a character seen on any realm is not new then.
local function SeenOnAnyRealm()
    local prefix = TW:PlayerName() .. "-"
    for key in pairs(db.seen) do
        if key:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Characters already played when first seen are recorded but left untouched.
local function CheckNewCharacter()
    local key = CharacterKey()
    if db.seen[key] or (GetRealmName() == "" and SeenOnAnyRealm()) then return end
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
    section = L["System"],
    alwaysEnabled = true,
    accountWide = true,
    desc = L["Keeps auto loot on (and faster), sets up the action bars of new characters (level 1) and picks the Edit Mode layout of this character. Existing characters only get the bars if you click \"Apply to this character\"."],
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
        thisLayout = "",
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
        { type = "execute", label = L["Apply to this character"], func = function()
            if not db then return end
            if ApplyProfile() then
                db.seen[CharacterKey()] = true
                TW:Print(L["settings applied."])
            end
        end },
        { type = "header", label = L["Blizzard Edit Mode"], editModeLayout = true },
        { type = "select", key = "thisLayout", label = L["Edit Mode layout of this character"], values = layoutNames,
          editModeLayout = true },
    },
})

-- Bars 6 to 8 only exist on recent clients, the layouts with Blizzard's Edit Mode.
for i = #mod.options, 1, -1 do
    local opt = mod.options[i]
    if (opt.recentOnly and not _G.MultiBar5) or (opt.editModeLayout and not HAS_EDIT_MODE) then
        table.remove(mod.options, i)
    end
end

-- The layouts come and go: the list follows, and the options with it.
local layouts = CreateFrame("Frame")
layouts:SetScript("OnEvent", function()
    ReadLayouts()
    TW:RefreshConfig()
end)

function mod:OnEnable()
    db = self.db
    db.seen = db.seen or {}
    db.layout = nil -- the old layout name for new characters: the setup asks each one now
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if HAS_EDIT_MODE then layouts:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED") end
    ReadLayouts()
    if IsLoggedIn() then CheckAutoLoot() end
    ApplyFastLoot()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    layouts:UnregisterAllEvents()
    looter:UnregisterAllEvents()
end

function mod:OnOptionChanged(key)
    if key == "autoLoot" then CheckAutoLoot() end
    if key == "fastLoot" then ApplyFastLoot() end
    if key == "thisLayout" then UseLayout(db.thisLayout) end
end
