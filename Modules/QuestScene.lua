-- QuestScene: when a quest is opened, or handed in, the interface fades away, black bands
-- frame the screen, the camera turns slowly and the text is written out. Gossip lists are left alone.
--
-- The interface is made transparent rather than hidden: hiding it would close the quest
-- with the NPC. The scene covers the whole screen, so the invisible interface takes no clicks.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BAND_H = 300
local TEXT_RIGHT = 420 -- the rewards and buttons use the right part of the band
local SAVED_VIEW = 5     -- camera view slot used to restore the camera
local CHARS_PER_SECOND = 45
local CLOSE_DELAY = 0.15 -- the game closes and reopens the quest between two steps
local MAX_REWARDS = 8

local db
local playing, cameraMoved, closeToken = false, false, 0
local kind, choice, fullText, shownBytes, typed = nil, nil, "", 0, 0

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- No parent: the scene must stay visible while the interface is transparent.
local scene = CreateFrame("Frame", "TinkerwiseQuestScene")
scene:SetFrameStrata("FULLSCREEN_DIALOG")
scene:EnableMouse(true)
scene:Hide()

local function Band(point)
    local band = scene:CreateTexture(nil, "BACKGROUND")
    band:SetColorTexture(0, 0, 0, 0.92)
    band:SetPoint(point .. "LEFT")
    band:SetPoint(point .. "RIGHT")
    return band
end
local topBand = Band("TOP")
local bottomBand = Band("BOTTOM")
bottomBand:SetHeight(BAND_H)

local rule = scene:CreateTexture(nil, "ARTWORK")
rule:SetHeight(1)
rule:SetColorTexture(1, 0.82, 0, 0.6)
rule:SetPoint("BOTTOMLEFT", bottomBand, "TOPLEFT")
rule:SetPoint("BOTTOMRIGHT", bottomBand, "TOPRIGHT")

local title = scene:CreateFontString(nil, "OVERLAY")
title:SetFont(TITLE_FONT, 30, "")
title:SetTextColor(1, 0.9, 0.7)
title:SetPoint("TOP", bottomBand, "TOP", 0, -14)

-- Text on the left of the rewards, scrolling when it does not fit.
local scroll = CreateFrame("ScrollFrame", nil, scene)
scroll:SetPoint("TOPLEFT", bottomBand, "TOPLEFT", 40, -56)
scroll:SetPoint("BOTTOMRIGHT", bottomBand, "BOTTOMRIGHT", -TEXT_RIGHT, 32)
local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(1, 1)
scroll:SetScrollChild(scrollChild)

local body = scrollChild:CreateFontString(nil, "OVERLAY")
body:SetFont(STANDARD_TEXT_FONT, 16, "")
body:SetTextColor(0.95, 0.9, 0.8)
body:SetPoint("TOPLEFT")
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetSpacing(4)

local scrollHint = scene:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
scrollHint:SetPoint("BOTTOMLEFT", bottomBand, "BOTTOMLEFT", 40, 14)
scrollHint:SetText(L["Mouse wheel: scroll"])
scrollHint:Hide()

local followText = true -- the view follows the writing until the player scrolls

local function MaxScroll()
    return math.max(body:GetStringHeight() - scroll:GetHeight(), 0)
end

local function UpdateScroll()
    local max = MaxScroll()
    scrollHint:SetShown(max > 0)
    if followText then
        scroll:SetVerticalScroll(max)
    else
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), max))
    end
end

scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    followText = false
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 40, MaxScroll())))
end)

local money = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
money:SetPoint("BOTTOMRIGHT", bottomBand, "BOTTOMRIGHT", -40, 52)

local primary = CreateFrame("Button", nil, scene, "UIPanelButtonTemplate")
primary:SetSize(150, 28)
primary:SetPoint("BOTTOMRIGHT", bottomBand, "BOTTOMRIGHT", -40, 16)
local secondary = CreateFrame("Button", nil, scene, "UIPanelButtonTemplate")
secondary:SetSize(110, 28)
secondary:SetPoint("RIGHT", primary, "LEFT", -8, 0)

-- The game's tooltip is transparent with the interface, so the scene has its own.
local tip = CreateFrame("GameTooltip", "TinkerwiseQuestSceneTip", nil, "GameTooltipTemplate")
tip:SetFrameStrata("TOOLTIP")

local function ShowRewardTip(self)
    tip:SetScale(UIParent:GetEffectiveScale())
    tip:SetOwner(self, "ANCHOR_TOPRIGHT")
    tip:SetQuestItem(self.rewardType, self.rewardIndex)
    tip.twCompared = nil
    if ns.CompareTooltip then ns.CompareTooltip(tip) end
    tip:Show()
end

local rewards = {}
for i = 1, MAX_REWARDS do
    local r = CreateFrame("Button", nil, scene)
    r:SetScript("OnEnter", ShowRewardTip)
    r:SetScript("OnLeave", function() tip:Hide() end)
    r:SetSize(170, 34)
    r:SetPoint("BOTTOMRIGHT", bottomBand, "BOTTOMRIGHT", -40 - (1 - (i - 1) % 2) * 176, 74 + math.floor((i - 1) / 2) * 38)
    r.highlight = r:CreateTexture(nil, "BACKGROUND")
    r.highlight:SetAllPoints()
    r.highlight:SetColorTexture(1, 0.82, 0, 0.3)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", -2, 0)
    r.name:SetJustifyH("LEFT")
    r:Hide()
    rewards[i] = r
end

---------------------------------------------------------------------------
-- Interface and camera
---------------------------------------------------------------------------

local function StartCamera()
    if not db.camera or cameraMoved then return end
    cameraMoved = true
    SaveView(SAVED_VIEW)
    CameraZoomIn(db.zoom)
    MoveViewLeftStart(0.03)
end

local function RestoreCamera()
    if not cameraMoved then return end
    cameraMoved = false
    MoveViewLeftStop()
    SetView(SAVED_VIEW)
end

local fadeIn = 0
local function Play()
    if playing then return true end
    if InCombatLockdown() then return false end
    ns.FinishImmersionFade()
    playing, fadeIn = true, 0
    -- Mode immersion keeps this window on screen while the interface is hidden.
    QuestFrame:SetAlpha(0)
    scene:ClearAllPoints()
    scene:SetAllPoints(WorldFrame)
    scene:SetScale(UIParent:GetEffectiveScale())
    scene:SetAlpha(0)
    scene:Show()
    topBand:SetHeight(scene:GetHeight() * db.letterboxSize / 100) -- same as the Mode immersion bars
    local opacity = db.letterboxTranslucent and 0.92 or 1
    topBand:SetColorTexture(0, 0, 0, opacity)
    bottomBand:SetColorTexture(0, 0, 0, opacity)
    body:SetWidth(scene:GetWidth() - TEXT_RIGHT - 40)
    StartCamera()
    return true
end

local function Stop()
    closeToken = closeToken + 1
    if not playing then return end
    playing = false
    tip:Hide()
    scene:Hide()
    QuestFrame:SetAlpha(1)
    UIParent:SetAlpha(1)
    ns.ImmersionLetterbox:SetAlpha(1)
    RestoreCamera()
end

scene:SetScript("OnUpdate", function(_, elapsed)
    if fadeIn < 1 then
        fadeIn = math.min(fadeIn + elapsed / 0.4, 1)
        scene:SetAlpha(fadeIn)
        UIParent:SetAlpha(1 - fadeIn)
        ns.ImmersionLetterbox:SetAlpha(1 - fadeIn)
    end
    if shownBytes < #fullText then
        typed = typed + elapsed * CHARS_PER_SECOND
        while typed >= 1 and shownBytes < #fullText do
            typed = typed - 1
            shownBytes = shownBytes + 1
            -- never stop inside a multi-byte character
            while shownBytes < #fullText do
                local nextByte = fullText:byte(shownBytes + 1)
                if nextByte < 128 or nextByte >= 192 then break end
                shownBytes = shownBytes + 1
            end
        end
        body:SetText(fullText:sub(1, shownBytes))
        UpdateScroll()
    end
end)

-- Clicking the scene shows the whole text at once.
scene:SetScript("OnMouseDown", function()
    shownBytes = #fullText
    body:SetText(fullText)
    followText = false
    scroll:SetVerticalScroll(0) -- whole text shown: read it from the start
    UpdateScroll()
end)

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

local function SetText(text)
    -- colour codes must not be cut by the writing effect
    fullText, shownBytes, typed = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), 0, 0
    followText = true
    body:SetText("")
    scroll:SetVerticalScroll(0)
    scrollHint:Hide()
end

local function UpdatePrimary()
    if kind == "progress" then
        primary:SetEnabled(IsQuestCompletable())
    elseif kind == "complete" then
        primary:SetEnabled(GetNumQuestChoices() <= 1 or choice ~= nil)
    else
        primary:SetEnabled(true)
    end
end

local function ShowRewards()
    tip:Hide()
    for _, r in ipairs(rewards) do r:Hide(); r:SetScript("OnClick", nil); r.highlight:Hide() end
    local amount = GetRewardMoney and GetRewardMoney() or 0
    local xp = GetRewardXP and GetRewardXP() or 0
    local parts = {}
    if amount > 0 then parts[#parts + 1] = GetCoinTextureString(amount) end
    if xp > 0 then parts[#parts + 1] = xp .. " XP" end
    money:SetText(table.concat(parts, "    "))
    if kind == "progress" then return money:SetText("") end

    local n = 0
    local function Add(rewardType, index, selectable)
        if n >= MAX_REWARDS then return end
        n = n + 1
        local r = rewards[n]
        r.rewardType, r.rewardIndex = rewardType, index
        local name, texture, count = GetQuestItemInfo(rewardType, index)
        r.icon:SetTexture(texture)
        r.name:SetText((count and count > 1) and (name or "") .. " x" .. count or name or "")
        if selectable then
            r.highlight:SetShown(choice == index)
            r:SetScript("OnClick", function()
                choice = index
                ShowRewards()
                UpdatePrimary()
            end)
        end
        r:Show()
    end
    local canChoose = kind == "complete" and GetNumQuestChoices() > 1
    for i = 1, GetNumQuestChoices() do Add("choice", i, canChoose) end
    for i = 1, GetNumQuestRewards() do Add("reward", i, false) end
end

local function Render(newKind)
    if not Play() then return end
    choice = nil
    kind = newKind
    title:SetText(GetTitleText() or "")
    if kind == "detail" then
        local objective = GetObjectiveText()
        local text = GetQuestText() or ""
        if objective and objective ~= "" then
            text = text .. L["\n\nObjectives: "] .. objective
        end
        SetText(text)
        primary:SetText(L["Accept"])
        primary:SetScript("OnClick", AcceptQuest)
        secondary:SetText(L["Decline"])
        secondary:SetScript("OnClick", DeclineQuest)
    elseif kind == "progress" then
        SetText(GetProgressText())
        primary:SetText(L["Continue"])
        primary:SetScript("OnClick", CompleteQuest)
        secondary:SetText(L["Close"])
        secondary:SetScript("OnClick", CloseQuest)
    else
        SetText(GetRewardText())
        primary:SetText(L["Finish"])
        primary:SetScript("OnClick", function()
            local count = GetNumQuestChoices()
            GetQuestReward(count == 1 and 1 or choice or 0)
        end)
        secondary:SetText(L["Close"])
        secondary:SetScript("OnClick", CloseQuest)
    end
    ShowRewards()
    UpdatePrimary()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_DETAIL" then
        closeToken = closeToken + 1
        Render("detail")
    elseif event == "QUEST_PROGRESS" then
        closeToken = closeToken + 1
        Render("progress")
    elseif event == "QUEST_COMPLETE" then
        closeToken = closeToken + 1
        Render("complete")
    elseif event == "QUEST_ITEM_UPDATE" then
        if playing then ShowRewards() end
    elseif event == "QUEST_FINISHED" then
        closeToken = closeToken + 1
        local token = closeToken
        C_Timer.After(CLOSE_DELAY, function()
            if token == closeToken then Stop() end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        Stop() -- the normal quest window is visible again
    end
end)

-- Part of the "Mode immersion" module, which holds its options.
ns.QuestScene = {}

function ns.QuestScene.IsPlaying()
    return playing
end

function ns.QuestScene.Enable(moduleDB)
    db = moduleDB
    for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
                         "QUEST_ITEM_UPDATE", "PLAYER_REGEN_DISABLED" }) do
        events:RegisterEvent(e)
    end
end

function ns.QuestScene.Disable()
    events:UnregisterAllEvents()
    Stop()
end
