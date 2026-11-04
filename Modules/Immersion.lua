-- Immersion: the "hide interface" key (Alt+Z) fades the interface in and out, can keep a few
-- chosen elements on screen and lists recent loot for a few seconds.
-- Kept elements are detached from the interface while it is hidden. Action bars are deliberately
-- not offered. In combat the normal key behavior stays, as protected frames cannot be detached.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local DEFAULTS = {
    duration = 1,
    keepMinimap = false,
    keepPlayer = false,
    keepTarget = false,
    keepNameplates = false,
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
    keepPlayer = { "PlayerFrame" },
    keepTarget = { "TargetFrame" },
    keepChat = { "ChatFrame1" },
    -- Not an option: always kept. The tooltip is there for the quest rewards.
    -- The game places these itself each time they are shown, so they are not pinned.
    always = { "QuestFrame", "GossipFrame", "GameTooltip" },
    keepTinkerwise = {
        "TinkerwiseSessionFrame", "TinkerwiseWeaponSkillsFrame", "TinkerwiseStatDeltaFrame",
        "TinkerwisePotionFrame", "TinkerwiseArmorAlertFrame",
        "TinkerwiseLowHealthVignette", "TinkerwiseAggroVignette",
    },
}

local FADE_OUT_TIME = 1 -- seconds a loot line takes to disappear
local MAX_LOOT = 6
local ROW_H = 28

local db
local fading, from, to, elapsedTime = false, 1, 1, 0
local detached = {} -- frame -> { parent, scale, strata, level, points }

---------------------------------------------------------------------------
-- Kept elements
---------------------------------------------------------------------------

local function Detach()
    if InCombatLockdown() then return end
    for option, names in pairs(KEPT_FRAMES) do
        if option == "always" or db[option] then
            for _, name in ipairs(names) do
                local f = _G[name]
                if f and not detached[f] then
                    local saved = { parent = f:GetParent(), scale = f:GetScale(),
                                    strata = f:GetFrameStrata(), level = f:GetFrameLevel() }
                    detached[f] = saved
                    local effectiveScale = f:GetEffectiveScale()
                    local left, top, width, height = f:GetLeft(), f:GetTop(), f:GetSize()
                    local points = {}
                    for i = 1, f:GetNumPoints() do points[i] = { f:GetPoint(i) } end
                    f:SetParent(nil)
                    f:SetScale(effectiveScale)
                    f:SetFrameStrata(saved.strata)
                    f:SetFrameLevel(saved.level)
                    -- Pin it where it is on screen: its anchors may depend on the hidden interface.
                    if option ~= "always" and left and top then
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
        f:SetParent(saved.parent)
        f:SetScale(saved.scale)
        f:SetFrameStrata(saved.strata)
        f:SetFrameLevel(saved.level)
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

local function OnLootMessage(message)
    if not db.lootLog or UIParent:IsShown() then return end
    for _, pattern in ipairs(LOOT_PATTERNS) do
        local link, count = message:match(pattern)
        if link then
            table.insert(entries, 1, { link = link, count = tonumber(count) or 1, time = GetTime() })
            entries[MAX_LOOT + 1] = nil
            for _, r in ipairs(rows) do r:SetAlpha(1) end
            log:SetScale(UIParent:GetEffectiveScale())
            RenderLog()
            return
        end
    end
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
            -- SetUIVisibility also hides the nameplates, which belong to the game world.
            if db.keepNameplates then UIParent:Hide() else SetUIVisibility(false) end
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

local toggle = CreateFrame("Button", "TinkerwiseImmersionToggle")
toggle:SetScript("OnClick", function()
    if fading or ns.QuestScene.IsPlaying() then return end -- the scene manages the interface's alpha
    if UIParent:IsShown() then
        Detach() -- kept elements must not fade with the rest
        ShowLetterbox()
        Fade(1, 0)
    else
        ClearLog()
        Fade(0, 1) -- first, so the interface reappears transparent
        UIParent:SetAlpha(0)
        -- It may have been hidden with UIParent:Hide(), which SetUIVisibility may not know about.
        if not InCombatLockdown() then UIParent:Show() end
        SetUIVisibility(true)
    end
end)

-- The interface can come back another way, such as the normal key in combat.
UIParent:HookScript("OnShow", function()
    if db and not fading then
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
        CancelFade()
        ClearOverrideBindings(toggle)
    elseif not TW.modules.Immersion.active then
        -- Disabled in combat (see OnDisable): only this cleanup was left to do.
        events:UnregisterAllEvents()
        ClearOverrideBindings(toggle)
        Attach()
    else
        ApplyBinding()
        if UIParent:IsShown() and not fading then Attach() end
    end
end)

local mod = TW:NewModule("Immersion", {
    title = L["Immersion Mode"],
    icon = "Interface\\Icons\\Spell_Shadow_Twilight",
    section = "Immersion",
    desc = L["The key that hides the interface (Alt+Z by default) fades it out and can keep a few elements on screen. Your loot shows for a few seconds, with item details on hover. In combat, the key behaves normally.\n\nThe optional quest scene stages the quests you open or turn in, with the interface shown or hidden: black bars, a slowly turning camera and text that writes itself. Click the screen to show it all at once. Out of combat only. The camera uses the game's view slot 5."],
    defaults = DEFAULTS,
    options = {
        { type = "slider", key = "duration", label = L["Fade duration (s)"], min = 0.1, max = 2, step = 0.1 },
        { type = "header", label = L["Keep visible"] },
        { type = "toggle", key = "keepMinimap", label = L["Minimap"] },
        { type = "toggle", key = "keepPlayer", label = L["Player frame"] },
        { type = "toggle", key = "keepTarget", label = L["Target frame"] },
        { type = "toggle", key = "keepNameplates", label = L["Nameplates"] },
        { type = "toggle", key = "keepChat", label = L["Main chat window"] },
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
end

function mod:OnOptionChanged(key)
    if key ~= "questScene" then return end
    ns.QuestScene.Disable()
    if db.questScene then ns.QuestScene.Enable(db) end
end

function mod:OnDisable()
    ns.QuestScene.Disable()
    events:UnregisterAllEvents()
    CancelFade()
    letterbox:Hide()
    log:Lock()
    ClearLog()
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ClearOverrideBindings(toggle)
        Attach()
    end
end

function mod:SetEditMode(on)
    log:SetScale(UIParent:GetEffectiveScale())
    log:SetUnlocked(on)
    RenderLog()
end
