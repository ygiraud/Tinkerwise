-- Characters: level, rested XP and last login of every character of the account, shown in the
-- "Mes personnages" window (see Bags.lua), whose saved table it shares.
-- A character's data is saved while it is played; rested XP is then estimated from the elapsed time.

local _, ns = ...
local L = ns.L

local HOURS_PER_REST_STEP = 8
local REST_STEP = 0.05        -- 5 % of a level per 8 hours in an inn
local OUTSIDE_FACTOR = 0.25   -- rest is four times slower outside an inn
local REST_CAP = 1.5          -- 150 % of a level

local db

local function Save()
    if not db then return end
    local c = ns.CurrentCharacter()
    c.level = UnitLevel("player")
    c.rested = GetXPExhaustion() or 0
    c.xpMax = UnitXPMax("player")
    c.resting = IsResting()
    c.time = time()
end

-- "12 %", or "----" at the maximum level. Nil for a character not seen since this was recorded.
local function Rested(c)
    if not c.level or not c.xpMax then return nil end
    if c.level >= GetMaxPlayerLevel() then return "----" end
    if c.xpMax <= 0 then return "0 %" end
    local steps = (time() - c.time) / 3600 / HOURS_PER_REST_STEP
    local gain = steps * REST_STEP * c.xpMax * (c.resting and 1 or OUTSIDE_FACTOR)
    return format("%d %%", math.min(c.rested + gain, c.xpMax * REST_CAP) / c.xpMax * 100)
end

local function Ago(seconds)
    if seconds < 3600 then return L["just now"] end
    if seconds < 86400 then return format(L["%d h ago"], seconds / 3600) end
    return format(L["%d d ago"], seconds / 86400)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Save)

ns.CharacterList = { Save = Save, Rested = Rested, Ago = Ago }

function ns.CharacterList.Enable(moduleDB)
    db = moduleDB
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE",
                         "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "PLAYER_LOGOUT" }) do
        events:RegisterEvent(e)
    end
    if IsLoggedIn() then Save() end
end

function ns.CharacterList.Disable()
    events:UnregisterAllEvents()
end
