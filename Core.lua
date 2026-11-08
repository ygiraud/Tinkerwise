-- Tinkerwise core: module registry, saved variables and enable/disable handling.
--
-- A module is declared with TW:NewModule(key, info) where info may contain:
--   title, desc        shown in the configuration window
--   section            group name in the module list (default "Misc")
--   icon               texture path shown in the configuration window
--   defaults           table of saved settings (copied into mod.db)
--   alwaysEnabled      true for a module that is always on and cannot be disabled (default: starts disabled)
--   accountWide        true to share settings between characters (default: per character)
--   perCharacterToggle with accountWide: settings stay shared, but each character turns the module on or off
--   options            list of option widgets (see Config.lua)
--   replaces           { oldModuleKey = optionKey } older modules it took over, see ADDON_LOADED
--   OnEnable, OnDisable, OnOptionChanged(key)   callbacks
--   SetEditMode(on)    unlock / lock the module's movable frames

local ADDON, ns = ...
local L = ns.L

local TW = { modules = {}, order = {}, commands = {} } -- commands: "/tw name" -> function(arguments)
ns.TW = TW
_G.Tinkerwise = TW

-- Game functions that recent clients moved into C_ namespaces. Modules alias these locally.
local C_Item, C_Spell, C_UnitAuras = _G.C_Item or {}, _G.C_Spell or {}, _G.C_UnitAuras or {}

local function AuraValues(aura)
    if not aura then return end
    return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration,
        aura.expirationTime, aura.sourceUnit, aura.isStealable, aura.nameplateShowPersonal, aura.spellId
end

ns.API = {
    GetItemInfo = _G.GetItemInfo or C_Item.GetItemInfo,
    GetItemInfoInstant = _G.GetItemInfoInstant or C_Item.GetItemInfoInstant,
    GetItemCount = _G.GetItemCount or C_Item.GetItemCount,
    GetItemSpell = _G.GetItemSpell or C_Item.GetItemSpell,
    GetItemIcon = _G.GetItemIcon or C_Item.GetItemIconByID,
    GetSpellTexture = _G.GetSpellTexture or C_Spell.GetSpellTexture,
    PickupItem = _G.C_Item and _G.C_Item.PickupItem or _G.PickupItem,
    -- C_CurrencyInfo first: on Forever the global still has a name but fails when called.
    GetCoinTextureString = _G.C_CurrencyInfo and _G.C_CurrencyInfo.GetCoinTextureString or _G.GetCoinTextureString,
    GetSpellInfo = _G.GetSpellInfo or function(spell)
        local info = C_Spell.GetSpellInfo(spell)
        if info then
            return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
        end
    end,
    UnitBuff = _G.UnitBuff or function(unit, index)
        return AuraValues(C_UnitAuras.GetBuffDataByIndex(unit, index))
    end,
    ContainerNumSlots = _G.C_Container and _G.C_Container.GetContainerNumSlots or _G.GetContainerNumSlots,
    -- itemID, stackCount, quality, hasNoValue of a bag slot (new and old APIs).
    ContainerItem = function(bag, slot)
        if C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then return info.itemID, info.stackCount, info.quality, info.hasNoValue end
            return
        end
        local _, count, _, quality, _, _, _, _, noValue, id = GetContainerItemInfo(bag, slot)
        return id, count, quality, noValue
    end,
}

-- "OPTIONS" -> "O P T I O N S" (UTF-8 aware)
function ns.Spaced(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return table.concat(out, " ")
end

function TW:Print(text)
    print("|cff33ccffTinkerwise|r: " .. text)
end

-- On WoW Forever characters have a main and a secondary name, and only both together are unique.
-- UnitFullName gives that second name there, and the realm on the other clients.
function TW:PlayerName()
    local name, second = UnitFullName("player")
    name = name or UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if second and second ~= "" and second ~= realm then return name .. " " .. second end
    return name
end

function TW:NewModule(key, info)
    local mod = info or {}
    mod.key = key
    self.modules[key] = mod
    self.order[#self.order + 1] = mod
    return mod
end

function TW:SetModuleEnabled(mod, enabled)
    if mod.alwaysEnabled then enabled = true end
    mod.state.enabled = enabled and true or false
    if enabled and not mod.active then
        mod.active = true
        if mod.OnEnable then
            -- A failing module must not stop the next ones from starting.
            local ok, err = pcall(mod.OnEnable, mod)
            if not ok then
                mod.active = false
                self:Print(format(L["the \"%s\" module could not start."], mod.title or mod.key))
                geterrorhandler()(err)
                return
            end
        end
        if self.editMode and mod.SetEditMode then mod:SetEditMode(true) end
    elseif not enabled and mod.active then
        mod.active = false
        if mod.OnDisable then mod:OnDisable() end
    end
end

function TW:SetOption(mod, key, value)
    mod.db[key] = value
    if mod.active and mod.OnOptionChanged then mod:OnOptionChanged(key) end
end

-- The dialog background texture is see-through whatever its color: this solid layer sits under it.
function TW:AddSolidBackground(frame, r, g, b)
    local solid = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetColorTexture(r, g, b, 0.96)
    solid:SetPoint("TOPLEFT", 11, -12)
    solid:SetPoint("BOTTOMRIGHT", -12, 11)
end

-- Classic dialog look: stone background, gold border, title on a header banner and a close button.
-- `frame` must be created with "BackdropTemplate". Returns the title font string.
function TW:SkinDialog(frame, title)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    self:AddSolidBackground(frame, 0.08, 0.08, 0.08)
    frame:SetToplevel(true) -- comes in front as a whole when shown or clicked
    local header = frame:CreateTexture(nil, "OVERLAY")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(300, 64)
    header:SetPoint("TOP", 0, 12)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", header, "TOP", 0, -14)
    text:SetText(title)
    header:SetWidth(math.max(220, text:GetStringWidth() + 140))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    return text
end

-- Round button with the minimap button border (same look as most addon minimap buttons).
function TW:CreateRoundButton(name, parent, iconPath)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(iconPath)
    b.icon:SetSize(17, 17)
    b.icon:SetPoint("TOPLEFT", 7, -6)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    return b
end

-- Makes `frame` draggable through a blue overlay, saving its position in db.point/x/y
-- (`default` holds the point/x/y used by ResetPosition).
-- Adds frame:ApplyPosition(), frame:ToggleMover() (returns true when unlocked), frame:ResetPosition(),
-- frame:IsUnlocked().
function TW:CreateMover(frame, getDB, label, default)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:Hide()
    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0.6, 1, 0.4)
    local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
    text:SetText(label or L["Drag to move"])

    overlay:SetScript("OnDragStart", function() frame:StartMoving() end)
    overlay:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local db = getDB()
        local point, _, _, x, y = frame:GetPoint()
        db.point, db.x, db.y = point, x, y
    end)

    function frame:ApplyPosition()
        local db = getDB()
        self:ClearAllPoints()
        self:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    end
    function frame:ResetPosition()
        local db = getDB()
        db.point, db.x, db.y = default.point, default.x, default.y
        self:ApplyPosition()
    end
    function frame:ToggleMover()
        overlay:SetShown(not overlay:IsShown())
        return overlay:IsShown()
    end
    function frame:IsUnlocked() return overlay:IsShown() end
    function frame:Lock() overlay:Hide() end
    function frame:SetUnlocked(on) overlay:SetShown(on) end
end

-- Edit mode: unlocks the frames of all active modules at once (see mod:SetEditMode).
local editBar

local function BuildEditBar()
    editBar = CreateFrame("Frame", "TinkerwiseEditBar", UIParent, "BackdropTemplate")
    editBar:SetSize(380, 44)
    editBar:SetPoint("TOP", 0, -60)
    editBar:SetFrameStrata("DIALOG")
    editBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    editBar:SetBackdropColor(0.06, 0.04, 0.02, 0.95)
    editBar:SetBackdropBorderColor(1, 0.82, 0, 1)
    local text = editBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 14, 0)
    text:SetText(L["Move windows: drag them"])
    local done = CreateFrame("Button", nil, editBar, "UIPanelButtonTemplate")
    done:SetSize(90, 22)
    done:SetPoint("RIGHT", -10, 0)
    done:SetText(L["Finish"])
    done:SetScript("OnClick", function() TW:SetEditMode(false) end)
end

function TW:SetEditMode(on)
    if on and InCombatLockdown() then
        return self:Print(L["cannot move windows in combat."])
    end
    self.editMode = on and true or false
    for _, mod in ipairs(self.order) do
        if mod.active and mod.SetEditMode then mod:SetEditMode(self.editMode) end
    end
    if not editBar then BuildEditBar() end
    editBar:SetShown(self.editMode)
    if self.editMode and TinkerwiseConfigFrame then TinkerwiseConfigFrame:Hide() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_DISABLED" then
        if TW.editMode then
            TW:SetEditMode(false)
            TW:Print(L["window moving ended: you entered combat."])
        end
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        TinkerwiseDB = TinkerwiseDB or {}
        TinkerwiseDB.modules = TinkerwiseDB.modules or {}
        TinkerwiseCharDB = TinkerwiseCharDB or {}
        TinkerwiseCharDB.modules = TinkerwiseCharDB.modules or {}
        -- A module that took over older ones starts from their settings: their on/off choice becomes
        -- one of its options, and it is on if any of them was.
        local charModules = TinkerwiseCharDB.modules
        for _, mod in ipairs(TW.order) do
            for oldKey, option in pairs(mod.replaces or {}) do
                local old = charModules[oldKey]
                if old then
                    local db = charModules[mod.key] or {}
                    charModules[mod.key] = db
                    db[option] = old.enabled and true or false
                    db.enabled = db.enabled or old.enabled
                    for k, v in pairs(old) do
                        if db[k] == nil then db[k] = v end
                    end
                end
            end
        end
        -- Forget the settings of modules that no longer exist.
        for _, store in ipairs({ TinkerwiseDB.modules, TinkerwiseCharDB.modules }) do
            for key in pairs(store) do
                if not TW.modules[key] then store[key] = nil end
            end
        end
        for _, mod in ipairs(TW.order) do
            local store = TinkerwiseCharDB.modules
            if mod.accountWide then
                store = TinkerwiseDB.modules
            elseif TinkerwiseDB.modules[mod.key] then
                store[mod.key] = store[mod.key] or TinkerwiseDB.modules[mod.key]
                TinkerwiseDB.modules[mod.key] = nil
            end
            local db = store[mod.key] or {}
            store[mod.key] = db
            for k, v in pairs(mod.defaults or {}) do
                if db[k] == nil then db[k] = v end
            end
            -- Where the on/off choice is saved. A character seen for the first time since the
            -- module became per character keeps the choice the account had until then.
            local state = db
            if mod.perCharacterToggle then
                state = TinkerwiseCharDB.modules[mod.key]
                if not state then
                    state = { enabled = db.enabled, defaultApplied = db.defaultApplied }
                    TinkerwiseCharDB.modules[mod.key] = state
                end
            end
            -- Modules start off once, even if saved as on; then the player's choice stays.
            if mod.alwaysEnabled then
                state.enabled = true
            elseif not state.defaultApplied then
                state.enabled, state.defaultApplied = false, true
            end
            if state.enabled == nil then state.enabled = true end
            mod.db, mod.state = db, state
        end
        -- The minimap button position used to be saved outside its module, and account-wide
        -- before that (the first character to log in inherits it). Moved once, then removed.
        local oldMinimap = TinkerwiseCharDB.minimap or TinkerwiseDB.minimap
        if oldMinimap and oldMinimap.angle then TW.modules.MinimapButton.db.angle = oldMinimap.angle end
        TinkerwiseCharDB.minimap, TinkerwiseDB.minimap = nil, nil
    elseif event == "PLAYER_LOGIN" then
        for _, mod in ipairs(TW.order) do
            if mod.state.enabled then TW:SetModuleEnabled(mod, true) end
        end
    end
end)

SLASH_TINKERWISE1 = "/tinkerwise"
SLASH_TINKERWISE2 = "/tw"
SlashCmdList.TINKERWISE = function(input)
    local cmd, arguments = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "move" then
        TW:SetEditMode(not TW.editMode)
    elseif TW.commands[cmd] then
        TW.commands[cmd](arguments)
    else
        TW:ToggleConfig()
    end
end

-- Shortcut for /reload.
SLASH_TINKERWISERELOAD1 = "/rl"
SlashCmdList.TINKERWISERELOAD = function()
    ReloadUI()
end

-- Opens Blizzard's Edit Mode (not to be confused with /tw move, for the addon's own windows).
SLASH_TINKERWISEEDIT1 = "/edit"
SlashCmdList.TINKERWISEEDIT = function()
    if not EditModeManagerFrame then
        TW:Print(L["Blizzard's Edit Mode does not exist in this game version."])
    elseif InCombatLockdown() then
        TW:Print(L["cannot open Edit Mode in combat."])
    else
        ShowUIPanel(EditModeManagerFrame)
    end
end

-- Opens Blizzard's Quick Keybind Mode: hover an action button and press a key.
SLASH_TINKERWISEKEYBIND1 = "/kb"
SlashCmdList.TINKERWISEKEYBIND = function()
    if not QuickKeybindFrame then
        TW:Print(L["Quick Keybind Mode is not available."])
    elseif InCombatLockdown() then
        TW:Print(L["cannot open Quick Keybind Mode in combat."])
    else
        ShowUIPanel(QuickKeybindFrame)
    end
end

-- Opens or closes Blizzard's Click Casting window, which is loaded on demand.
SLASH_TINKERWISECLICKCAST1 = "/cc"
SlashCmdList.TINKERWISECLICKCAST = function()
    if InCombatLockdown() then
        TW:Print(L["cannot open Click Casting in combat."])
        return
    end
    if not ClickBindingFrame then
        local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        loadAddOn("Blizzard_ClickBindingUI")
    end
    if not ClickBindingFrame then
        TW:Print(L["Click Casting is not available."])
    elseif ClickBindingFrame:IsShown() then
        HideUIPanel(ClickBindingFrame)
    else
        ShowUIPanel(ClickBindingFrame)
    end
end
