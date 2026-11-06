-- Immersion: the "hide interface" key (Alt+Z) fades the interface in and out, can keep a few
-- chosen elements on screen and lists recent loot for a few seconds. With a fishing pole equipped,
-- FishingDisplay adds its statistics (and can start the mode by itself).
-- Kept elements are detached from the interface while it is hidden. Action bars are deliberately
-- not offered. Combat brings the interface back and the mode starts again when it ends. During combat
-- the normal key behavior stays, as protected frames cannot be detached.

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
    fishingDisplay = true,
    fishingAuto = true,
    point = "BOTTOM", x = 0, y = 180,
}

local KEPT_FRAMES = {
    keepMinimap = { "MinimapCluster" },
    keepChat = { "GeneralDockManager" }, -- holds the docked tabs; the windows are added below
    -- Not an option: always kept. The tooltip is there for the quest rewards.
    -- The game places these itself each time they are shown, so they are not pinned.
    always = { "QuestFrame", "GossipFrame", "GameTooltip" },
    -- Not an option either: the bags key keeps working, and loot can be picked up. See bagHolder.
    bags = { "ContainerFrameCombinedBags", "LootFrame" },
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

for i = 1, NUM_CONTAINER_FRAMES or 13 do
    tinsert(KEPT_FRAMES.bags, "ContainerFrame" .. i)
end

-- The game sets the scale of the bags each time they open, expecting the interface's scale above it:
-- this parent stands in for the interface, so they keep their usual size and place. It needs the
-- interface's rectangle too, as the first bag is anchored to its parent's corner. The loot window
-- uses it as well.
local bagHolder = CreateFrame("Frame")
bagHolder:SetAllPoints(UIParent)

local FADE_OUT_TIME = 1 -- seconds a loot line takes to disappear
local MAX_LOOT = 6
local ROW_H = 28

local db
local fading, from, to, elapsedTime = false, 1, 1, 0
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
    bagHolder:SetScale(UIParent:GetEffectiveScale())
    for option, names in pairs(KEPT_FRAMES) do
        if option == "always" or option == "bags" or db[option] then
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
                    if option == "bags" then
                        Reparent(f, bagHolder)
                    else
                        Reparent(f, nil)
                        f:SetScale(effectiveScale)
                    end
                    -- Pin it where it is on screen: its anchors may depend on the hidden interface.
                    if option ~= "always" and option ~= "bags" and left and top then
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
TW:CreateMover(log, function() return db end, L["Loot (immersion mode)"], DEFAULTS)

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
-- Fade
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:Hide()

-- The game refuses to open bags while the interface is hidden. Showing it for the call opens them with
-- the game's own logic, and nothing is drawn as it is hidden again within the same frame.
local togglingBags = false

local bagToggle = CreateFrame("Frame") -- owns the bindings of the bag keys
-- Closing needs no interface: only opening is refused.
local function BagKey(name, open)
    local button = CreateFrame("Button", name)
    button:SetScript("OnClick", function()
        if IsAnyBagOpen() then
            CloseAllBags()
        elseif UIParent:IsShown() then -- still fading
            open()
        elseif not InCombatLockdown() then
            togglingBags = true
            UIParent:Show()
            open()
            UIParent:Hide()
            togglingBags = false
        end
    end)
end

local BAG_KEYS = { OPENALLBAGS = "TinkerwiseImmersionAllBags", TOGGLEBACKPACK = "TinkerwiseImmersionBackpack" }
BagKey(BAG_KEYS.OPENALLBAGS, function() OpenAllBags() end)
BagKey(BAG_KEYS.TOGGLEBACKPACK, function() OpenBackpack() end)

-- Only during the mode: the rest of the time, the bag keys stay the game's.
local function BindBagKeys(on)
    if InCombatLockdown() then return end
    ClearOverrideBindings(bagToggle)
    if not on then return end
    for action, button in pairs(BAG_KEYS) do
        local key1, key2 = GetBindingKey(action)
        if key1 then SetOverrideBindingClick(bagToggle, false, key1, button) end
        if key2 then SetOverrideBindingClick(bagToggle, false, key2, button) end
    end
end

local function UpdateFade(self, elapsed)
    elapsedTime = elapsedTime + elapsed
    local p = math.min(elapsedTime / db.duration, 1)
    local alpha = from + (to - from) * p
    UIParent:SetAlpha(alpha)
    letterbox:SetAlpha(1 - alpha)
    if p >= 1 then
        fading = false
        self:Hide()
        if to == 0 then
            SetUIVisibility(false)
            UIParent:SetAlpha(1) -- ready for any other way of showing it again
        else
            letterbox:Hide()
            Attach()
        end
    end
end
driver:SetScript("OnUpdate", UpdateFade)

local function Fade(a, b)
    from, to, elapsedTime, fading = a, b, 0, true
    driver:Show()
end

-- Ends a running fade at once: the quest scene takes over the interface's alpha.
function ns.FinishImmersionFade()
    if fading then UpdateFade(driver, db.duration) end
end

-- Whether the interface is hidden or on its way out.
local function IsOn()
    if fading then return to == 0 end
    return not UIParent:IsShown()
end

-- Set when combat interrupts the mode, which starts again once it ends.
local resumeAfterCombat, resumable = false, true

-- The running scene manages the interface's alpha: Enter and Leave wait for it to end.
-- Returns whether the mode started. A mode that must not come back after combat (a test) says so.
local function Enter(noResume)
    if fading or InCombatLockdown() or ns.ImmersionScene.AnyPlaying() or not UIParent:IsShown() then
        return false
    end
    resumable = not noResume
    Detach() -- kept elements must not fade with the rest
    ShowLetterbox()
    BindBagKeys(true)
    Fade(1, 0)
    ns.FishingDisplay.Update()
    return true
end

-- At once, without a fade: for combat, and for a mode ended while the interface was still fading out.
local function Restore()
    fading = false
    driver:Hide()
    letterbox:Hide()
    BindBagKeys(false)
    UIParent:SetAlpha(1)
    if not UIParent:IsShown() then
        -- The bag keys hide it with UIParent:Hide(), which SetUIVisibility may not know about.
        if not InCombatLockdown() then UIParent:Show() end
        SetUIVisibility(true)
    end
    ClearLog()
    Attach()
end

local function Leave()
    resumeAfterCombat = false
    if ns.ImmersionScene.AnyPlaying() then return end
    if fading then
        if to == 0 then Restore() end
    elseif not UIParent:IsShown() then
        ClearLog()
        BindBagKeys(false)
        Fade(0, 1) -- first, so the interface reappears transparent
        UIParent:SetAlpha(0)
        -- See Restore.
        if not InCombatLockdown() then UIParent:Show() end
        SetUIVisibility(true)
    end
    ns.FishingDisplay.Update()
end

ns.ImmersionMode = {
    IsOn = IsOn, Enter = Enter, Leave = Leave,
    IsResuming = function() return resumeAfterCombat end,
}

local toggle = CreateFrame("Button", "TinkerwiseImmersionToggle")
toggle:SetScript("OnClick", function()
    if UIParent:IsShown() then Enter() else Leave() end
end)

-- The interface can come back another way, such as the normal key in combat.
UIParent:HookScript("OnShow", function()
    if db and not fading and not togglingBags then
        BindBagKeys(false)
        letterbox:Hide()
        ClearLog()
        Attach()
    end
end)

local function ApplyBinding()
    if not db or InCombatLockdown() then return end
    ClearOverrideBindings(toggle)
    local key1, key2 = GetBindingKey("TOGGLEUI")
    if key1 then SetOverrideBindingClick(toggle, false, key1, "TinkerwiseImmersionToggle") end
    if key2 then SetOverrideBindingClick(toggle, false, key2, "TinkerwiseImmersionToggle") end
    BindBagKeys(IsOn())
end

local function CancelFade()
    if not fading then return end
    fading = false
    driver:Hide()
    UIParent:SetAlpha(1)
    letterbox:Hide()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, message)
    if event == "CHAT_MSG_LOOT" then
        OnLootMessage(message)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if IsOn() then
            resumeAfterCombat = resumable
            Restore()
        else
            CancelFade()
        end
        ClearOverrideBindings(toggle)
        ClearOverrideBindings(bagToggle)
    elseif not TW.modules.Immersion.active then
        -- Disabled in combat (see OnDisable): only this cleanup was left to do.
        events:UnregisterAllEvents()
        ClearOverrideBindings(toggle)
        ClearOverrideBindings(bagToggle)
        Attach()
    else
        ApplyBinding()
        if UIParent:IsShown() and not fading then Attach() end
        if event == "PLAYER_REGEN_ENABLED" and resumeAfterCombat then
            resumeAfterCombat = false
            Enter()
        end
    end
end)

local mod = TW:NewModule("Immersion", {
    title = L["Immersion Mode"],
    icon = "Interface\\Icons\\Spell_Shadow_Twilight",
    section = "Immersion",
    desc = L["The key that hides the interface (Alt+Z by default) fades it out and can keep a few elements on screen. Your bags can still be opened and your loot shows for a few seconds, with item details on hover. In combat, the interface comes back until the fight ends.\n\nThe optional quest scene stages the quests you open or turn in, with the interface shown or hidden: black bars, a slowly turning camera and text that writes itself. Click the screen to show it all at once. Out of combat only. The camera uses the game's view slot 5."]
        .. "\n\n" .. L["With Fishing Buddy and a fishing pole equipped, black bands add your fishing skill, the catches of the zone and of the session, and a ring showing the bobber's time left. The bobber stays clickable."],
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
        { type = "execute", label = L["Move / Lock"], func = function()
            log:SetScale(UIParent:GetEffectiveScale())
            log:ToggleMover()
            RenderLog()
        end },
        { type = "execute", label = L["Reset position"], func = function() log:ResetPosition() end },
        { type = "header", label = L["Fishing"] },
        { type = "toggle", key = "fishingDisplay", label = L["Show the fishing displays with a pole equipped"] },
        { type = "toggle", key = "fishingAuto", label = L["Start the mode when a pole is equipped"] },
        { type = "execute", label = L["Test (15 s)"], func = function() ns.FishingDisplay.Test() end },
    },
})

function mod:OnEnable()
    db = self.db
    log:ApplyPosition()
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
                         "PLAYER_ENTERING_WORLD", "CHAT_MSG_LOOT" }) do
        events:RegisterEvent(e)
    end
    ApplyBinding()
    if db.questScene then ns.QuestScene.Enable(db) end
    if db.fishingDisplay then ns.FishingDisplay.Enable(db) end
end

function mod:OnOptionChanged(key)
    if key == "questScene" then
        ns.QuestScene.Disable()
        if db.questScene then ns.QuestScene.Enable(db) end
    elseif key == "fishingDisplay" then
        ns.FishingDisplay.Disable()
        if db.fishingDisplay then ns.FishingDisplay.Enable(db) end
    end
end

function mod:OnDisable()
    ns.QuestScene.Disable()
    ns.FishingDisplay.Disable()
    resumeAfterCombat = false
    events:UnregisterAllEvents()
    CancelFade()
    letterbox:Hide()
    log:Lock()
    ClearLog()
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ClearOverrideBindings(toggle)
        ClearOverrideBindings(bagToggle)
        Attach()
    end
end

function mod:SetEditMode(on)
    log:SetScale(UIParent:GetEffectiveScale())
    log:SetUnlocked(on)
    RenderLog()
end
