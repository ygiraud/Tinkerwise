-- GroupComfort: accepts group invitations from friends and guildmates, resurrections and summons.

local _, ns = ...
local TW = ns.TW

local db

local function SameName(a, b)
    return a and b and Ambiguate(a, "short") == Ambiguate(b, "short")
end

local function IsFriend(name)
    if not C_FriendList then return false end
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and SameName(info.name, name) then return true end
    end
    return false
end

local function IsGuildmate(name)
    if not IsInGuild() then return false end
    for i = 1, GetNumGuildMembers() do
        if SameName((GetGuildRosterInfo(i)), name) then return true end
    end
    return false
end

local function HidePopups(...)
    for i = 1, select("#", ...) do StaticPopup_Hide((select(i, ...))) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PARTY_INVITE_REQUEST" then
        if db.invites and (IsFriend(name) or IsGuildmate(name)) then
            AcceptGroup()
            HidePopups("PARTY_INVITE")
            TW:Print(format("invitation de %s acceptée.", name))
        end
    elseif event == "RESURRECT_REQUEST" then
        if db.resurrect and not (db.resurrectSafe and UnitAffectingCombat(name)) then
            AcceptResurrect()
            HidePopups("RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER")
            TW:Print(format("résurrection de %s acceptée.", name))
        end
    elseif event == "CONFIRM_SUMMON" then
        if db.summon then
            if C_SummonInfo and C_SummonInfo.ConfirmSummon then
                C_SummonInfo.ConfirmSummon()
            else
                ConfirmSummon()
            end
            HidePopups("CONFIRM_SUMMON")
            TW:Print("invocation acceptée.")
        end
    end
end)

local mod = TW:NewModule("GroupComfort", {
    title = "Confort de groupe",
    icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
    section = "Groupe",
    desc = "Accepte automatiquement les invitations de groupe de vos amis et de votre guilde, les résurrections et, si vous le souhaitez, les invocations.",
    defaults = {
        invites = true,
        resurrect = true,
        resurrectSafe = true, -- not while the resurrecter is still in combat
        summon = false,
    },
    options = {
        { type = "toggle", key = "invites", label = "Invitations des amis et de la guilde" },
        { type = "toggle", key = "resurrect", label = "Résurrections" },
        { type = "toggle", key = "resurrectSafe", label = "Pas si celui qui vous relève est en combat" },
        { type = "toggle", key = "summon", label = "Invocations" },
    },
})

function mod:OnEnable()
    db = self.db
    events:RegisterEvent("PARTY_INVITE_REQUEST")
    events:RegisterEvent("RESURRECT_REQUEST")
    events:RegisterEvent("CONFIRM_SUMMON")
end

function mod:OnDisable()
    events:UnregisterAllEvents()
end
