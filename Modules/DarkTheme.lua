-- DarkTheme: darkens the game's frame art (unit frames, action bars, minimap, windows, tooltips).
-- The textures are only desaturated and tinted: nothing is moved, resized or replaced, so the
-- protected frames keep working in combat. Each texture's original look is kept and given back
-- when the module or a group of elements is turned off.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local CLASS_TINT = 0.45 -- class colors are darkened so the art stays dark

local mod, db

---------------------------------------------------------------------------
-- Textures
---------------------------------------------------------------------------

local original = {} -- texture -> { r, g, b, a, desaturated }
local groupOf = {}  -- texture -> group key of the option that covers it
local hookedTextures = {}
local applying = false

local function Tint()
    if db.classColor then
        local _, class = UnitClass("player")
        local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
        local c = class and colors and colors[class]
        if c then return c.r * CLASS_TINT, c.g * CLASS_TINT, c.b * CLASS_TINT end
    end
    local c = db.color
    return c.r, c.g, c.b
end

-- For the frames drawn by other modules (the square minimap border): the tint, or nil when that
-- group is not darkened.
function ns.DarkThemeTint(group)
    if not (mod and mod.active and db and db[group]) then return end
    return Tint()
end

local function Wanted(texture)
    return mod.active and db[groupOf[texture]]
end

local function Paint(texture)
    if not original[texture] then
        local r, g, b, a = texture:GetVertexColor()
        original[texture] = { r, g, b, a, texture:IsDesaturated() }
    end
    applying = true
    if Wanted(texture) then
        local r, g, b = Tint()
        local a = original[texture][4]
        texture:SetDesaturated(true)
        texture:SetVertexColor(r, g, b, a)
    else
        local o = original[texture]
        texture:SetDesaturated(o[5])
        texture:SetVertexColor(o[1], o[2], o[3], o[4])
    end
    applying = false
end

-- The game sets some of these colors again (target classification, flashes): the tint comes back.
local function OnColorSet(texture)
    if applying or not Wanted(texture) then return end
    Paint(texture)
end

local function Darken(texture, group)
    if type(texture) ~= "table" or not texture.GetObjectType or texture:GetObjectType() ~= "Texture" then return end
    if texture.IsForbidden and texture:IsForbidden() then return end
    groupOf[texture] = group
    if not hookedTextures[texture] then
        hookedTextures[texture] = true
        hooksecurefunc(texture, "SetVertexColor", OnColorSet)
        if texture.SetAtlas then hooksecurefunc(texture, "SetAtlas", OnColorSet) end
        if texture.SetDesaturated then hooksecurefunc(texture, "SetDesaturated", OnColorSet) end
    end
    Paint(texture)
end

-- "PlayerFrame.PlayerFrameContainer.FrameTexture" -> the object, or nil when it doesn't exist here.
local function Find(path)
    local object = _G
    for part in path:gmatch("[^.]+") do
        object = type(object) == "table" and object[part]
        if not object then return end
    end
    return object
end

local function DarkenPaths(paths, group)
    for _, path in ipairs(paths) do Darken(Find(path), group) end
end

-- Every texture of a frame's border (the NineSlice pieces of the recent windows).
local function DarkenRegions(frame, group)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then Darken(region, group) end
    end
end

---------------------------------------------------------------------------
-- What each group covers
---------------------------------------------------------------------------

local UNIT_FRAME_PATHS = {
    "PlayerFrame.PlayerFrameContainer.FrameTexture",
    "PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture",
    "PlayerFrame.PlayerFrameContainer.VehicleFrameTexture",
    "TargetFrame.TargetFrameContainer.FrameTexture",
    "TargetFrame.TargetFrameContainer.BossPortraitFrameTexture",
    "FocusFrame.TargetFrameContainer.FrameTexture",
    "FocusFrame.TargetFrameContainer.BossPortraitFrameTexture",
    "TargetFrameToT.FrameTexture",
    "FocusFrameToT.FrameTexture",
    "PetFrameTexture",
    "PetFrame.PetFrameTexture",
    "PlayerCastingBarFrame.Border",
    "TargetFrameSpellBar.Border",
    "FocusFrameSpellBar.Border",
}

local function DarkenUnitFrames()
    DarkenPaths(UNIT_FRAME_PATHS, "unitFrames")
    for i = 1, MAX_PARTY_MEMBERS or 4 do
        DarkenPaths({ "PartyFrame.Member" .. i .. ".Texture", "PartyFrame.Member" .. i .. ".PetFrame.Texture",
            "PartyMemberFrame" .. i .. "Texture" }, "unitFrames")
    end
end

local ACTION_BAR_PATHS = {
    "MainMenuBar.BorderArt", "MainMenuBar.EndCaps.LeftEndCap", "MainMenuBar.EndCaps.RightEndCap",
    "MainActionBar.BorderArt", "MainActionBar.EndCaps.LeftEndCap", "MainActionBar.EndCaps.RightEndCap",
    "MainMenuBarArtFrame.LeftEndCap", "MainMenuBarArtFrame.RightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
}

local BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
    "PetActionButton", "StanceButton",
}

local BAG_BUTTONS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot",
}

local function DarkenActionBars()
    DarkenPaths(ACTION_BAR_PATHS, "actionBars")
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, NUM_ACTIONBAR_BUTTONS or 12 do
            local button = _G[prefix .. i]
            if button and button.GetNormalTexture then Darken(button:GetNormalTexture(), "actionBars") end
        end
    end
    for _, name in ipairs(BAG_BUTTONS) do
        local button = _G[name]
        if button and button.GetNormalTexture then Darken(button:GetNormalTexture(), "actionBars") end
    end
end

local MINIMAP_PATHS = {
    "MinimapCompassTexture", "MinimapBorder", "MinimapBorderTop", "MinimapCluster.BorderTop",
    "MinimapCluster.Tracking.Background", "MinimapZoomIn.NormalTexture", "MinimapZoomOut.NormalTexture",
}

local function DarkenMinimap()
    DarkenPaths(MINIMAP_PATHS, "minimap")
    if ns.ColorMinimapBorder then ns.ColorMinimapBorder() end
end

-- Windows that exist at login, then those of the game's addons loaded later.
local WINDOWS = {
    "CharacterFrame", "PaperDollFrame", "SpellBookFrame", "FriendsFrame", "QuestFrame", "QuestLogFrame",
    "GossipFrame", "MerchantFrame", "MailFrame", "OpenMailFrame", "BankFrame", "PVEFrame", "LootFrame",
    "TradeFrame", "GameMenuFrame", "CommunitiesFrame", "CollectionsJournal", "DressUpFrame", "TaxiFrame",
    "ContainerFrameCombinedBags", "WorldMapFrame.BorderFrame", "SettingsPanel", "AddonList", "LFGParentFrame",
    "HelpFrame", "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "StaticPopup1",
    "StaticPopup2", "StaticPopup3", "StaticPopup4",
    -- loaded on demand
    "InspectFrame", "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "ProfessionsFrame",
    "TradeSkillFrame", "CraftFrame", "AuctionHouseFrame", "AuctionFrame", "MacroFrame", "ClassTrainerFrame",
    "FlightMapFrame.BorderFrame", "GuildFrame", "KeyBindingFrame", "WeeklyRewardsFrame", "ItemSocketingFrame",
}

-- The border of a window (with its portrait ring), its title bar and the border of its inner panel.
local WINDOW_PARTS = { "NineSlice", "Border", "TitleContainer", "TopTileStreaks", "Inset.NineSlice" }

local hookedWindows = {}

local function DarkenWindow(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    for _, part in ipairs(WINDOW_PARTS) do
        local object = frame
        for key in part:gmatch("[^.]+") do object = object and object[key] end
        if object and object.GetObjectType and object:GetObjectType() == "Texture" then
            Darken(object, "windows")
        elseif object then
            DarkenRegions(object, "windows")
        end
    end
    -- Classic-style windows draw their border with the frame's own textures (named ...TopLeft etc.).
    if frame.GetName and frame:GetName() and not frame.NineSlice then
        local name = frame:GetName()
        for _, suffix in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right",
            "TopLeftTexture", "TopRightTexture", "BotLeftTexture", "BotRightTexture" }) do
            Darken(_G[name .. suffix], "windows")
        end
    end
end

local function DarkenWindows()
    for _, path in ipairs(WINDOWS) do
        local frame = Find(path)
        if frame then
            DarkenWindow(frame)
            -- Some borders are built when the window first shows.
            if not hookedWindows[frame] and frame.HookScript then
                hookedWindows[frame] = true
                frame:HookScript("OnShow", function(self)
                    if mod.active and db.windows then DarkenWindow(self) end
                end)
            end
        end
    end
    for i = 1, NUM_CONTAINER_FRAMES or 13 do DarkenWindow(_G["ContainerFrame" .. i]) end
end

-- Tooltips: only the background gets darker; the border keeps the item quality color.
local tooltipHooked = false
local darkenedTooltips = {}
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }

local function DarkenTooltip(tooltip)
    if not (mod.active and db.tooltips) or not tooltip or not tooltip.NineSlice then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    darkenedTooltips[tooltip] = true
    local r, g, b = Tint()
    tooltip.NineSlice:SetCenterColor(r * 0.25, g * 0.25, b * 0.25, db.tooltipOpacity / 100)
end

local function DarkenTooltips()
    if not tooltipHooked then
        tooltipHooked = true
        if SharedTooltip_SetBackdropStyle then hooksecurefunc("SharedTooltip_SetBackdropStyle", DarkenTooltip) end
        for _, name in ipairs(TOOLTIPS) do
            if _G[name] and _G[name].HookScript then _G[name]:HookScript("OnShow", DarkenTooltip) end
        end
    end
    for _, name in ipairs(TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip and tooltip.NineSlice then
            if mod.active and db.tooltips then
                DarkenTooltip(tooltip)
            elseif darkenedTooltips[tooltip] and TOOLTIP_DEFAULT_BACKGROUND_COLOR then
                darkenedTooltips[tooltip] = nil
                local c = TOOLTIP_DEFAULT_BACKGROUND_COLOR
                tooltip.NineSlice:SetCenterColor(c.r, c.g, c.b, 1)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

local function Apply()
    DarkenUnitFrames()
    DarkenActionBars()
    DarkenMinimap()
    DarkenWindows()
    DarkenTooltips()
    -- Textures found earlier but no longer listed (another group switched off, module disabled).
    for texture in pairs(original) do Paint(texture) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and not (type(addon) == "string" and addon:match("^Blizzard_")) then return end
    Apply()
end)

mod = TW:NewModule("DarkTheme", {
    title = L["Dark Theme"],
    icon = "Interface\\Icons\\Spell_Shadow_Twilight",
    section = L["Interface"],
    desc = L["Darkens the game's frames: unit frames, action bars, minimap, windows and tooltips. Only their colors change: nothing is moved or replaced, so the game's frames work as usual, in combat too. Turning the module off gives them back their colors."],
    defaults = {
        color = { r = 0.3, g = 0.3, b = 0.3 },
        classColor = false,
        unitFrames = true, actionBars = true, minimap = true, windows = true,
        tooltips = true, tooltipOpacity = 90,
    },
    options = {
        { type = "header", label = L["Color"] },
        { type = "color", key = "color", label = L["Tint"] },
        { type = "toggle", key = "classColor", label = L["Tint with your class color"] },
        { type = "header", label = L["Elements"] },
        { type = "toggle", key = "unitFrames", label = L["Unit frames and cast bars"] },
        { type = "toggle", key = "actionBars", label = L["Action bars and bag buttons"] },
        { type = "toggle", key = "minimap", label = L["Minimap border"] },
        { type = "toggle", key = "windows", label = L["Windows (character, bags, spells, merchants...)"] },
        { type = "toggle", key = "tooltips", label = L["Tooltip background"] },
        { type = "slider", key = "tooltipOpacity", label = L["Tooltip opacity (%)"], min = 50, max = 100, step = 5 },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE") -- party frames are created when a group forms
    Apply()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    for texture in pairs(original) do Paint(texture) end
    if ns.ColorMinimapBorder then ns.ColorMinimapBorder() end
    DarkenTooltips()
end

function mod:OnOptionChanged()
    Apply()
end
