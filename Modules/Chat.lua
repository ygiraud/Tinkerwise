-- Chat: typing comfort, readability, copying the chat and automatic tabs by theme.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local HISTORY_SIZE = 50
local URL_PREFIX = "twurl:"
local COMBAT_LOG_INDEX = 2

local URL_EVENTS = {
    "SAY", "YELL", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER", "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM", "CHANNEL",
}

local SHORT_CHANNELS = {
    GUILD = L["G"], OFFICER = L["O"], PARTY = L["P"], RAID = L["R"],
}

local TABS = {
    { key = "tabGuild", name = L["Guild"], groups = { "GUILD", "OFFICER" } },
    { key = "tabGroup", name = L["Group"], groups = {
        "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER",
        "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    } },
}

local mod

-- CHAT_FRAMES also lists the temporary windows of whisper conversations.
local function ForEachWindow(func)
    if CHAT_FRAMES then
        for _, name in ipairs(CHAT_FRAMES) do
            if _G[name] then func(_G[name], _G[name]:GetID()) end
        end
    else
        for i = 1, NUM_CHAT_WINDOWS do
            if _G["ChatFrame" .. i] then func(_G["ChatFrame" .. i], i) end
        end
    end
end

local function ForEachChatFrame(func)
    ForEachWindow(function(frame, id)
        if id ~= COMBAT_LOG_INDEX then func(frame, id) end
    end)
end

local function IsWhisperWindow(frame)
    return frame.isTemporary and (frame.chatType == "WHISPER" or frame.chatType == "BN_WHISPER")
end

---------------------------------------------------------------------------
-- Copy window (also shows a clicked link, ready to copy)
---------------------------------------------------------------------------

local copyWin, copyEdit

local function BuildCopyWindow()
    copyWin = CreateFrame("Frame", "TinkerwiseChatCopyFrame", UIParent, "BackdropTemplate")
    copyWin:SetSize(640, 420)
    copyWin:SetPoint("CENTER")
    copyWin:SetFrameStrata("DIALOG")
    copyWin:SetMovable(true)
    copyWin:SetClampedToScreen(true)
    copyWin:EnableMouse(true)
    copyWin:RegisterForDrag("LeftButton")
    copyWin:SetScript("OnDragStart", copyWin.StartMoving)
    copyWin:SetScript("OnDragStop", copyWin.StopMovingOrSizing)
    copyWin:Hide()
    TW:SkinDialog(copyWin, L["Copy (Ctrl + C)"])
    tinsert(UISpecialFrames, "TinkerwiseChatCopyFrame")

    local scroll = CreateFrame("ScrollFrame", "TinkerwiseChatCopyScroll", copyWin, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -40)
    scroll:SetPoint("BOTTOMRIGHT", -42, 24)

    copyEdit = CreateFrame("EditBox", nil, scroll)
    copyEdit:SetMultiLine(true)
    copyEdit:SetAutoFocus(false)
    copyEdit:SetMaxLetters(0)
    copyEdit:SetFontObject(ChatFontNormal)
    copyEdit:SetWidth(570)
    copyEdit:SetScript("OnEscapePressed", function() copyWin:Hide() end)
    -- Read-only: typing puts the original text back.
    copyEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.original)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(copyEdit)
end

local function ShowCopyWindow(text)
    if not copyWin then BuildCopyWindow() end
    copyEdit.original = text
    copyEdit:SetText(text)
    copyWin:Show()
    copyEdit:SetFocus()
    copyEdit:HighlightText()
end

local function PlainText(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

local function CopyFrame(frame)
    local lines = {}
    for i = 1, frame:GetNumMessages() do
        local text = frame:GetMessageInfo(i)
        if text then lines[#lines + 1] = PlainText(text) end
    end
    ShowCopyWindow(table.concat(lines, "\n"))
end

local copyButtons = {}

local function CopyButton(frame)
    local b = copyButtons[frame]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:SetSize(16, 16)
    b:SetPoint("TOPRIGHT", -2, -2)
    b:SetFrameLevel(frame:GetFrameLevel() + 5)
    b:SetAlpha(0.5)
    b:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    b:SetScript("OnClick", function() CopyFrame(frame) end)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Copy this chat window"])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetAlpha(0.5)
        GameTooltip:Hide()
    end)
    copyButtons[frame] = b
    return b
end

---------------------------------------------------------------------------
-- Resizing, available even when the window is locked
---------------------------------------------------------------------------

local MIN_W, MIN_H, MAX_W, MAX_H = 200, 100, 1400, 1000
local resizeGrips = {}

-- A docked window must cover the main one exactly, or switching tabs moves the background.
local function AlignDockedWindows()
    if not mod.active then return end
    ForEachWindow(function(frame)
        if frame ~= ChatFrame1 and frame.isDocked then
            -- Keeping it on screen would push it up when the main window sits low.
            frame:SetClampedToScreen(false)
            frame.twUnclamped = true
            frame:ClearAllPoints()
            frame:SetAllPoints(ChatFrame1)
        elseif frame.twUnclamped then
            frame:SetClampedToScreen(true)
            frame.twUnclamped = nil
        end
    end)
end

local function ResizeGrip(frame)
    local grip = resizeGrips[frame]
    if grip then return grip end
    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", 2, -2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- Docked windows all follow the main one.
    local function Target() return frame.isDocked and ChatFrame1 or frame end
    grip:SetScript("OnMouseDown", function()
        local target = Target()
        target:SetResizable(true)
        if target.SetResizeBounds then
            target:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
        else
            target:SetMinResize(MIN_W, MIN_H)
            target:SetMaxResize(MAX_W, MAX_H)
        end
        target:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        local target = Target()
        target:StopMovingOrSizing()
        if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(target) end
        mod.db.sizes = mod.db.sizes or {}
        mod.db.sizes[target:GetID()] = { w = target:GetWidth(), h = target:GetHeight() }
        AlignDockedWindows()
    end)
    resizeGrips[frame] = grip
    return grip
end

-- The game's own saved size does not always survive a reload, hence this copy.
-- Only a size that differs is set, so that nothing visibly moves.
local function RestoreSize(frame)
    local db = mod.db
    local size = db and db.enabled and db.resizeGrip and db.sizes and db.sizes[frame:GetID()]
    if size and (math.abs(frame:GetWidth() - size.w) > 0.5 or math.abs(frame:GetHeight() - size.h) > 0.5) then
        frame:SetSize(size.w, size.h)
    end
end

local function RestoreSizes()
    ForEachWindow(RestoreSize)
    AlignDockedWindows()
end

-- Runs right after the game places a window, during the loading screen.
if FCF_RestorePositionAndDimensions then
    hooksecurefunc("FCF_RestorePositionAndDimensions", RestoreSize)
end

---------------------------------------------------------------------------
-- Clickable links
---------------------------------------------------------------------------

local function IsURL(word)
    return word:match("^https?://") or word:match("^www%.[%w%-]")
end

local function LinkifyWord(word)
    if IsURL(word) then
        return "|cff66bbff|H" .. URL_PREFIX .. word .. "|h[" .. word .. "]|h|r"
    end
end

local function URLFilter(_, _, message, ...)
    local linked = message:gsub("[^%s|]+", LinkifyWord)
    if linked ~= message then return false, linked, ... end
end

-- The game has no hook that runs before an unknown link type would raise an error.
local linkHandlerInstalled
local function InstallLinkHandler()
    if linkHandlerInstalled then return end
    linkHandlerInstalled = true
    local original = SetItemRef
    SetItemRef = function(link, ...)
        if link:sub(1, #URL_PREFIX) == URL_PREFIX then
            return ShowCopyWindow(link:sub(#URL_PREFIX + 1))
        end
        return original(link, ...)
    end
end

local function SetURLFilter(on)
    for _, event in ipairs(URL_EVENTS) do
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_" .. event, URLFilter)
        if on then ChatFrame_AddMessageEventFilter("CHAT_MSG_" .. event, URLFilter) end
    end
end

---------------------------------------------------------------------------
-- Readability: rewrites each line just before it is displayed
---------------------------------------------------------------------------

local function ShortenChannels(text)
    text = text:gsub("|h%[(%d+)%. [^%]]-%]|h", "|h[%1]|h")
    text = text:gsub("(|Hchannel:(%u+)|h)%[[^%]]-%](|h)", function(open, channel, close)
        local short = SHORT_CHANNELS[channel]
        if short then return open .. "[" .. short .. "]" .. close end
    end)
    return text
end

local wrapped = {}

local function WrapFrame(frame)
    if wrapped[frame] then return end
    wrapped[frame] = true
    local original = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if mod.active and type(text) == "string" then
            if mod.db.shortChannels then text = ShortenChannels(text) end
            -- Blizzard's own timestamp setting already adds one.
            if mod.db.timestamps and GetCVar("showTimestamps") == "none" then
                text = "|cff888888" .. date("%H:%M") .. "|r " .. text
            end
        end
        return original(self, text, ...)
    end
end

local classColorBackup

local function ApplyClassColors()
    local on = mod.active and mod.db.classColors
    -- This setting takes priority over ChatTypeInfo below. The player's value survives a logout.
    local override = GetCVar("chatClassColorOverride")
    if override then
        if on then
            if not mod.db.classOverrideBackup then mod.db.classOverrideBackup = override end
            SetCVar("chatClassColorOverride", "0")
        elseif mod.db.classOverrideBackup then
            SetCVar("chatClassColorOverride", mod.db.classOverrideBackup)
            mod.db.classOverrideBackup = nil
        end
    end
    if on and not classColorBackup then
        classColorBackup = {}
        for chatType, info in pairs(ChatTypeInfo) do classColorBackup[chatType] = info.colorNameByClass or false end
    end
    if on then
        for _, info in pairs(ChatTypeInfo) do info.colorNameByClass = true end
    elseif classColorBackup then
        for chatType, value in pairs(classColorBackup) do ChatTypeInfo[chatType].colorNameByClass = value end
        classColorBackup = nil
    end
end

---------------------------------------------------------------------------
-- Input history, kept between sessions
---------------------------------------------------------------------------

local historyHooked, historyRestored, restoring

local function RememberLine(_, line)
    if restoring or not (mod.active and mod.db.keepHistory) or not line or line == "" then return end
    local history = mod.db.history
    history[#history + 1] = line
    if #history > HISTORY_SIZE then table.remove(history, 1) end
end

local function SetupHistory()
    ForEachChatFrame(function(frame)
        if frame.editBox and not historyHooked then hooksecurefunc(frame.editBox, "AddHistoryLine", RememberLine) end
    end)
    historyHooked = true
    if historyRestored or not mod.db.keepHistory then return end
    historyRestored = true
    restoring = true
    ForEachChatFrame(function(frame)
        if frame.editBox then
            for _, line in ipairs(mod.db.history) do frame.editBox:AddHistoryLine(line) end
        end
    end)
    restoring = false
end

---------------------------------------------------------------------------
-- Tabs by theme
---------------------------------------------------------------------------

local function FindTab(name)
    for i = 1, NUM_CHAT_WINDOWS do
        local tabName, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
        if tabName == name and (shown or docked) then return _G["ChatFrame" .. i] end
    end
end

local function AddGroup(frame, group)
    if not ChatTypeGroup[group] then return end
    for _, existing in ipairs(frame.messageTypeList or {}) do
        if existing == group then return end
    end
    ChatFrame_AddMessageGroup(frame, group)
end

local function SetGeneralGroups(tab, add)
    for _, group in ipairs(tab.groups) do
        if add then
            AddGroup(ChatFrame1, group)
        elseif ChatTypeGroup[group] then
            ChatFrame_RemoveMessageGroup(ChatFrame1, group)
        end
    end
end

-- The single Whispers tab was replaced by one tab per conversation.
local function RemoveOldWhispersTab()
    local db = mod.db
    if db.tabs.tabWhispers == "own" then
        local frame = FindTab(L["Whispers"])
        if frame then FCF_Close(frame) end
    end
    db.tabs.tabWhispers = nil
    if db.moved.tabWhispers then
        AddGroup(ChatFrame1, "WHISPER")
        AddGroup(ChatFrame1, "BN_WHISPER")
        db.moved.tabWhispers = nil
    end
end

-- One tab per whisper conversation is built into the game: these settings turn it on.
local WHISPER_CVARS = { "whisperMode", "bnWhisperMode" }

local function ApplyWhisperMode()
    local db = mod.db
    local on = mod.active and db.whisperTabs
    db.whisperBackup = db.whisperBackup or {}
    for _, cvar in ipairs(WHISPER_CVARS) do
        local value = GetCVar(cvar)
        if value and on then
            db.whisperBackup[cvar] = db.whisperBackup[cvar] or value
            SetCVar(cvar, "popout")
        elseif value and db.whisperBackup[cvar] then
            SetCVar(cvar, db.whisperBackup[cvar])
            db.whisperBackup[cvar] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Channel following the selected tab
---------------------------------------------------------------------------

-- Returns the chat type and whisper target of a window, or nothing to leave the channel alone.
local function WindowChannel(frame)
    if IsWhisperWindow(frame) then return frame.chatType, frame.chatTarget end
    if frame == ChatFrame1 then return "SAY" end
    local name = GetChatWindowInfo(frame:GetID())
    if name == L["Group"] then
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
    elseif name == L["Guild"] and IsInGuild() then
        return "GUILD"
    end
end

local function SelectChannel(frame)
    if not (mod.active and mod.db.autoChannel and frame) then return end
    local chatType, target = WindowChannel(frame)
    if not chatType then return end
    local box = ChatEdit_ChooseBoxForSend(frame)
    box:SetAttribute("chatType", chatType)
    box:SetAttribute("stickyType", chatType)
    if target then box:SetAttribute("tellTarget", target) end
    ChatEdit_UpdateHeader(box)
end

local function OpenTab(tab)
    local frame = FindTab(tab.name)
    if frame then
        mod.db.tabs[tab.key] = "found" -- the player's own tab: never closed by the addon
        return
    end
    FCF_OpenNewWindow(tab.name, true)
    frame = FindTab(tab.name)
    if not frame then
        TW:Print(format(L["no free chat window for the \"%s\" tab."], tab.name))
        return
    end
    ChatFrame_RemoveAllMessageGroups(frame)
    for _, group in ipairs(tab.groups) do
        if ChatTypeGroup[group] then ChatFrame_AddMessageGroup(frame, group) end
    end
    mod.db.tabs[tab.key] = "own"
end

-- Each tab takes the color of its messages, so it follows the player's chat colors.
local function ApplyTabColors()
    for _, tab in ipairs(TABS) do
        local frame = FindTab(tab.name)
        local button = frame and _G[frame:GetName() .. "Tab"]
        local text = button and button:GetFontString()
        if text then
            local color = NORMAL_FONT_COLOR
            if mod.active and mod.db.colorTabs and mod.db.tabs[tab.key] then
                color = ChatTypeInfo[tab.groups[1]] or color
            end
            text:SetTextColor(color.r, color.g, color.b)
        end
    end
    ForEachWindow(function(frame)
        local button = IsWhisperWindow(frame) and _G[frame:GetName() .. "Tab"]
        local text = button and button:GetFontString()
        if text then
            local color = mod.active and mod.db.colorTabs and ChatTypeInfo[frame.chatType] or NORMAL_FONT_COLOR
            text:SetTextColor(color.r, color.g, color.b)
        end
    end)
end

-- Tabs made by an older version have Group first: reopened once, in the order of TABS.
-- A tab the player made is left where it is.
local function ReorderOldTabs()
    local db = mod.db
    if db.guildTabFirst then return end
    db.guildTabFirst = true
    if db.tabs.tabGroup ~= "own" or db.tabs.tabGuild ~= "own" then return end
    for _, tab in ipairs(TABS) do
        local frame = FindTab(tab.name)
        if frame then FCF_Close(frame) end
        db.tabs[tab.key] = nil
    end
end

local tabColorsHooked

local function SyncTabs()
    -- The game repaints the tabs each time the selected one changes.
    if not tabColorsHooked and FCFTab_UpdateColors then
        tabColorsHooked = true
        hooksecurefunc("FCFTab_UpdateColors", ApplyTabColors)
    end
    if mod.active then ReorderOldTabs() end
    for _, tab in ipairs(TABS) do
        local db = mod.db
        local wanted = mod.active and db[tab.key]
        if wanted and not db.tabs[tab.key] then
            OpenTab(tab)
        elseif not wanted and db.tabs[tab.key] then
            if db.tabs[tab.key] == "own" then
                local frame = FindTab(tab.name)
                if frame then FCF_Close(frame) end
            end
            db.tabs[tab.key] = nil
        end

        -- Only a tab that exists may take its messages away from the general tab.
        local frame = wanted and db.removeFromGeneral and db.tabs[tab.key] and FindTab(tab.name)
        if frame then
            for _, group in ipairs(tab.groups) do AddGroup(frame, group) end
            SetGeneralGroups(tab, false)
            db.moved[tab.key] = true
        elseif db.moved[tab.key] then
            SetGeneralGroups(tab, true)
            db.moved[tab.key] = nil
        end
    end
    ApplyTabColors()
end

---------------------------------------------------------------------------
-- Applying the settings
---------------------------------------------------------------------------

-- Every window, combat log included, so that docked tabs share the same background.
local function ApplyBackground()
    local db = mod.db
    local custom = mod.active and db.customBackground
    ForEachWindow(function(frame, i)
        local backup = db.backgroundBackup and db.backgroundBackup[i]
        if custom then
            if not backup and not frame.isTemporary then
                local _, _, r, g, b, alpha = GetChatWindowInfo(i)
                db.backgroundBackup = db.backgroundBackup or {}
                db.backgroundBackup[i] = { r = r, g = g, b = b, alpha = alpha }
            end
            FCF_SetWindowColor(frame, db.bgColor.r, db.bgColor.g, db.bgColor.b)
            FCF_SetWindowAlpha(frame, db.bgOpacity / 100)
        elseif backup then
            FCF_SetWindowColor(frame, backup.r, backup.g, backup.b)
            FCF_SetWindowAlpha(frame, backup.alpha)
            db.backgroundBackup[i] = nil
        end
    end)
end

-- The game reads these values each time it fades the tabs.
local TAB_ALPHAS = { "CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA", "CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA" }
local tabAlphaBackup

local function ApplyTabVisibility()
    local on = mod.active and mod.db.alwaysShowTabs
    if not on and not tabAlphaBackup then return end
    if on and not tabAlphaBackup then
        tabAlphaBackup = {}
        for _, name in ipairs(TAB_ALPHAS) do tabAlphaBackup[name] = _G[name] end
    end
    for _, name in ipairs(TAB_ALPHAS) do _G[name] = on and 1 or tabAlphaBackup[name] end
    ForEachWindow(function(frame)
        local tab = _G[frame:GetName() .. "Tab"]
        if tab and on then
            tab:SetAlpha(1)
        elseif tab and FCFTab_UpdateAlpha then
            FCFTab_UpdateAlpha(frame)
        end
    end)
    if not on then tabAlphaBackup = nil end
end

local function Apply()
    local on, db = mod.active, mod.db
    ApplyBackground()
    ApplyTabVisibility()
    ForEachChatFrame(function(frame)
        WrapFrame(frame)
        if frame.editBox then frame.editBox:SetAltArrowKeyMode(not (on and db.arrowKeys)) end
        frame:SetFading(not (on and db.noFade))
        if on and db.copyButton then
            CopyButton(frame):Show()
        elseif copyButtons[frame] then
            copyButtons[frame]:Hide()
        end
        if on and db.resizeGrip then
            ResizeGrip(frame):Show()
        elseif resizeGrips[frame] then
            resizeGrips[frame]:Hide()
        end
    end)
    if on and db.links then InstallLinkHandler() end
    SetURLFilter(on and db.links)
    ApplyClassColors()
    ApplyWhisperMode()
end

local gameHooked

local function HookGame()
    if gameHooked then return end
    gameHooked = true
    if FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            if mod.active then
                Apply()
                SyncTabs()
            end
        end)
    end
    if FCF_Tab_OnClick then
        hooksecurefunc("FCF_Tab_OnClick", function(tab)
            SelectChannel(_G["ChatFrame" .. tab:GetID()])
        end)
    end
    if FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function(_, frame)
            AlignDockedWindows()
            SelectChannel(frame)
        end)
    end
end

local events = CreateFrame("Frame")
-- The game reloads these when entering the world.
events:SetScript("OnEvent", function()
    ApplyClassColors()
    RestoreSizes()
    C_Timer.After(1, RestoreSizes)
end)

mod = TW:NewModule("Chat", {
    title = L["Chat"],
    icon = "Interface\\Icons\\INV_Letter_05",
    section = L["Chat"],
    desc = L["Improves the chat: easier typing, more readable lines, copying a window's text and automatic tabs by theme."],
    defaults = {
        arrowKeys = true, keepHistory = true, links = true,
        timestamps = true, classColors = true, shortChannels = true, noFade = false,
        copyButton = true, resizeGrip = true,
        customBackground = false, bgColor = { r = 0, g = 0, b = 0 }, bgOpacity = 25,
        whisperTabs = true, autoChannel = true, tabGroup = true, tabGuild = true, removeFromGeneral = true, colorTabs = true, alwaysShowTabs = false,
    },
    options = {
        { type = "header", label = L["Typing"] },
        { type = "toggle", key = "arrowKeys", label = L["Arrow keys without Alt"] },
        { type = "toggle", key = "keepHistory", label = L["Keep sent messages between sessions"] },
        { type = "toggle", key = "links", label = L["Clickable web links"] },
        { type = "header", label = L["Readability"] },
        { type = "toggle", key = "timestamps", label = L["Show the time"] },
        { type = "toggle", key = "classColors", label = L["Color names by class"] },
        { type = "toggle", key = "shortChannels", label = L["Shorten channel names"] },
        { type = "toggle", key = "noFade", label = L["Keep messages from fading"] },
        { type = "header", label = L["Windows"] },
        { type = "toggle", key = "copyButton", label = L["Copy button on chat windows"] },
        { type = "toggle", key = "resizeGrip", label = L["Resize handle on chat windows"] },
        { type = "header", label = L["Background"] },
        { type = "toggle", key = "customBackground", label = L["Custom background"] },
        { type = "color", key = "bgColor", label = L["Background color"] },
        { type = "slider", key = "bgOpacity", label = L["Opacity (%)"], min = 0, max = 100, step = 5 },
        { type = "header", label = L["Tabs"] },
        { type = "toggle", key = "whisperTabs", label = L["One new tab per whisper conversation"] },
        { type = "toggle", key = "autoChannel", label = L["Channel follows the selected tab"] },
        { type = "toggle", key = "tabGuild", label = L["Guild"] },
        { type = "toggle", key = "tabGroup", label = L["Group and raid"] },
        { type = "toggle", key = "removeFromGeneral", label = L["Remove these messages from the General tab"] },
        { type = "toggle", key = "colorTabs", label = L["Color these tabs"] },
        { type = "toggle", key = "alwaysShowTabs", label = L["Always show tabs"] },
    },
})

function mod:OnEnable()
    self.db.history = self.db.history or {}
    self.db.tabs = self.db.tabs or {}
    self.db.moved = self.db.moved or {}
    self.db.moveFromGeneral = nil -- previous option, off by default: replaced by removeFromGeneral
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    SetupHistory()
    Apply()
    HookGame()
    -- Chat window settings are not ready yet at login.
    C_Timer.After(1, function()
        if self.active then
            RemoveOldWhispersTab()
            SyncTabs()
            RestoreSizes()
        end
    end)
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    Apply()
    SyncTabs()
    if copyWin then copyWin:Hide() end
end

function mod:OnOptionChanged(key)
    if key == "keepHistory" then SetupHistory() end
    Apply()
    SyncTabs()
end
