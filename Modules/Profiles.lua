-- Profiles: named copies of a character's settings and window positions, shared by the account.
--
-- A profile is a copy: changing an option afterwards changes the character, not the profile. Only what
-- the player sets is copied, never what the modules keep for themselves (chat history, tabs created,
-- the game's values to give back...). The settings shared by the whole account stay out of it.

local _, ns = ...
local L = ns.L
local TW = ns.TW

-- Saved by the windows, on top of the options and defaults of each module.
local POSITION_KEYS = { "point", "x", "y", "winPoint", "winX", "winY", "btnPoint", "btnX", "btnY", "sizes" }
-- Hold the names of spells: kept for each class.
local CLASS_KEYS = { skipGroups = true, skipSpells = true, skipBuffs = true }

local _, class = UnitClass("player")
local mod

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

local function Store()
    TinkerwiseDB.profiles = TinkerwiseDB.profiles or {}
    return TinkerwiseDB.profiles
end

local function Keys(m)
    local keys = {}
    for k in pairs(m.defaults or {}) do keys[k] = true end
    for _, opt in ipairs(m.options or {}) do
        if opt.key then keys[opt.key] = true end
    end
    for _, k in ipairs(POSITION_KEYS) do keys[k] = true end
    return keys
end

-- The modules this character does not have (those of another class) are left as they were.
local function Write(profile)
    profile.modules = profile.modules or {}
    profile.classes = profile.classes or {}
    local own = {}
    for _, m in ipairs(TW.order) do
        if m ~= mod then
            local saved = { values = {} }
            if not m.alwaysEnabled then saved.enabled = m.state.enabled and true or false end
            if not m.accountWide then
                for key in pairs(Keys(m)) do
                    if CLASS_KEYS[key] then
                        own[m.key] = own[m.key] or {}
                        own[m.key][key] = Copy(m.db[key])
                    else
                        saved.values[key] = Copy(m.db[key])
                    end
                end
            end
            profile.modules[m.key] = saved
        end
    end
    profile.classes[class] = own
    profile.configSize = Copy(TinkerwiseCharDB.configSize)
end

local function Read(profile)
    -- First the modules to turn off, while they still have their settings: they give back what they
    -- changed in the game.
    for _, m in ipairs(TW.order) do
        local saved = profile.modules[m.key]
        if m ~= mod and saved and saved.enabled == false and m.active then TW:SetModuleEnabled(m, false) end
    end
    local own = profile.classes[class]
    for _, m in ipairs(TW.order) do
        local saved = profile.modules[m.key]
        if m ~= mod and saved then
            if saved.enabled ~= nil and not m.alwaysEnabled then m.state.enabled = saved.enabled end
            if not m.accountWide then
                for key in pairs(Keys(m)) do
                    if CLASS_KEYS[key] then
                        -- Saved by another class: yours stays.
                        if own then m.db[key] = Copy(own[m.key] and own[m.key][key]) end
                    else
                        local value = saved.values[key]
                        -- An option newer than the profile keeps its value; an unsaved position or list
                        -- goes back to the original one.
                        if value ~= nil then
                            m.db[key] = Copy(value)
                        elseif not (m.defaults and m.defaults[key] ~= nil) then
                            m.db[key] = nil
                        end
                    end
                end
            end
        end
    end
    TinkerwiseCharDB.configSize = Copy(profile.configSize)
end

local names = {} -- values of the drop-down list

local function UpdateNames()
    wipe(names)
    for name in pairs(Store()) do names[#names + 1] = { name, name } end
    table.sort(names, function(a, b) return a[1]:lower() < b[1]:lower() end)
    if not Store()[mod.db.selected] then mod.db.selected = names[1] and names[1][1] or "" end
    if #names == 0 then names[1] = { "", L["No profile yet"] } end
    TW:RefreshConfig()
end

-- The selected profile, or nil with a message.
local function Selected()
    local name = mod.db.selected
    local profile = Store()[name]
    if not profile then
        TW:Print(L["no profile selected."])
        return
    end
    return profile, name
end

local function Create()
    local name = strtrim(mod.db.name or "")
    if name == "" then
        TW:Print(L["give the profile a name."])
    elseif Store()[name] then
        TW:Print(format(L["the profile \"%s\" already exists: select it and update it."], name))
    else
        local profile = {}
        Write(profile)
        Store()[name] = profile
        mod.db.selected, mod.db.name = name, ""
        UpdateNames()
        TW:Print(format(L["profile \"%s\" saved."], name))
    end
end

local function Load()
    local profile = Selected()
    if not profile then return end
    if InCombatLockdown() then
        TW:Print(L["cannot apply settings in combat."])
        return
    end
    Read(profile)
    ReloadUI() -- every module starts again from its new settings
end

local function Update()
    local profile, name = Selected()
    if not profile then return end
    Write(profile)
    TW:Print(format(L["profile \"%s\" saved."], name))
end

local function Delete()
    local _, name = Selected()
    if not name then return end
    Store()[name] = nil
    UpdateNames()
    TW:Print(format(L["profile \"%s\" deleted."], name))
end

mod = TW:NewModule("Profiles", {
    title = L["Profiles"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    section = "Configuration",
    alwaysEnabled = true,
    desc = L["Saves this character's options, modules turned on or off and window positions under a name, to find them again later or give them to another character. Loading a profile replaces the current settings and reloads the interface. The settings shared by the whole account are not part of it."],
    defaults = { selected = "", name = "" },
    options = {
        { type = "header", label = L["Saved profiles"] },
        { type = "select", key = "selected", label = L["Profile"], values = names },
        { type = "execute", label = L["Load"], confirm = true, func = Load },
        { type = "execute", label = L["Update with my settings"], confirm = true, func = Update },
        { type = "execute", label = L["Delete"], confirm = true, func = Delete },
        { type = "header", label = L["New profile"] },
        { type = "input", key = "name", label = L["Profile name"], live = true },
        { type = "execute", label = L["Save my settings"], func = Create },
    },
})

function mod:OnEnable()
    UpdateNames()
end
