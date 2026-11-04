-- MissingBuffs: reminds you of your class self-buff (armor, aspect, aura, poisons, weapon
-- imbue...) when you enter combat and/or regularly out of combat. Only spells you know are checked.

local _, ns = ...
local TW = ns.TW
local GetSpellInfo, UnitBuff = ns.API.GetSpellInfo, ns.API.UnitBuff

local DEFAULTS = {
    outCombat = true,   -- check every 30 s out of combat
    inCombat = true,    -- check when combat starts
    sound = true,
}

local CHECK_EVERY = 30   -- seconds, out of combat
local REPEAT_AFTER = 60  -- seconds before warning again about the same buff

-- Per class: { label, spell IDs that satisfy it (any rank 1 id), kind, combatOnly }
-- kind "aura" = look for a buff with one of these names, "weapon" = main hand enchant.
local CHECKS = {
    MAGE = { { "Armure (Givre / Glace / Mage)", { 168, 7302, 6117 } } },
    WARLOCK = { { "Peau / Armure démoniaque", { 687, 706 } } },
    PRIEST = { { "Feu intérieur", { 588 } } },
    DRUID = { { "Marque du fauve", { 1126, 21849 } } },
    PALADIN = { { "Bénédiction ou aura", {
        19740, 19742, 20217, 1038, 19977, 20911,              -- blessings
        25782, 25894, 25898, 25895, 25890, 25899,             -- greater blessings
        465, 7294, 19746, 19876, 19888, 19891, 20218,         -- auras
    } } },
    HUNTER = { { "Aspect", { 13163, 13165, 5118, 13159, 20043, 13161 } } },
    ROGUE = { { "Poison sur l'arme", { 2842 }, "weapon" } },                 -- Poisons skill
    SHAMAN = { { "Arme imprégnée", { 8017, 8024, 8033, 8232 }, "weapon" } }, -- Rockbiter, Flametongue...
    WARRIOR = { { "Cri de guerre", { 6673 }, "aura", true } },
}

local db
local lastWarned = {}

local function KnownNames(ids)
    local names, known = {}, false
    for _, id in ipairs(ids) do
        local name = GetSpellInfo(id)
        if name then
            names[name] = true
            -- GetSpellInfo(name) only answers for spells in the spellbook
            if GetSpellInfo(name) then known = true end
        end
    end
    return names, known
end

local function HasBuff(names)
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then return false end
        if names[name] then return true end
    end
    return false
end

local function Missing(inCombat)
    local _, class = UnitClass("player")
    local missing = {}
    for _, check in ipairs(CHECKS[class] or {}) do
        local label, ids, kind, combatOnly = check[1], check[2], check[3] or "aura", check[4]
        if not combatOnly or inCombat then
            local names, known = KnownNames(ids)
            if known then
                local ok
                if kind == "weapon" then
                    ok = GetWeaponEnchantInfo() -- hasMainHandEnchant
                else
                    ok = HasBuff(names)
                end
                if not ok then missing[#missing + 1] = label end
            end
        end
    end
    return missing
end

local function Warn(inCombat)
    if not db then return end
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or IsMounted() then return end
    local now = GetTime()
    for _, label in ipairs(Missing(inCombat)) do
        if not lastWarned[label] or now - lastWarned[label] >= REPEAT_AFTER then
            lastWarned[label] = now
            local text = "Buff manquant : " .. label
            RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
            TW:Print("|cffffa020" .. text .. "|r")
            if db.sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if db.inCombat then Warn(true) end
end)
local ticker

local mod = TW:NewModule("MissingBuffs", {
    title = "Buffs manquants",
    section = "Préparation",
    icon = "Interface\\Icons\\Spell_Frost_FrostArmor02",
    desc = "Vous rappelle votre buff de classe : armure du mage ou du démoniste, Feu intérieur, Marque du fauve, bénédiction ou aura du paladin, aspect du chasseur, poison du voleur, arme imprégnée du chaman, Cri de guerre en combat. Seuls les sorts que vous connaissez sont vérifiés.",
    defaults = DEFAULTS,
    options = {
        { type = "toggle", key = "inCombat", label = "Vérifier en entrant en combat" },
        { type = "toggle", key = "outCombat", label = "Vérifier régulièrement hors combat" },
        { type = "toggle", key = "sound", label = "Jouer un son" },
        { type = "execute", label = "Vérifier maintenant", func = function()
            wipe(lastWarned)
            local missing = Missing(InCombatLockdown())
            if #missing == 0 then TW:Print("aucun buff manquant.") else Warn(InCombatLockdown()) end
        end },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    ticker = C_Timer.NewTicker(CHECK_EVERY, function()
        if db.outCombat and not InCombatLockdown() and not IsResting() then Warn(false) end
    end)
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    if ticker then ticker:Cancel(); ticker = nil end
end
