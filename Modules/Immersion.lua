-- Immersion: follows the game's "hide interface" key (Alt+Z). While the interface is hidden, black bars,
-- a few chosen elements kept on screen and the recent loot for a few seconds; it comes back with a fade.
-- The addon never hides or shows the interface itself: see "Following the game's key". Kept elements are
-- detached from the interface while it is hidden, out of combat only. Action bars are deliberately not offered.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local DEFAULTS = {
    duration = 1,
    keepMinimap = false,
    keepChat = false,
    keepTinkerwise = true,
    letterbox = true,
    letterboxSize = 10,
    letterboxTranslucent = false,
    questScene = false,
    camera = true,
    zoom = 8,
    lootLog = true,
    lootHold = 6,
    point = "BOTTOM", x = 0, y = 180,
}

local KEPT_FRAMES = {
    keepMinimap = { "MinimapCluster" },
    keepChat = { "GeneralDockManager" }, -- holds the docked tabs; the windows are added below
    -- Not an option: always kept. The tooltip is there for the quest rewards.
    -- The game places these itself each time they are shown, so they are not pinned.
    always = { "QuestFrame", "GossipFrame", "GameTooltip" },
    -- Not an option either: loot can be picked up. See lootHolder.
    loot = { "LootFrame" },
    keepTinkerwise = {
        "TinkerwiseStatDeltaFrame",
        "TinkerwisePotionFrame",
    },
}

-- Every chat window, with its input box and its tab.
local CHAT_TABS = {}
for i = 1, NUM_CHAT_WINDOWS do
    tinsert(KEPT_FRAMES.keepChat, "ChatFrame" .. i)
    tinsert(KEPT_FRAMES.keepChat, "ChatFrame" .. i .. "EditBox")
    tinsert(KEPT_FRAMES.keepChat, "ChatFrame" .. i .. "Tab")
    CHAT_TABS["ChatFrame" .. i .. "Tab"] = "ChatFrame" .. i
end

-- The game sets the loot window's scale and place expecting the interface above it: this parent stands
-- in for the interface, with its rectangle and scale.
local lootHolder = CreateFrame("Frame")
lootHolder:SetAllPoints(UIParent)

local FADE_OUT_TIME = 1 -- seconds a loot line takes to disappear
local MAX_LOOT = 6
local ROW_H = 28

local db
local detached = {} -- frame -> { parent, scale, strata, level, points }

---------------------------------------------------------------------------
-- Kept elements
---------------------------------------------------------------------------

-- Changes a frame's parent, keeping how it and its children are drawn. Some windows set their children's
-- levels one by one (a bag's translucent background sits below its items, at level 0): a new parent
-- would otherwise change that order and put the background over the contents.
local function Reparent(f, parent)
    local strata, level = f:GetFrameStrata(), f:GetFrameLevel()
    local children = {}
    for _, child in ipairs({ f:GetChildren() }) do
        children[child] = { child:GetFrameStrata(), child:GetFrameLevel() }
    end
    f:SetParent(parent)
    f:SetFrameStrata(strata)
    f:SetFrameLevel(level)
    for child, was in pairs(children) do
        child:SetFrameStrata(was[1])
        child:SetFrameLevel(was[2])
    end
end

local function Detach()
    if InCombatLockdown() then return end
    lootHolder:SetScale(UIParent:GetEffectiveScale())
    for option, names in pairs(KEPT_FRAMES) do
        if option == "always" or option == "loot" or db[option] then
            for _, name in ipairs(names) do
                local f = _G[name]
                -- A docked tab stays inside the dock, which is kept as a whole.
                local chatWindow = CHAT_TABS[name] and _G[CHAT_TABS[name]]
                if f and not detached[f] and not (chatWindow and chatWindow.isDocked) then
                    local saved = { parent = f:GetParent(), scale = f:GetScale() }
                    detached[f] = saved
                    local effectiveScale = f:GetEffectiveScale()
                    local left, top, width, height = f:GetLeft(), f:GetTop(), f:GetSize()
                    local points = {}
                    for i = 1, f:GetNumPoints() do points[i] = { f:GetPoint(i) } end
                    if option == "loot" then
                        Reparent(f, lootHolder)
                    else
                        Reparent(f, nil)
                        f:SetScale(effectiveScale)
                    end
                    -- Pin it where it is on screen: its anchors may depend on the hidden interface.
                    if option ~= "always" and option ~= "loot" and left and top then
                        saved.points = points
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", WorldFrame, "BOTTOMLEFT", left, top)
                        f:SetSize(width, height)
                    end
                end
            end
        end
    end
end

local function Attach()
    if InCombatLockdown() then return end -- done when combat ends
    for f, saved in pairs(detached) do
        Reparent(f, saved.parent)
        f:SetScale(saved.scale)
        -- The size stays as it is: it may have changed while detached, and two anchors set it anyway.
        if saved.points then
            f:ClearAllPoints()
            for _, point in ipairs(saved.points) do f:SetPoint(unpack(point, 1, 5)) end
        end
        detached[f] = nil
    end
end

---------------------------------------------------------------------------
-- Loot log
---------------------------------------------------------------------------

-- No parent: it must stay visible while the interface is hidden.
local log = CreateFrame("Frame", "TinkerwiseLootLog")
log:SetSize(280, MAX_LOOT * ROW_H)
log:SetFrameStrata("HIGH")
log:Hide()
TW:CreateMover(log, function() return db end, DEFAULTS)

local tip = CreateFrame("GameTooltip", "TinkerwiseLootLogTip", nil, "GameTooltipTemplate")
tip:SetFrameStrata("TOOLTIP")

local entries = {} -- newest first: { link, count, time }
local rows = {}

for i = 1, MAX_LOOT do
    local r = CreateFrame("Button", nil, log)
    r:SetSize(280, ROW_H - 2)
    r:SetPoint("BOTTOMLEFT", 0, (i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.55)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        if not self.link then return end
        tip:SetScale(UIParent:GetEffectiveScale())
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:SetHyperlink(self.link)
        tip.twCompared = nil
        if ns.CompareTooltip then ns.CompareTooltip(tip) end
        tip:Show()
    end)
    r:SetScript("OnLeave", function() tip:Hide() end)
    r:Hide()
    rows[i] = r
end

local function RenderLog()
    for i, r in ipairs(rows) do
        local e = entries[i]
        if e then
            r.link = e.link
            r.icon:SetTexture((select(5, ns.API.GetItemInfoInstant(e.link))))
            r.text:SetText(e.count > 1 and (e.link .. " x" .. e.count) or e.link)
            r:Show()
        else
            r.link = nil
            r:Hide()
        end
    end
    log:SetShown(#entries > 0 or log:IsUnlocked())
end

log:SetScript("OnUpdate", function()
    local now, changed = GetTime(), false
    for i = #entries, 1, -1 do
        local e, r = entries[i], rows[i]
        if r:IsMouseOver() then e.time = now end -- reading it: keep it
        local age = now - e.time
        if age > db.lootHold + FADE_OUT_TIME then
            table.remove(entries, i)
            changed = true
        else
            r:SetAlpha(age > db.lootHold and 1 - (age - db.lootHold) / FADE_OUT_TIME or 1)
        end
    end
    if changed then
        tip:Hide()
        for _, r in ipairs(rows) do r:SetAlpha(1) end
        RenderLog()
    end
end)

local function ClearLog()
    wipe(entries)
    tip:Hide()
    RenderLog()
end

-- Turns "Vous recevez le butin : %s." into a pattern catching the link and the count.
local function LootPattern(text)
    if not text then return end
    return "^" .. text:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
end
local LOOT_PATTERNS = {}
for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
    LOOT_PATTERNS[#LOOT_PATTERNS + 1] = LootPattern(_G[name])
end

-- The item link and count of a loot message about the player; nil for any other message.
function ns.ParseLootMessage(message)
    for _, pattern in ipairs(LOOT_PATTERNS) do
        local link, count = message:match(pattern)
        if link then return link, tonumber(count) or 1 end
    end
end

local function OnLootMessage(message)
    if not db.lootLog or UIParent:IsShown() then return end
    local link, count = ns.ParseLootMessage(message)
    if not link then return end
    table.insert(entries, 1, { link = link, count = count, time = GetTime() })
    entries[MAX_LOOT + 1] = nil
    for _, r in ipairs(rows) do r:SetAlpha(1) end
    log:SetScale(UIParent:GetEffectiveScale())
    RenderLog()
end

---------------------------------------------------------------------------
-- Black bars
---------------------------------------------------------------------------

-- Child of the game world: it stays visible while the interface is hidden.
local letterbox = CreateFrame("Frame", nil, WorldFrame)
letterbox:SetAllPoints()
letterbox:SetFrameStrata("BACKGROUND")
letterbox:Hide()
ns.ImmersionLetterbox = letterbox -- the quest scene has its own bands and fades these out
local barTop = letterbox:CreateTexture(nil, "BACKGROUND")
barTop:SetColorTexture(0, 0, 0, 1)
barTop:SetPoint("TOPLEFT")
barTop:SetPoint("TOPRIGHT")
local barBottom = letterbox:CreateTexture(nil, "BACKGROUND")
barBottom:SetColorTexture(0, 0, 0, 1)
barBottom:SetPoint("BOTTOMLEFT")
barBottom:SetPoint("BOTTOMRIGHT")

local function ShowLetterbox()
    if not db.letterbox then return end
    local height = letterbox:GetHeight() * db.letterboxSize / 100
    barTop:SetHeight(height)
    barBottom:SetHeight(height)
    local opacity = db.letterboxTranslucent and 0.92 or 1
    barTop:SetColorTexture(0, 0, 0, opacity)
    barBottom:SetColorTexture(0, 0, 0, opacity)
    letterbox:SetAlpha(0)
    letterbox:Show()
end

---------------------------------------------------------------------------
-- Following the game's key
---------------------------------------------------------------------------

-- The interface is hidden and shown again by the game's own key only. Doing it from the addon would run
-- the interface's show and hide scripts under Tinkerwise's taint, and the action bars would then refuse
-- their cooldowns and buttons in combat. So the mode only reacts: no fade out (the game hides at once),
-- a fade in when the interface comes back, out of combat.
local driver = CreateFrame("Frame")
driver:Hide()
local fadingIn, elapsedTime = false, 0

driver:SetScript("OnUpdate", function(self, elapsed)
    elapsedTime = elapsedTime + elapsed
    local p = math.min(elapsedTime / db.duration, 1)
    if fadingIn then
        UIParent:SetAlpha(p)
        letterbox:SetAlpha(1 - p)
    else
        letterbox:SetAlpha(p)
    end
    if p >= 1 then
        self:Hide()
        if fadingIn then
            fadingIn = false
            letterbox:Hide()
        end
    end
end)

local function StartFade(inward)
    fadingIn, elapsedTime = inward, 0
    driver:Show()
end

-- Ends a running fade at once: the quest scene takes over the interface's alpha.
function ns.FinishImmersionFade()
    if not driver:IsShown() then return end
    driver:Hide()
    if fadingIn then
        fadingIn = false
        UIParent:SetAlpha(1)
        letterbox:Hide()
    else
        letterbox:SetAlpha(1)
    end
end

local function CancelFade()
    if not driver:IsShown() then return end
    driver:Hide()
    if fadingIn then UIParent:SetAlpha(1) end
    fadingIn = false
end

local entered = false -- the interface was hidden while the mode was on

-- Whether the interface is hidden by the mode's key.
local function IsOn()
    return entered and not UIParent:IsShown()
end

ns.ImmersionMode = { IsOn = IsOn }

-- A cinematic or a movie hides the interface too: it is not the mode.
local function Cinematic()
    return (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown())
end

-- Forever Fishing hides the interface itself while its fishing bar is open (its "Hide Blizzard UI" option)
-- and moves the minimap and the tooltips under its own frame meanwhile: the mode stays out of its way,
-- or both would move the same frames and the minimap's tooltip would end up misplaced.
local function ForeverFishingHides()
    local ff = _G.ForeverFishing
    if type(ff) ~= "table" then return false end
    if ff.fishingUIChangeInProgress then return true end
    local ok, mode = pcall(ff.GetBlizzardUIHideMode, ff)
    return ok and mode ~= "never" and ff.bar ~= nil and ff.bar:IsShown()
end

UIParent:HookScript("OnHide", function()
    if not (db and TW.modules.Immersion.active) or Cinematic() or ForeverFishingHides() then return end
    entered = true
    CancelFade()
    Detach() -- not in combat: the kept elements then hide with the rest
    if db.letterbox then
        ShowLetterbox()
        StartFade(false)
    end
end)

UIParent:HookScript("OnShow", function()
    if not db then return end
    ClearLog()
    Attach() -- in combat, done when it ends
    local wasOn = entered
    entered = false
    if wasOn and TW.modules.Immersion.active and not InCombatLockdown() and not ns.ImmersionScene.AnyPlaying() then
        UIParent:SetAlpha(0)
        if not letterbox:IsShown() then letterbox:SetAlpha(0) end
        StartFade(true)
    else
        CancelFade()
        letterbox:Hide()
    end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, message)
    if event == "CHAT_MSG_LOOT" then
        OnLootMessage(message)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The interface shown again in combat stays fully visible.
        if fadingIn then CancelFade() letterbox:Hide() end
    elseif not TW.modules.Immersion.active then
        -- Disabled in combat (see OnDisable): only this cleanup was left to do.
        events:UnregisterAllEvents()
        Attach()
    elseif UIParent:IsShown() then
        Attach()
    end
end)

local mod = TW:NewModule("Immersion", {
    title = L["Immersion Mode"],
    icon = "Interface\\Icons\\Spell_Shadow_Twilight",
    section = "Immersion",
    desc = L["When the game's key hides the interface (Alt+Z by default), black bars come in and a few elements can stay on screen. Your loot shows for a few seconds, with item details on hover. The same key brings the interface back with a fade, in combat too.\n\nThe optional quest scene stages the quests you open or turn in, with the interface shown or hidden: black bars, a slowly turning camera and text that writes itself. Click the screen to show it all at once. Out of combat only. The camera uses the game's view slot 5."],
    defaults = DEFAULTS,
    options = {
        { type = "slider", key = "duration", label = L["Fade duration (s)"], min = 0.1, max = 2, step = 0.1 },
        { type = "header", label = L["Keep visible"] },
        { type = "toggle", key = "keepMinimap", label = L["Minimap"] },
        { type = "toggle", key = "keepChat", label = L["Chat"] },
        { type = "toggle", key = "keepTinkerwise", label = L["Tinkerwise windows and alerts"] },
        { type = "header", label = L["Black bars"] },
        { type = "toggle", key = "letterbox", label = L["Show black bars"] },
        { type = "slider", key = "letterboxSize", label = L["Height of each bar (% of screen)"], min = 5, max = 20, step = 1 },
        { type = "toggle", key = "letterboxTranslucent", label = L["Slightly transparent bars"] },
        { type = "header", label = L["Quest scene"] },
        { type = "toggle", key = "questScene", label = L["Stage quests"] },
        { type = "toggle", key = "camera", label = L["Camera movement"] },
        { type = "slider", key = "zoom", label = L["Camera zoom"], min = 0, max = 20, step = 1 },
        { type = "header", label = L["Loot"] },
        { type = "toggle", key = "lootLog", label = L["Show what I pick up"] },
        { type = "slider", key = "lootHold", label = L["Display duration (s)"], min = 2, max = 20, step = 1 },
        { type = "execute", label = L["Reset position"], editMode = "only", func = function() log:ResetPosition() end },
    },
})

ns.AddToEditMode({
    frame = log, mod = mod, label = L["Loot (immersion mode)"], card = L["Loot"],
    OnEditing = function()
        log:SetScale(UIParent:GetEffectiveScale())
        RenderLog()
    end,
})

function mod:OnEnable()
    db = self.db
    log:ApplyPosition()
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_LOOT" }) do
        events:RegisterEvent(e)
    end
    if db.questScene then ns.QuestScene.Enable(db) end
end

function mod:OnOptionChanged(key)
    if key == "questScene" then
        ns.QuestScene.Disable()
        if db.questScene then ns.QuestScene.Enable(db) end
    end
end

function mod:OnDisable()
    ns.QuestScene.Disable()
    events:UnregisterAllEvents()
    CancelFade()
    letterbox:Hide()
    ClearLog()
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        Attach()
    end
end
