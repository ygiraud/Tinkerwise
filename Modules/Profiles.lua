-- Profiles: named settings and window positions, shared by the account. Each character uses its own
-- settings or a profile; everything changed while using a profile is saved in it at logout, and the
-- other characters using it find it when they log in.
--
-- Only what the player sets is saved, never what the modules keep for themselves (chat history, tabs
-- created, the game's values to give back...). The settings shared by the whole account stay out of it.

local _, ns = ...
local L = ns.L
local TW = ns.TW

-- Saved by the windows, on top of the options and defaults of each module.
local POSITION_KEYS = { "point", "x", "y", "winPoint", "winX", "winY", "btnPoint", "btnX", "btnY", "sizes" }
-- Hold the names of spells: kept for each class.
local CLASS_KEYS = { skipGroups = true, skipSpells = true, skipBuffs = true }
-- Their options are only made once the modules run.
local CLASS_MODULES = { ClassBar = { "skipGroups", "skipSpells" }, Courtesy = { "skipBuffs" } }

-- Never copied: what destroys items is chosen on each character.
local EXCLUDED = { SoulShards = { destroy = true } }

local _, class = UnitClass("player")
local mod

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
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
    for _, k in ipairs(CLASS_MODULES[m.key] or {}) do keys[k] = true end
    for k in pairs(EXCLUDED[m.key] or {}) do keys[k] = nil end
    return keys
end

local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- Whether a saved value suits the option: a profile may come from another version or another player.
local function Valid(m, key, value)
    for _, opt in ipairs(m.options or {}) do
        if opt.key == key then
            if opt.type == "toggle" then return type(value) == "boolean" end
            if opt.type == "slider" then return type(value) == "number" and value >= opt.min and value <= opt.max end
            if opt.type == "checklist" then return type(value) == "table" end
            if opt.type == "input" then return type(value) == "string" end
            if opt.type == "color" then
                return type(value) == "table" and type(value.r) == "number" and type(value.g) == "number" and type(value.b) == "number"
            end
            if opt.type == "select" then
                for _, v in ipairs(opt.values) do
                    if v[1] == value then return true end
                end
                return false
            end
        end
    end
    if CLASS_KEYS[key] then return type(value) == "table" end
    if key:lower():find("point") then return POINTS[value] == true end
    if key == "sizes" then return type(value) == "table" end
    if key == "x" or key == "y" or key:find("[XY]$") then return type(value) == "number" end
    local default = m.defaults and m.defaults[key]
    return default == nil or type(default) == type(value)
end

-- The modules and options this character does not have (those of another class) are left as they were.
local function Write(profile)
    profile.modules = profile.modules or {}
    profile.classes = profile.classes or {}
    local own = {}
    for _, m in ipairs(TW.order) do
        if m ~= mod then
            local saved = profile.modules[m.key] or {}
            saved.values = saved.values or {}
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

-- What a profile gives to a module: the keys to change and their new value (nil: forgotten).
local function Changes(m, profile)
    local saved = profile.modules[m.key]
    if m == mod or not saved or m.accountWide then return {}, {} end
    local own = profile.classes[class]
    local keys, values = {}, {}
    local function Set(key, value)
        -- An unsaved position or list goes back to the original one.
        if value == nil and m.defaults then value = m.defaults[key] end
        if Same(m.db[key], value) then return end
        keys[#keys + 1] = key
        values[key] = Copy(value)
    end
    for key in pairs(Keys(m)) do
        if CLASS_KEYS[key] then
            -- Saved by another class: yours stays.
            local list = own and own[m.key] and own[m.key][key]
            if own and (list == nil or Valid(m, key, list)) then Set(key, list) end
        else
            local value = saved.values[key]
            if value ~= nil then
                if Valid(m, key, value) then Set(key, value) end
            elseif not (m.defaults and m.defaults[key] ~= nil) then
                Set(key, nil) -- an option newer than the profile keeps its value
            end
        end
    end
    return keys, values
end

-- At login, before the modules start.
local function Read(profile)
    for _, m in ipairs(TW.order) do
        local saved = profile.modules[m.key]
        if m ~= mod and saved then
            if saved.enabled ~= nil and not m.alwaysEnabled then m.state.enabled = saved.enabled end
            local keys, values = Changes(m, profile)
            for _, key in ipairs(keys) do m.db[key] = values[key] end
        end
    end
    TinkerwiseCharDB.configSize = Copy(profile.configSize)
end

-- While playing: only the modules the profile changes stop and start again, so that they give back
-- what they had changed in the game and take everything from their new settings.
local function Apply(profile)
    for _, m in ipairs(TW.order) do
        local saved = profile.modules[m.key]
        if m ~= mod and saved then
            local wanted = m.state.enabled and true or false
            if saved.enabled ~= nil and not m.alwaysEnabled then wanted = saved.enabled end
            local keys, values = Changes(m, profile)
            if #keys > 0 or wanted ~= (m.active or false) then
                local live = m.active and wanted and (m.OnProfileChanged or m.alwaysEnabled)
                local ok, err = pcall(function()
                    if m.active and not live then TW:SetModuleEnabled(m, false) end
                end)
                if not ok then geterrorhandler()(err) end
                for _, key in ipairs(keys) do m.db[key] = values[key] end
                ok, err = pcall(function()
                    if not live then
                        TW:SetModuleEnabled(m, wanted)
                    elseif m.OnProfileChanged then
                        m:OnProfileChanged()
                    elseif m.OnEnable then
                        m:OnEnable()
                    end
                end)
                if not ok then geterrorhandler()(err) end
            end
        end
    end
end

local names = {}    -- values of the drop-down lists
local newNames, copyNames, savedNames = {}, {}, {}

-- The default profile is always there: the original settings until a character uses it and changes them.
local DEFAULT = "*default*"
local ORIGINAL = "*original*" -- what a character can copy to start again
local OWN = ""                -- no profile: the character's own settings

local function DefaultProfile()
    local profile = { modules = {}, classes = { [class] = {} } }
    for _, m in ipairs(TW.order) do
        if m ~= mod then
            local saved = { values = {} }
            if not m.alwaysEnabled then saved.enabled = true end
            for key in pairs(Keys(m)) do
                if m.defaults and not CLASS_KEYS[key] then saved.values[key] = Copy(m.defaults[key]) end
            end
            profile.modules[m.key] = saved
        end
    end
    return profile
end

local function Get(name)
    if name == ORIGINAL then return DefaultProfile() end
    return name and (Store()[name] or name == DEFAULT and DefaultProfile()) or nil
end

local function Label(name)
    if name == OWN then return L["This character's own settings"] end
    if name == ORIGINAL then return L["Original settings"] end
    return name == DEFAULT and L["Default"] or name
end

-- The profile this character uses.
local function Current()
    local name = TinkerwiseCharDB.profile
    return name and Get(name) and name or OWN
end

-- Saves the settings where they belong, before others replace them and at logout.
local function Save()
    local name = Current()
    if name == OWN then
        TinkerwiseCharDB.ownProfile = {}
        Write(TinkerwiseCharDB.ownProfile)
    else
        local profile = Get(name)
        Write(profile)
        Store()[name] = profile
    end
end

local ready = false -- nothing is saved over a profile that could not be read

-- The renames done by the account, in order, for the characters that still know the old names.
local function Renames()
    TinkerwiseDB.profileRenames = TinkerwiseDB.profileRenames or {}
    return TinkerwiseDB.profileRenames
end

local function FollowRenames()
    local list = Renames()
    for i = (TinkerwiseCharDB.profileRenames or 0) + 1, #list do
        if TinkerwiseCharDB.profile == list[i].old then TinkerwiseCharDB.profile = list[i].new end
    end
    TinkerwiseCharDB.profileRenames = #list
end

-- Called by Core.lua before the modules start.
function ns.LoadProfile()
    FollowRenames()
    local new = TinkerwiseDB.newProfile
    if TW.newCharacter and UnitLevel("player") == 1 and new and Get(new) then
        TinkerwiseCharDB.profile = new
        TW:Print(format(L["profile \"%s\" applied to this new character."], Label(new)))
    end
    local name = Current()
    if name ~= OWN then
        local profile = Get(name)
        -- Turned off by another character: started first, to give back what it had changed in the game.
        for _, m in ipairs(TW.order) do
            local saved = profile.modules[m.key]
            if m ~= mod and saved and saved.enabled == false and not m.alwaysEnabled and m.state.enabled then
                TW:SetModuleEnabled(m, true)
                TW:SetModuleEnabled(m, false)
            end
        end
        Read(profile)
    else
        TinkerwiseCharDB.profile = nil
    end
    ready = true
end

local logout = CreateFrame("Frame")
logout:RegisterEvent("PLAYER_LOGOUT")
logout:SetScript("OnEvent", function()
    if ready and Current() ~= OWN then Save() end
end)

local function UpdateNames()
    local db = mod.db
    local current = Current()
    local function Entry(name) return { name, Label(name) } end
    local saved = {}
    for name in pairs(Store()) do
        if name ~= DEFAULT then saved[#saved + 1] = name end
    end
    table.sort(saved, function(a, b) return a:lower() < b:lower() end)

    for _, list in ipairs({ names, newNames, copyNames, savedNames }) do wipe(list) end
    names[1] = Entry(OWN)
    names[2] = Entry(DEFAULT)
    newNames[1] = { "", L["None"] }
    newNames[2] = { DEFAULT, Label(DEFAULT) }
    copyNames[1] = { ORIGINAL, Label(ORIGINAL) }
    copyNames[2] = { DEFAULT, Label(DEFAULT) }
    if current ~= OWN and TinkerwiseCharDB.ownProfile then copyNames[#copyNames + 1] = Entry(OWN) end
    for _, name in ipairs(saved) do
        names[#names + 1] = Entry(name)
        newNames[#newNames + 1] = { name, name }
        copyNames[#copyNames + 1] = { name, name }
        savedNames[#savedNames + 1] = { name, name }
    end

    db.selected = current
    local found = false
    for _, v in ipairs(copyNames) do found = found or v[1] == db.copyFrom end
    if not found then db.copyFrom = ORIGINAL end
    if db.toDelete == DEFAULT or not Store()[db.toDelete] then db.toDelete = saved[1] or "" end
    if #saved == 0 then savedNames[1] = { "", L["None"] } end
    local new = TinkerwiseDB.newProfile
    if new and not Get(new) then
        new = nil
        TinkerwiseDB.newProfile = nil
    end
    db.newCharacters = new or "" -- the choice is the account's
    TW:RefreshConfig()
end

-- The profile in use, up to date.
local function Selected()
    local name = Current()
    if name ~= OWN then
        Save()
        return Get(name), name
    end
    local profile = {}
    Write(profile)
    return profile, UnitName("player")
end

local function FreeName(name)
    if name == "" then
        TW:Print(L["give the profile a name."])
    elseif name == ORIGINAL or Get(name) or name:lower() == Label(DEFAULT):lower() then
        TW:Print(format(L["the profile \"%s\" already exists."], name))
    else
        return true
    end
end

local function Create()
    local name = strtrim(mod.db.name or "")
    if FreeName(name) then
        Save()
        local profile = {}
        Write(profile)
        Store()[name] = profile
        TinkerwiseCharDB.profile = name
        mod.db.name = ""
        UpdateNames()
        TW:Print(format(L["this character now uses the profile \"%s\": your changes are saved in it."], name))
    end
end

local function Rename()
    local old, name = Current(), strtrim(mod.db.newName or "")
    if old == OWN or old == DEFAULT then
        TW:Print(L["this profile cannot be renamed."])
    elseif FreeName(name) then
        Store()[name], Store()[old] = Store()[old], nil
        local list = Renames()
        list[#list + 1] = { old = old, new = name }
        TinkerwiseCharDB.profileRenames = #list
        TinkerwiseCharDB.profile = name
        if TinkerwiseDB.newProfile == old then TinkerwiseDB.newProfile = name end
        mod.db.newName = ""
        UpdateNames()
        TW:Print(format(L["profile \"%s\" renamed to \"%s\"."], old, name))
    end
end

local function CanApply()
    if not InCombatLockdown() then return true end
    TW:Print(L["cannot apply settings in combat."])
end

local function Use(name)
    if name ~= Current() and CanApply() then
        local profile = Get(name)
        if name == OWN then profile = TinkerwiseCharDB.ownProfile end
        Save()
        TinkerwiseCharDB.profile = name ~= OWN and name or nil
        if profile then Apply(profile) end -- no settings of its own yet: these become so
    end
    UpdateNames()
end

-- The current settings become a copy of another profile.
local function CopyFrom()
    local name = mod.db.copyFrom
    local profile = Get(name)
    if name == OWN then profile = TinkerwiseCharDB.ownProfile end
    if not profile or name == Current() or not CanApply() then return end
    Apply(profile)
    UpdateNames()
    TW:Print(format(L["settings copied from \"%s\"."], Label(name)))
end

-- The characters using it keep their settings, as their own.
local function Delete()
    local name = mod.db.toDelete
    if name == DEFAULT or not Store()[name] then return end
    if name == Current() then
        TinkerwiseCharDB.profile = nil
    end
    Store()[name] = nil
    UpdateNames()
    TW:Print(format(L["profile \"%s\" deleted."], name))
end

---------------------------------------------------------------------------
-- Export and import: a text made of the profile, to copy and paste
---------------------------------------------------------------------------

local TEXT_PREFIX = "TW1:"
local MAX_TEXT = 200000
local codec = C_EncodingUtil

local box
local function TextWindow(heading, text, onAccept)
    if not box then
        box = CreateFrame("Frame", "TinkerwiseProfileText", UIParent, "BackdropTemplate")
        box:SetSize(480, 300)
        box:SetPoint("CENTER")
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box:EnableMouse(true)
        box:Hide()
        box.title = TW:SkinDialog(box, L["Profiles"])
        tinsert(UISpecialFrames, "TinkerwiseProfileText")
        local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 24, -40)
        scroll:SetPoint("BOTTOMRIGHT", -44, 52)
        box.edit = CreateFrame("EditBox", nil, scroll)
        box.edit:SetMultiLine(true)
        box.edit:SetAutoFocus(false)
        box.edit:SetFontObject("ChatFontNormal")
        box.edit:SetWidth(400)
        box.edit:SetScript("OnEscapePressed", function() box:Hide() end)
        scroll:SetScrollChild(box.edit)
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function() box.edit:SetFocus() end)
        box.accept = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        box.accept:SetSize(140, 22)
        box.accept:SetPoint("BOTTOMRIGHT", -24, 20)
        box.accept:SetText(L["Import"])
        box.accept:SetScript("OnClick", function()
            if box.onAccept(box.edit:GetText()) then box:Hide() end
        end)
    end
    box.title:SetText(heading)
    box.onAccept = onAccept
    box.accept:SetShown(onAccept ~= nil)
    box.edit:SetText(text)
    box:Show()
    box.edit:SetFocus()
    if text ~= "" then box.edit:HighlightText() end
end

local function Export()
    local profile, name = Selected()
    if not profile then return end
    local ok, text = pcall(function()
        return codec.EncodeBase64(codec.CompressString(codec.SerializeCBOR({ name = Label(name), profile = profile })))
    end)
    if not ok or not text then
        TW:Print(L["the profile could not be exported."])
        return
    end
    TextWindow(format(L["Copy with Ctrl + C: %s"], Label(name)), TEXT_PREFIX .. text)
end

-- Only the parts a profile is made of; their values are checked when it is loaded.
local function Clean(profile)
    if type(profile) ~= "table" or type(profile.modules) ~= "table" then return end
    local clean = { modules = {}, classes = {} }
    for key, saved in pairs(profile.modules) do
        if type(key) == "string" and type(saved) == "table" and type(saved.values) == "table" then
            local enabled
            if type(saved.enabled) == "boolean" then enabled = saved.enabled end
            saved.values.sizes = nil -- the windows of somebody else's chat
            clean.modules[key] = { enabled = enabled, values = saved.values }
        end
    end
    for key, own in pairs(type(profile.classes) == "table" and profile.classes or {}) do
        if type(key) == "string" and type(own) == "table" then
            local list = {}
            for module, values in pairs(own) do
                if type(values) == "table" then list[module] = values end
            end
            clean.classes[key] = list
        end
    end
    return clean
end

local function ImportText(text)
    text = text:gsub("%s", "")
    local data
    if text:sub(1, #TEXT_PREFIX) == TEXT_PREFIX and #text <= MAX_TEXT then
        local ok, value = pcall(function()
            return codec.DeserializeCBOR(codec.DecompressString(codec.DecodeBase64(text:sub(#TEXT_PREFIX + 1))))
        end)
        data = ok and value
    end
    local profile = type(data) == "table" and Clean(data.profile)
    if not profile then
        TW:Print(L["this text is not a Tinkerwise profile."])
        return false
    end
    local base = type(data.name) == "string" and strtrim((data.name:gsub("[|%c]", ""))):sub(1, 60) or ""
    if base == "" then base = L["Profile"] end
    local name, n = base, 1
    while Get(name) or name:lower() == Label(DEFAULT):lower() do
        n = n + 1
        name = format("%s (%d)", base, n)
    end
    Store()[name] = profile
    UpdateNames()
    TW:Print(format(L["profile \"%s\" imported."], name))
    return true
end

local function Import()
    TextWindow(L["Paste with Ctrl + V"], "", ImportText)
end

mod = TW:NewModule("Profiles", {
    title = L["Profiles"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    section = "Configuration",
    alwaysEnabled = true,
    desc = L["A profile holds the options, the modules turned on or off and the window positions. Everything you change while using a profile is saved in it, and shared by all the characters using it. The settings shared by the whole account are not part of it. A profile picked in the list is applied at once."]
        .. " " .. L["The default profile cannot be deleted."]
        .. " " .. L["A profile can be given to new characters, or exported as a text to share."],
    defaults = { selected = OWN, copyFrom = ORIGINAL, toDelete = "", name = "", newName = "", newCharacters = "" },
    options = {
        { type = "header", label = L["Profile in use"] },
        { type = "select", key = "selected", label = L["Profile"], values = names },
        { type = "input", key = "newName", label = L["New name"], live = true },
        { type = "execute", label = L["Rename"], func = Rename },
        { type = "header", label = L["New profile"] },
        { type = "input", key = "name", label = L["Profile name"], live = true },
        { type = "execute", label = L["Create from my settings"], func = Create },
        { type = "header", label = L["Copy a profile"] },
        { type = "select", key = "copyFrom", label = L["Copy from"], values = copyNames },
        { type = "execute", label = L["Copy into my settings"], confirm = true, func = CopyFrom },
        { type = "header", label = L["Delete a profile"] },
        { type = "select", key = "toDelete", label = L["Profile to delete"], values = savedNames },
        { type = "execute", label = L["Delete"], confirm = true, func = Delete },
        { type = "header", label = L["New characters"] },
        { type = "select", key = "newCharacters", label = L["Profile given to new characters (level 1)"], values = newNames },
    },
})

if codec and codec.SerializeCBOR and codec.CompressString and codec.EncodeBase64 then
    table.insert(mod.options, 5, { type = "execute", label = L["Export"], func = Export })
    table.insert(mod.options, 6, { type = "execute", label = L["Import"], func = Import })
end

function mod:OnEnable()
    UpdateNames()
end

function mod:OnOptionChanged(key)
    if key == "selected" then Use(self.db.selected) end
    if key == "newCharacters" then
        local name = self.db.newCharacters
        TinkerwiseDB.newProfile = name ~= "" and name or nil
    end
end
