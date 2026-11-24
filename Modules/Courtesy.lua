-- Courtesy: one button that offers, in this order, to thank (and buff back) whoever just buffed you,
-- to buff yourself and to buff the first member of your group who lacks your buff. The thanks (an
-- emote) can also go out by themselves; buffing back stays a click.
--
-- The button casts through a secure macro, so it only changes outside combat: it hides when a fight
-- starts and comes back after. WoW Forever gives addons no combat log, so a buff from somebody is
-- spotted by watching your own buffs appear and reading who cast them (aura.sourceUnit): a stranger
-- the game has no unit for (no nameplate) cannot be named, and is not thanked.

local _, ns = ...
local L = ns.L
local TW = ns.TW

local DEFAULTS = {
    self = true,
    group = true,
    thanks = true,
    autoThanks = true, -- the /thank emote goes out by itself; the card only offers to buff back
    buffBack = true,
    track = true,
    size = 40,
    point = "TOP", x = 0, y = -140,
}

local db -- the module's saved settings, once enabled

local FAVOUR_SECONDS = 90  -- how long a favour waits for its thanks
local THANKED_SECONDS = 300 -- the same person is not thanked twice within this
local REBUFF_SECONDS = 120  -- a buff of yours with this little left is offered again
local THANKS_ICON = "Interface\\Icons\\INV_Misc_Gift_01"

---------------------------------------------------------------------------
-- The buffs (vanilla spells, as on WoW Forever): every rank, highest first, and the group version.
-- Cast by name, the game takes the best rank you know.
---------------------------------------------------------------------------

local BUFFS = {
    intellect = { ranks = { 10157, 10156, 1461, 1460, 1459 }, group = { 23028 }, manaOnly = true },
    fortitude = { ranks = { 10938, 10937, 2791, 1245, 1244, 1243 }, group = { 21564, 21562 } },
    spirit = { ranks = { 27841, 14819, 14818, 14752 }, group = { 27681 }, manaOnly = true },
    shadow = { ranks = { 10958, 10957, 976 }, group = { 27683 } },
    motw = { ranks = { 9885, 9884, 8907, 5234, 6756, 5232, 1126 }, group = { 21850, 21849 } },
    thorns = { ranks = { 9910, 9756, 8914, 1075, 782, 467 } },
    wisdom = { ranks = { 25290, 19854, 19853, 19852, 19850, 19742 }, group = { 25918, 25894 }, blessing = true },
    might = { ranks = { 25291, 19838, 19837, 19836, 19835, 19834, 19740 }, group = { 25916, 25782 }, blessing = true },
    kings = { ranks = { 20217 }, group = { 25898 }, blessing = true },
    salvation = { ranks = { 1038 }, group = { 25895 }, blessing = true },
    light = { ranks = { 19979, 19978, 19977 }, group = { 25890 }, blessing = true },
    sanctuary = { ranks = { 20914, 20913, 20912, 20911 }, group = { 25899 }, blessing = true },
    breath = { ranks = { 5697 }, group = { 131 }, swimOnly = true }, -- only offered in the water
    battleshout = { ranks = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 }, selfCast = true },

    -- Buffs only for yourself (ranks as Manners has them for Forever: Demon Skin is Demon Armor's
    -- first ranks there, and Ice Armor Frost Armor's last ones).
    demonarmor = { ranks = { 11735, 11734, 11733, 1086, 706, 696, 687 }, selfCast = true },
    felarmor = { ranks = { 403619 }, selfCast = true },
    frostarmor = { ranks = { 10220, 10219, 7320, 7302, 7301, 7300, 168 }, selfCast = true },
    magearmor = { ranks = { 22783, 22782, 6117 }, selfCast = true },
    innerfire = { ranks = { 10952, 10951, 1006, 602, 7128, 588 }, selfCast = true },
    lightningshield = { ranks = { 10432, 10431, 8134, 945, 905, 325, 324 }, selfCast = true },
    watershield = { ranks = { 408510 }, selfCast = true },
    devotionaura = { ranks = { 10293, 10292, 1032, 10291, 643, 10290, 465 }, selfCast = true },
    retributionaura = { ranks = { 10301, 10300, 10299, 10298, 7294 }, selfCast = true },
    concentrationaura = { ranks = { 19746 }, selfCast = true },
    shadowresaura = { ranks = { 19896, 19895, 19876 }, selfCast = true },
    frostresaura = { ranks = { 19898, 19897, 19888 }, selfCast = true },
    fireresaura = { ranks = { 19900, 19899, 19891 }, selfCast = true },
    sanctityaura = { ranks = { 20218 }, selfCast = true },
    aspecthawk = { ranks = { 25296, 14322, 14321, 14320, 14319, 14318, 13165 }, selfCast = true },
    aspectmonkey = { ranks = { 13163 }, selfCast = true },
    aspectwild = { ranks = { 20190, 20043 }, selfCast = true },
    aspectbeast = { ranks = { 1299447, 1299446, 1299445, 13161 }, selfCast = true },
    aspectcheetah = { ranks = { 5118 }, selfCast = true },
    aspectpack = { ranks = { 13159 }, selfCast = true },
    aspectfalcon = { ranks = { 469145 }, selfCast = true },
    aspectviper = { ranks = { 415423 }, selfCast = true },
}

-- Your own buffs, by class: each family is satisfied by any of its buffs, and the first one you
-- know is offered when you wear none (the ones only worth wearing now and then come last).
local OWN_BUFFS = {
    WARLOCK = { { "felarmor", "demonarmor" } },
    MAGE = { { "frostarmor", "magearmor" } },
    PRIEST = { { "innerfire" } },
    SHAMAN = { { "lightningshield", "watershield" } },
    PALADIN = { { "devotionaura", "retributionaura", "concentrationaura", "sanctityaura",
                  "shadowresaura", "frostresaura", "fireresaura" } },
    HUNTER = { { "aspecthawk", "aspectmonkey", "aspectwild", "aspectbeast", "aspectfalcon",
                 "aspectviper", "aspectcheetah", "aspectpack" } },
}

-- What each class hands out, in the order it is offered. A paladin's blessing is picked per person
-- (Blessing below), so the list only says the class has them.
local CLASS_BUFFS = {
    MAGE = { "intellect" },
    PRIEST = { "fortitude", "spirit" },
    DRUID = { "motw" },
    PALADIN = { "blessing" },
    WARRIOR = { "battleshout" },
    WARLOCK = { "breath" },
}

local BLESSINGS = { "kings", "might", "wisdom", "salvation", "light", "sanctuary" }

-- The buffs your class may offer, as the options list them: your own first, then what you hand out.
local function ClassBuffKeys()
    local class = select(2, UnitClass("player"))
    local keys = {}
    for _, family in ipairs(OWN_BUFFS[class] or {}) do
        for _, key in ipairs(family) do keys[#keys + 1] = key end
    end
    for _, key in ipairs(CLASS_BUFFS[class] or {}) do
        if key == "blessing" then
            for _, blessing in ipairs(BLESSINGS) do keys[#keys + 1] = blessing end
        else
            keys[#keys + 1] = key
        end
    end
    return keys
end

-- Tracking: only one at a time. The gathering ones are offered, first known first, when nothing is
-- tracked; any of the others (a hunter's, a paladin's...) already takes the slot.
local TRACK_OFFERED = {
    { id = 2383 }, -- Find Herbs
    { id = 2580 }, -- Find Minerals
    { id = 2481 }, -- Find Treasure
}
local TRACK_IDS = { 2383, 2580, 2481, 1494, 19883, 19884, 19885, 19880, 19878, 19882, 19879, 5225, 5502, 5500 }

-- Every spell id of a buff somebody else can put on you: what counts as a favour.
local FAVOUR_IDS = {}
for _, buff in pairs(BUFFS) do
    if not buff.selfCast then
        for _, id in ipairs(buff.ranks) do FAVOUR_IDS[id] = true end
        for _, id in ipairs(buff.group or {}) do FAVOUR_IDS[id] = true end
    end
end

local issecretvalue = _G.issecretvalue
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture(id)
end

-- Forever keeps IsSpellKnown and IsPlayerSpell only as optional shims: ask the spell book first.
local function SpellKnown(id)
    local book = C_SpellBook
    if book then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        if book.IsSpellInSpellBook then
            local ok, known = pcall(book.IsSpellInSpellBook, id, bank, false)
            if ok and known then return true end
        end
        if book.IsSpellKnown then
            local ok, known = pcall(book.IsSpellKnown, id, bank)
            if ok and known then return true end
        end
    end
    for _, fn in ipairs({ _G.IsSpellKnown, _G.IsPlayerSpell }) do
        local ok, known = pcall(fn, id)
        if ok and known then return true end
    end
    return false
end

ns.Spells = { Name = SpellName, Icon = SpellIcon, Known = SpellKnown, Plain = Plain } -- also for the class bar

local function Knows(key)
    for _, id in ipairs(BUFFS[key].ranks) do
        if SpellKnown(id) then return true end
    end
    return false
end

-- The names that show the buff is there: every rank's (a rank may carry another name, as Demon
-- Skin) and its group version's.
local function AuraNames(key)
    local buff = BUFFS[key]
    if not buff.names then
        local names, seen = {}, {}
        local ids = {}
        for _, id in ipairs(buff.ranks) do ids[#ids + 1] = id end
        for _, id in ipairs(buff.group or {}) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            local name = SpellName(id)
            if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
        end
        buff.names = names
    end
    return buff.names
end

-- The spell to cast: the name of the best rank you know, so a rank renamed on the way still casts.
local function CastId(key)
    local ranks = BUFFS[key].ranks
    for _, id in ipairs(ranks) do
        if SpellKnown(id) then return id end
    end
    return ranks[#ranks]
end

-- The buff's name in the options: every name its ranks carry, lowest first ("Frost Armor / Ice
-- Armor"), so it stays the same as you learn ranks and the unticked boxes keep their meaning.
local function OptionName(key)
    local buff = BUFFS[key]
    if buff.optionName then return buff.optionName end
    local names, seen, complete = {}, {}, true
    for i = #buff.ranks, 1, -1 do
        local name = SpellName(buff.ranks[i])
        if not name then complete = false
        elseif not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    local label = #names > 0 and table.concat(names, " / ") or key
    if complete then buff.optionName = label end
    return label
end

-- Whether the buff is ticked in the options (db.skipBuffs holds the unticked names).
local function Wanted(key)
    local skipped = db and db.skipBuffs
    return not (skipped and skipped[OptionName(key)])
end

local function CastName(key) return SpellName(CastId(key)) end
local function CastIcon(key) return SpellIcon(CastId(key)) end

-- Whether the unit wears the aura, and when it runs out (nil when the game keeps it secret).
local function FindAura(unit, name)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local aura = Plain(C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL"))
        return aura ~= nil, aura and Plain(aura.expirationTime)
    end
    if AuraUtil then
        local found, _, _, _, _, expires = AuraUtil.FindAuraByName(name, unit, "HELPFUL")
        return found ~= nil, Plain(expires)
    end
    return false
end

local function HasAura(unit, name)
    return (FindAura(unit, name))
end

local function Wears(unit, key)
    for _, name in ipairs(AuraNames(key)) do
        if HasAura(unit, name) then return true end
    end
    return false
end

-- When the buff the unit wears runs out, if that is within REBUFF_SECONDS; nil otherwise (not
-- worn, lasting, never running out or kept secret).
local function FadingExpires(unit, key)
    local latest
    for _, name in ipairs(AuraNames(key)) do
        local found, expires = FindAura(unit, name)
        if found then
            if not (expires and expires > 0) then return nil end
            if expires - GetTime() > REBUFF_SECONDS then return nil end
            latest = math.max(latest or 0, expires)
        end
    end
    return latest
end

-- Whether the unit wears the buff with more than REBUFF_SECONDS left. A buff that never runs out
-- (an aura, an aspect) or whose end the game keeps secret counts as lasting.
local function WearsLasting(unit, key)
    for _, name in ipairs(AuraNames(key)) do
        local found, expires = FindAura(unit, name)
        if found and not (expires and expires > 0 and expires - GetTime() <= REBUFF_SECONDS) then
            return true
        end
    end
    return false
end

local MANA_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true }

-- A paladin's blessing for this person: Kings when known, else Wisdom for casters, else Might.
-- Nil when they already wear a blessing, since one paladin's blessings do not stack. With rebuff
-- (your own), a blessing about to run out is offered again when you know it.
local function Blessing(unit, class, rebuff)
    for _, key in ipairs(BLESSINGS) do
        if unit and Wears(unit, key) then
            if rebuff and not WearsLasting(unit, key) and Knows(key) and Wanted(key) then return key end
            return nil
        end
    end
    local function Can(key) return Knows(key) and Wanted(key) end
    if Can("kings") then return "kings" end
    if CASTERS[class] and Can("wisdom") then return "wisdom" end
    if Can("might") then return "might" end
    if Can("wisdom") then return "wisdom" end
end

-- Whether you are in the water: the buffs only worth having there (Unending Breath) wait for it.
local function InWater()
    for _, check in ipairs({ _G.IsSubmerged, _G.IsSwimming }) do
        if check and Plain(check()) then return true end
    end
    return false
end

local function Worthwhile(key)
    return not BUFFS[key].swimOnly or InWater()
end

-- The first of my buffs this unit lacks, or nil. Without a unit (a stranger now out of reach)
-- nothing can be checked, and the first one I know is offered.
local function MissingBuff(unit, class)
    local mine = CLASS_BUFFS[select(2, UnitClass("player"))]
    if not mine then return nil end
    local hasMana = unit and UnitPowerType(unit) == 0 or (not unit and MANA_CLASSES[class])
    for _, key in ipairs(mine) do
        if key == "blessing" then
            local blessing = Blessing(unit, class)
            if blessing then return blessing end
        elseif not BUFFS[key].selfCast and Knows(key) and Wanted(key) and Worthwhile(key) and (hasMana or not BUFFS[key].manaOnly)
            and not (unit and Wears(unit, key)) then
            return key
        end
    end
end

-- Whether some tracking is on. Asked three ways, since clients differ: the minimap's tracking list
-- (newer clients), the tracking texture (older ones) and the tracking aura on you.
local function Tracking()
    local tracked = {}
    for _, id in ipairs(TRACK_IDS) do
        tracked[id] = true
        local name = SpellName(id)
        if name then
            tracked[name] = true
            if HasAura("player", name) then return true end
        end
    end
    local minimap = C_Minimap
    if minimap and minimap.GetNumTrackingTypes and minimap.GetTrackingInfo then
        for i = 1, minimap.GetNumTrackingTypes() or 0 do
            local info = minimap.GetTrackingInfo(i)
            if type(info) == "table" and Plain(info.active)
                and (tracked[Plain(info.spellID) or 0] or tracked[Plain(info.name) or ""]) then
                return true
            end
        end
    end
    if _G.GetTrackingTexture and Plain(GetTrackingTexture()) then return true end
    return false
end

-- The tracking to offer, or nil.
local function MissingTracking()
    if Tracking() then return nil end
    for _, track in ipairs(TRACK_OFFERED) do
        if SpellKnown(track.id) then return track.id end
    end
end

local function CanReach(unit, key)
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return false end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    local name = CastName(key)
    if C_Spell and C_Spell.IsSpellInRange and name then
        return Plain(C_Spell.IsSpellInRange(name, unit)) ~= false
    end
    return true
end

---------------------------------------------------------------------------
-- Favours: somebody's buff appearing on you
---------------------------------------------------------------------------

local favour        -- { name = "Name-Realm", unit = token when seen, class = "MAGE", time = GetTime() }
local thanked = {}  -- name -> GetTime() of the thanks

local function UnitForName(name)
    -- A name the game keeps secret (a stranger under the mouse) cannot be compared: not that one.
    local function Is(unit) return UnitExists(unit) and Plain(GetUnitName(unit, true)) == name end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
        if Is(unit) then return unit end
    end
    local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
    for i = 1, count do
        if Is(prefix .. i) then return prefix .. i end
    end
    if favour and favour.unit and Is(favour.unit) then return favour.unit end
end

local Schedule -- set further down

-- Automatic thanks: the /thank emote, a moment after the buff lands. Buffing back is a spell, so it
-- still waits for a click on the card.
local function AutoThank(name)
    C_Timer.After(1, function()
        if not favour or favour.name ~= name or favour.thanked or not db or not db.autoThanks then return end
        local unit = UnitForName(name)
        pcall(DoEmote, "THANK", unit or name)
        favour.thanked = true
        thanked[name] = GetTime()
        Schedule()
    end)
end

-- A stranger the game does not name: a /thank without a target ("you thank someone near you"),
-- through the "none" unit so that the current target is not the one thanked. At most once a minute.
local STRANGER_SECONDS = 60
local strangerThankedAt = -STRANGER_SECONDS
local function AutoThankStranger()
    if not (db and db.thanks and db.autoThanks) or GetTime() - strangerThankedAt < STRANGER_SECONDS then return end
    strangerThankedAt = GetTime()
    C_Timer.After(1, function() pcall(DoEmote, "THANK", "none") end)
end

local function NoteFavours(info)
    -- The game may hide the whole update (secret values): nothing to read then.
    if not info or Plain(info.isFullUpdate) ~= false then return end
    local added = Plain(info.addedAuras)
    if type(added) ~= "table" then return end
    for _, aura in ipairs(added) do
        local id, source = Plain(aura.spellId), Plain(aura.sourceUnit)
        if id and FAVOUR_IDS[id] and source and Plain(aura.isHelpful) ~= false
            and not UnitIsUnit(source, "player") and UnitIsPlayer(source) then
            local name = Plain(GetUnitName(source, true))
            local last = name and thanked[name]
            if name and not (last and GetTime() - last < THANKED_SECONDS) then
                favour = { name = name, unit = source, class = select(2, UnitClass(source)), time = GetTime() }
                if db and db.thanks and db.autoThanks then AutoThank(name) end
            elseif not name then
                AutoThankStranger()
            end
        elseif id and FAVOUR_IDS[id] and not source and Plain(aura.isHelpful) ~= false
            and Plain(aura.isFromPlayerOrPlayerPet) == false then
            AutoThankStranger() -- cast by somebody else, whom the game does not name
        end
    end
end

---------------------------------------------------------------------------
-- The card: the spell's icon with a slow glow, what the click does in the theme's color, and for
-- whom below it, on a dark card. The whole card is the secure button: a click anywhere does it.
---------------------------------------------------------------------------

local PAD, GAP, MIN_WIDTH = 6, 10, 150

local container = CreateFrame("Frame", "TinkerwiseCourtesyFrame", UIParent, "BackdropTemplate")
container:SetSize(MIN_WIDTH, 52)
container:Hide()
container:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
TW:CreateMover(container, function() return db end, L["Buffs and Thanks"], DEFAULTS)

local iconFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
iconFrame:SetPoint("LEFT", PAD, 0)
iconFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

local glow = iconFrame:CreateTexture(nil, "BACKGROUND")
glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
glow:SetBlendMode("ADD")
glow:SetPoint("CENTER")

local icon = iconFrame:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", 1, -1)
icon:SetPoint("BOTTOMRIGHT", -1, 1)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("BOTTOMLEFT", iconFrame, "RIGHT", GAP, 1)
title:SetJustifyH("LEFT")

local detail = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detail:SetPoint("TOPLEFT", iconFrame, "RIGHT", GAP, -2)
detail:SetJustifyH("LEFT")

local accent, rim = { 1, 0.82, 0 }, { 0.6, 0.5, 0.35 }
TW:OnTheme(function(theme)
    accent, rim = theme.accent, theme.border
    local s = theme.solid
    container:SetBackdropColor(s[1], s[2], s[3], 0.92)
    container:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
    title:SetTextColor(accent[1], accent[2], accent[3])
    glow:SetVertexColor(accent[1], accent[2], accent[3])
end)

-- A short fade each time the card comes up.
local fade = container:CreateAnimationGroup()
local alpha = fade:CreateAnimation("Alpha")
alpha:SetFromAlpha(0)
alpha:SetToAlpha(1)
alpha:SetDuration(0.25)
alpha:SetSmoothing("OUT")
container:SetScript("OnShow", function() fade:Play() end)

-- A buff of yours still on you counts down after its name: "Frost Armor  ·  1:42".
local countdown, countdownDetail -- the buff's expirationTime, and the detail without the time
local DOT = "  |cff808080\194\183|r  " -- a grey middle dot between the name and the spell

local function CountdownText(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return format("%s%s|cffffffff%d:%02d|r", countdownDetail, DOT, math.floor(seconds / 60), seconds % 60)
end

-- The glow breathes slowly while the card is up, and the countdown ticks (a few times a second,
-- only while the card is shown: it is hidden during any fight).
local t, sinceTick = 0, 0
container:SetScript("OnUpdate", function(_, elapsed)
    t = t + elapsed
    glow:SetAlpha(0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 2.2)))
    if not countdown then return end
    sinceTick = sinceTick + elapsed
    if sinceTick < 0.25 then return end
    sinceTick = 0
    local left = countdown - GetTime()
    if left > 0 then
        detail:SetText(CountdownText(left))
    else
        -- Gone: back to the plain card, and let the next refresh see the buff missing.
        countdown = nil
        detail:SetText(countdownDetail)
        Schedule()
    end
end)

local button = CreateFrame("Button", "TinkerwiseCourtesyButton", container, "SecureActionButtonTemplate")
button:SetAllPoints()
button:SetFrameLevel(container:GetFrameLevel() + 5)
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("type", "macro")
local hover = button:CreateTexture(nil, "HIGHLIGHT")
hover:SetPoint("TOPLEFT", 3, -3)
hover:SetPoint("BOTTOMRIGHT", -3, 3)
hover:SetColorTexture(1, 1, 1, 0.06)

button:SetScript("OnEnter", function(self)
    container:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    if not self.text then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.text, 1, 1, 1)
    GameTooltip:AddLine(L["Click to do it"], accent[1], accent[2], accent[3])
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
    container:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
    GameTooltip:Hide()
end)

-- A name in its class color.
local function Colored(name, class)
    local color = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    return color and format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name) or name
end

-- What the next click does, or nil: { icon, title, detail, text (tooltip), macro, thanks = name }.
local function NextAction()
    local now = GetTime()
    if favour and now - favour.time > FAVOUR_SECONDS then favour = nil end
    if favour and db.thanks then
        local unit = UnitForName(favour.name)
        local key = db.buffBack and MissingBuff(unit, favour.class)
        local name = favour.name
        local action = { icon = THANKS_ICON, title = L["Thank"], detail = Colored(name, favour.class),
                         text = format(L["Thank %s"], name), thanks = name }
        local canBuffBack = key and (not unit or CanReach(unit, key))
        -- Thanked automatically: the card is only there to buff back.
        if db.autoThanks then
            if canBuffBack then
                local spell = CastName(key)
                action.title = L["Buff back"]
                action.detail = action.detail .. DOT .. spell
                action.text = format(L["Give %s back to %s"], spell, name)
                action.icon = CastIcon(key) or THANKS_ICON
                action.macro = "/targetexact " .. name .. "\n/cast " .. spell .. "\n/targetlasttarget"
                return action
            end
        else
            local macro = "/targetexact " .. name .. "\n/thank"
            if canBuffBack then
                local spell = CastName(key)
                macro = macro .. "\n/cast " .. spell
                action.title = L["Thank and buff back"]
                action.detail = action.detail .. DOT .. spell
                action.text = format(L["Thank %s and give %s back"], name, spell)
                action.icon = CastIcon(key) or THANKS_ICON
            end
            action.macro = macro .. "\n/targetlasttarget"
            return action
        end
    end

    local class = select(2, UnitClass("player"))
    local mine = CLASS_BUFFS[class] or {}

    local function Self(key, macro)
        local spell = CastName(key)
        return { icon = CastIcon(key), title = L["Buff yourself"], detail = spell,
                 text = format(L["Buff yourself: %s"], spell), macro = macro .. spell,
                 expires = FadingExpires("player", key) } -- still on you: the card counts down
    end

    if db.self then
        -- Your own buffs first (an armor, an aura, an aspect): any of a family will do. One about
        -- to run out (REBUFF_SECONDS) is offered again, the same one you wear.
        for _, family in ipairs(OWN_BUFFS[class] or {}) do
            local worn, fading, offer = false, nil, nil
            for _, key in ipairs(family) do
                if WearsLasting("player", key) then worn = true break end
                if not fading and Wears("player", key) and Knows(key) and Wanted(key) then fading = key end
                if not offer and Knows(key) and Wanted(key) then offer = key end
            end
            offer = fading or offer
            if not worn and offer then return Self(offer, "/cast ") end
        end
        for _, key in ipairs(mine) do
            local wanted = key
            if key == "blessing" then wanted = Blessing("player", class, true) end
            local buff = wanted and BUFFS[wanted]
            if buff and Knows(wanted) and Wanted(wanted) and Worthwhile(wanted) and (UnitPowerType("player") == 0 or not buff.manaOnly)
                and not WearsLasting("player", wanted) then
                return Self(wanted, buff.selfCast and "/cast " or "/cast [@player] ")
            end
        end
    end

    if db.group and IsInGroup() then
        local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local unitClass = select(2, UnitClass(unit))
                local key = MissingBuff(unit, unitClass)
                if key and CanReach(unit, key) then
                    local spell, name = CastName(key), Plain(GetUnitName(unit, false)) or unit
                    return { icon = CastIcon(key), title = L["Buff the group"],
                             detail = Colored(name, unitClass) .. DOT .. spell,
                             text = format(L["Buff %s: %s"], name, spell),
                             macro = "/cast [@" .. unit .. "] " .. spell }
                end
            end
        end
    end

    if db.track then
        local id = MissingTracking()
        local spell = id and SpellName(id)
        if spell then
            return { icon = SpellIcon(id), title = L["Start tracking"], detail = spell,
                     text = format(L["Start tracking: %s"], spell), macro = "/cast " .. spell }
        end
    end
end

local inEncounter = false -- between ENCOUNTER_START and ENCOUNTER_END

-- Whether the fight is on, even before the game locks the secure button: you are flagged, a boss
-- encounter runs (it may drop you out of combat for a phase), or somebody in your group already
-- fights (the tank pulls the boss a moment before the rest of you are flagged).
local function Fighting()
    if inEncounter or (_G.IsEncounterInProgress and Plain(IsEncounterInProgress())) then return true end
    local v = UnitAffectingCombat("player")
    if v or (issecretvalue and issecretvalue(v)) then return true end
    if IsInGroup() then
        local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit) then
                v = UnitAffectingCombat(unit)
                if v and not (issecretvalue and issecretvalue(v)) then return true end
            end
        end
    end
    return false
end

-- Nothing to offer while dead, on a flight path, out of control of your character or while a fight
-- is on. An answer the game keeps secret counts as busy.
local function Busy()
    if Fighting() then return true end
    for _, check in ipairs({ UnitIsDeadOrGhost, UnitOnTaxi }) do
        local v = check("player")
        if issecretvalue and issecretvalue(v) then return true end
        if v then return true end
    end
    if HasFullControl then
        local control = HasFullControl()
        if (issecretvalue and issecretvalue(control)) or not control then return true end
    end
    return false
end

local function Refresh()
    if not db or InCombatLockdown() then return end
    local action = not Busy() and NextAction() or nil -- nil, not false: SetShown below tests ~= nil
    if not action and container:IsUnlocked() then
        action = { icon = THANKS_ICON, title = L["Buffs and Thanks"], detail = L["Drag to move"], macro = "" }
    end
    button.text = action and action.text
    button.thanks = action and action.thanks
    button:SetAttribute("macrotext", action and action.macro or "")
    if action then
        local size = db.size
        iconFrame:SetSize(size, size)
        glow:SetSize(size * 1.75, size * 1.75)
        icon:SetTexture(action.icon or THANKS_ICON)
        title:SetText(action.title)
        countdownDetail = action.detail or ""
        countdown = action.expires and action.expires > GetTime() and action.expires or nil
        sinceTick = 0
        -- Sized for the widest time ("0:00" digits are about as wide as any), so it never jitters.
        detail:SetText(countdown and CountdownText(0) or countdownDetail)
        local textWidth = math.max(title:GetStringWidth(), detail:GetStringWidth())
        if countdown then detail:SetText(CountdownText(countdown - GetTime())) end
        container:SetSize(math.max(MIN_WIDTH, PAD + size + GAP + textWidth + 14), size + 2 * PAD)
    end
    container:SetShown(action ~= nil)
end

button:SetScript("PostClick", function(self)
    if self.thanks then
        thanked[self.thanks] = GetTime()
        favour = nil
    end
    C_Timer.After(0.5, Refresh)
end)

local pending
function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        if TW.modules.Courtesy.active then Refresh() end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, info)
    if event == "ENCOUNTER_START" then inEncounter = true end
    if event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then inEncounter = false end
    if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
        -- The last moment the secure button may still be hidden before the fight locks it.
        if not InCombatLockdown() then container:Hide() end
        return
    end
    if event == "UNIT_AURA" then
        if unit == "player" then NoteFavours(info) end
        if InCombatLockdown() then return end
    end
    Schedule()
end)

local ticker

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local mod = TW:NewModule("Courtesy", {
    title = L["Buffs and Thanks"],
    icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    section = L["Group"],
    desc = L["Shows a button, outside combat, to buff yourself, to buff the members of your group who lack your buff, to thank whoever buffs you (buffing them back when you can) and to turn tracking back on. The thanks can also go out by themselves: the button then only offers to buff back."],
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "self", label = L["Buff myself"] },
        { type = "toggle", key = "group", label = L["Buff my group"] },
        { type = "toggle", key = "thanks", label = L["Thank whoever buffs me"] },
        { type = "toggle", key = "autoThanks", label = L["Thank automatically"] },
        { type = "toggle", key = "buffBack", label = L["Buff them back when I can"] },
        { type = "toggle", key = "track", label = L["Track herbs, minerals or treasures"] },
        { type = "slider", key = "size", label = L["Icon size"], min = 24, max = 80, step = 2 },
        { type = "execute", label = L["Move / Lock"], func = function()
            if InCombatLockdown() then return end
            container:ToggleMover()
            Refresh()
        end },
        { type = "execute", label = L["Reset position"], func = function()
            if not InCombatLockdown() then container:ResetPosition() end
        end },
    },
})

-- One box per buff of your class (none for a class without any): an unticked one is never
-- offered, to you or to your group.
if #ClassBuffKeys() > 0 then
    mod.options[#mod.options + 1] = { type = "header", label = L["Buffs to offer"] }
    mod.options[#mod.options + 1] = { type = "checklist", key = "skipBuffs", items = function()
        local names = {}
        for _, key in ipairs(ClassBuffKeys()) do names[#names + 1] = OptionName(key) end
        return names
    end }
end

function mod:OnEnable()
    db = self.db
    -- The card used to sit in the middle of the screen: an untouched position moves to the top.
    if db.point == "CENTER" and db.x == 0 and db.y == -160 then
        db.point, db.x, db.y = DEFAULTS.point, DEFAULTS.x, DEFAULTS.y
    end
    if not InCombatLockdown() then container:ApplyPosition() end
    for _, e in ipairs({ "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
                         "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_TARGET_CHANGED",
                         "MINIMAP_UPDATE_TRACKING", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
                         "ENCOUNTER_START", "ENCOUNTER_END" }) do
        pcall(events.RegisterEvent, events, e)
    end
    -- Group members walk in and out of range, and into a fight, without any event.
    ticker = C_Timer.NewTicker(2, Schedule)
    Refresh()
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
    favour = nil
    if not InCombatLockdown() then
        container:Lock()
        container:Hide()
    end
end

function mod:OnOptionChanged()
    Refresh()
end

function mod:SetEditMode(on)
    if InCombatLockdown() then return end
    container:SetUnlocked(on)
    Refresh()
end
