-- What's new: at login, shows once what came out since the version this character last played with
-- (Changelog.lua), every version in between gathered by kind: new, improved, fixed. /tw news shows
-- the whole history.
--
-- TinkerwiseCharDB.lastVersion holds the version last seen. A new character starts at the current
-- one (the setup welcomes it instead); a character from before the news starts at FIRST_TRACKED.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local FIRST_TRACKED = "1.17.1"
local WIDTH, MAX_LIST_H = 560, 420

local KINDS = {
    { key = "new", label = L["New"] },
    { key = "improved", label = L["Improved"] },
    { key = "fixed", label = L["Fixed"] },
}

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------

local function Numbers(version)
    local numbers = {}
    for n in tostring(version or ""):gmatch("%d+") do numbers[#numbers + 1] = tonumber(n) end
    return numbers
end

-- -1, 0 or 1 as a is older than, the same as or newer than b: "1.10.2" is newer than "1.9.5".
local function Compare(a, b)
    local x, y = Numbers(a), Numbers(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p < q and -1 or 1 end
    end
    return 0
end

local function CurrentVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return get("Tinkerwise", "Version") or "0"
end

-- The releases newer than since and not newer than upto (all of them without since), newest first.
local function Releases(since, upto)
    local list = {}
    for _, release in ipairs(ns.Changelog or {}) do
        if (not since or Compare(release.version, since) > 0) and Compare(release.version, upto) <= 0 then
            list[#list + 1] = release
        end
    end
    table.sort(list, function(a, b) return Compare(a.version, b.version) > 0 end)
    return list
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local win, P, UI

local function Build()
    UI = ns.UI
    P = UI.Palette()
    win = CreateFrame("Frame", "TinkerwiseNewsFrame", UIParent)
    win:Hide()
    win:SetWidth(WIDTH)
    win:SetPoint("CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local look = TW.modules.Appearance and TW.modules.Appearance.db or {}
    win:SetScale(math.min((look.configScale or 100) / 100, 1.2))
    UI.Chrome(win, 160)
    tinsert(UISpecialFrames, "TinkerwiseNewsFrame")

    local head = UI.Font(win, 11, P.muted)
    head:SetPoint("TOPLEFT", 24, -20)
    head:SetText(ns.Spaced(UI.Upper(L["What's new"])))
    win.title = UI.Font(win, 26, P.title, UI.TITLE_FONT)
    win.title:SetPoint("TOPLEFT", 24, -40)
    win.sub = UI.Font(win, 12, P.muted)
    win.sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 1, -6)
    local rule = UI.Rule(win, P.line, 0.6)
    rule:SetPoint("TOPLEFT", 24, -100)
    rule:SetPoint("TOPRIGHT", -24, -100)

    win.scroll = UI.NewScroll(win)
    win.scroll:SetPoint("TOPLEFT", 24, -114)
    win.scroll:SetWidth(WIDTH - 56)

    win.all = UI.NewButton(win, L["Whole history"], P)
    win.all:SetPoint("BOTTOMLEFT", 24, 20)
    win.all:SetScript("OnClick", function() ns.ShowNews(true) end)
    local close = UI.NewButton(win, L["Close"], P, true, 26)
    close:SetPoint("BOTTOMRIGHT", -24, 19)
    close:SetScript("OnClick", function() win:Hide() end)
end

-- Fills the window with the releases: by kind, each line with its version when there are several.
local function Fill(releases, subtitle)
    local content = win.scroll.content
    if win.lines then
        for _, region in ipairs(win.lines) do region:Hide() end
    end
    win.lines = {}
    local width = WIDTH - 56
    content:SetWidth(width)
    local several = #releases > 1
    local y = 0
    local function Keep(region)
        win.lines[#win.lines + 1] = region
        return region
    end
    for _, kind in ipairs(KINDS) do
        local any = false
        for _, release in ipairs(releases) do
            for _, text in ipairs(release[kind.key] or {}) do
                if not any then
                    any = true
                    if y < 0 then y = y - 10 end
                    local cap = Keep(UI.Font(content, 10, P.title))
                    cap:SetPoint("TOPLEFT", 2, y)
                    cap:SetText(ns.Spaced(UI.Upper(kind.label)))
                    local line = Keep(UI.Rule(content, P.line, 0.5))
                    line:SetPoint("LEFT", cap, "RIGHT", 10, 0)
                    line:SetPoint("RIGHT", content, "RIGHT", -2, 0)
                    y = y - 22
                end
                local dot = Keep(UI.Disc(content, 6, P.on))
                dot:SetPoint("TOPLEFT", 8, y - 5)
                local tag
                if several then
                    tag = Keep(UI.Font(content, 10, P.muted))
                    tag:SetPoint("TOPRIGHT", -2, y - 1)
                    tag:SetJustifyH("RIGHT")
                    tag:SetText(release.version)
                end
                local fs = Keep(UI.Font(content, 12, P.text))
                fs:SetWordWrap(true)
                fs:SetSpacing(2)
                fs:SetPoint("TOPLEFT", 22, y)
                fs:SetWidth(width - 22 - (several and 46 or 4))
                fs:SetText(text)
                y = y - fs:GetStringHeight() - 8
            end
        end
    end
    if y == 0 then
        local none = Keep(UI.Font(content, 12, P.muted))
        none:SetPoint("TOPLEFT", 2, 0)
        none:SetText(L["Nothing new."])
        y = -20
    end
    content:SetHeight(-y)
    local listH = math.min(-y, MAX_LIST_H)
    win.scroll:SetHeight(listH)
    win.scroll:SetVerticalScroll(0)
    win.scroll.Update()
    win:SetHeight(114 + listH + 70)
    win.title:SetText("Tinkerwise " .. CurrentVersion())
    win.sub:SetText(subtitle)
end

-- Shows the releases newer than since (all of them without since).
local function Open(since)
    if not win then Build() end
    win.since = since
    Fill(Releases(since, CurrentVersion()), since and format(L["Since version %s"], since) or L["Every version"])
    win.all:SetShown(since ~= nil)
    win:Show()
end

-- all: the whole history; else what came out since the version last seen, which becomes the current one.
function ns.ShowNews(all)
    Open(not all and (TinkerwiseCharDB.lastVersion or FIRST_TRACKED) or nil)
    TinkerwiseCharDB.lastVersion = CurrentVersion()
end
TW.commands.news = function() ns.ShowNews(true) end

-- The style changed: built again, showing the same.
ns.styleListeners[#ns.styleListeners + 1] = function()
    if not win then return end
    local shown, since, point = win:IsShown(), win.since, { win:GetPoint() }
    win:Hide()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "TinkerwiseNewsFrame" then table.remove(UISpecialFrames, i) end
    end
    win = nil
    if not shown then return end
    Build()
    if point[1] then
        win:ClearAllPoints()
        win:SetPoint(point[1], UIParent, point[3], point[4], point[5])
    end
    Open(since)
end

---------------------------------------------------------------------------
-- At login
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local current = CurrentVersion()
    local last = TinkerwiseCharDB.lastVersion
    if not last then
        if TW.newCharacter then -- nothing to tell: it starts with this version
            TinkerwiseCharDB.lastVersion = current
            return
        end
        last = FIRST_TRACKED
        TinkerwiseCharDB.lastVersion = last
    end
    if Compare(current, last) <= 0 then
        TinkerwiseCharDB.lastVersion = current -- the same, or an older version put back
        return
    end
    if #Releases(last, current) == 0 then
        TinkerwiseCharDB.lastVersion = current
        return
    end
    -- After the loading screen, out of combat, and once the setup (if it opens) is closed.
    C_Timer.After(4, function()
        local ticker
        ticker = C_Timer.NewTicker(1, function()
            local setup = _G.TinkerwiseSetupFrame
            if ns.setupPending or (setup and setup:IsShown()) or InCombatLockdown() then return end
            ticker:Cancel()
            ns.ShowNews(false)
        end)
    end)
end)
