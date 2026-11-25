-- CharacterDetails: professions, recipes, recipe cooldowns and reputations of every character, for the
-- "Mes personnages" window (see Bags.lua), whose saved table it shares.
--
-- Recipes and cooldowns are only told by the game while the profession's window is open. A faction
-- under a folded header is not told either: what was known of it stays.

local _, ns = ...
local L = ns.L
local Spells = ns.Spells
local Plain = Spells.Plain

local db
local MAX_COOLDOWN = 30 * 86400 -- nothing lasts longer: a bad reading

local function SaveProfessions()
    if not db or not (GetProfessions and GetProfessionInfo) then return end
    local list, found = {}, false
    local lines = { GetProfessions() }
    for i = 1, select("#", GetProfessions()) do
        local index = lines[i]
        if index then
            local ok, name, icon, rank, max, _, _, line = pcall(GetProfessionInfo, index)
            if ok and Plain(name) and Plain(rank) then
                list[#list + 1] = { name = name, icon = Plain(icon), rank = rank, max = Plain(max), line = Plain(line) }
                found = true
            end
        end
    end
    if found then ns.CurrentCharacter().professions = list end
end

local function SaveReputations()
    local rep = C_Reputation
    if not db or not (rep and rep.GetNumFactions and rep.GetFactionDataByIndex) then return end
    local c = ns.CurrentCharacter()
    c.reputations = c.reputations or {}
    for i = 1, Plain(rep.GetNumFactions()) or 0 do
        local ok, f = pcall(rep.GetFactionDataByIndex, i)
        if ok and f and Plain(f.name) and (not f.isHeader or f.isHeaderWithRep) and Plain(f.reaction)
            and Plain(f.currentStanding) and (f.factionID or 0) > 0 then
            c.reputations[f.factionID] = { name = f.name, reaction = f.reaction,
                value = f.currentStanding - (f.currentReactionThreshold or 0),
                max = (f.nextReactionThreshold or 0) - (f.currentReactionThreshold or 0) }
        end
    end
end

-- The recipes of the open profession window, and their cooldowns.
local function SaveRecipes()
    local api = C_TradeSkillUI
    if not db or not (api and api.GetAllRecipeIDs and api.GetRecipeInfo and api.GetBaseProfessionInfo) then return end
    for _, method in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsDataSourceChanging" }) do
        if api[method] then
            local ok, yes = pcall(api[method])
            if not ok or yes then return end -- somebody else's
        end
    end
    local okInfo, profession = pcall(api.GetBaseProfessionInfo)
    local okIds, ids = pcall(api.GetAllRecipeIDs)
    local line = okInfo and profession and Plain(profession.professionID)
    if not line or line == 0 or not okIds or type(ids) ~= "table" or #ids == 0 then return end
    local c = ns.CurrentCharacter()
    c.cooldowns = c.cooldowns or {}
    local learned = {}
    for _, id in ipairs(ids) do
        local ok, info = pcall(api.GetRecipeInfo, id)
        if ok and info and Plain(info.learned) then
            learned[#learned + 1] = id
            if api.GetRecipeCooldown then
                local okCd, seconds = pcall(api.GetRecipeCooldown, id)
                seconds = okCd and Plain(seconds)
                if type(seconds) == "number" and seconds > 2 and seconds < MAX_COOLDOWN then
                    c.cooldowns[id] = time() + math.floor(seconds)
                end
            end
        end
    end
    if #learned > 0 then
        c.recipes = c.recipes or {}
        c.recipes[line] = learned
    end
end

local pending = {}
local function Later(fn, delay)
    if pending[fn] then return end
    pending[fn] = true
    C_Timer.After(delay, function()
        pending[fn] = nil
        fn()
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        Later(SaveRecipes, 1)
    elseif event == "UPDATE_FACTION" then
        Later(SaveReputations, 2)
    else
        Later(SaveProfessions, 2)
        if event == "PLAYER_ENTERING_WORLD" then Later(SaveReputations, 3) end
    end
end)

---------------------------------------------------------------------------
-- Rows for the window: { icon, name, text, spell }
---------------------------------------------------------------------------

local D = {}
ns.CharacterDetails = D

local function Left(ready)
    local seconds = ready - time()
    if seconds <= 0 then return "|cff40ff40" .. L["Ready"] .. "|r" end
    if seconds >= 86400 then return format(L["%d d %d h"], math.floor(seconds / 86400), math.floor(seconds / 3600) % 24) end
    if seconds >= 3600 then return format(L["%d h %d min"], math.floor(seconds / 3600), math.floor(seconds / 60) % 60) end
    return format(L["%d min"], math.ceil(seconds / 60))
end

local function Sorted(rows)
    table.sort(rows, function(a, b)
        if a.sort ~= b.sort then return a.sort < b.sort end
        if a.value ~= b.value then return a.value > b.value end
        return a.who < b.who
    end)
    return rows
end

local DOT = "  |cff808080\194\183|r  "

local BUILD = {}

function BUILD.professions(chars, rows)
    for _, c in ipairs(chars) do
        for _, p in ipairs(c.professions or {}) do
            rows[#rows + 1] = { icon = p.icon, name = p.name .. DOT .. ns.ClassColored(c), text = p.rank .. " / " .. (p.max or "?"),
                sort = p.name, value = p.rank, who = c.name }
        end
    end
end

-- One row per recipe, with everybody who knows it.
function BUILD.recipes(chars, rows)
    local by = {}
    for _, c in ipairs(chars) do
        for _, ids in pairs(c.recipes or {}) do
            for _, id in ipairs(ids) do
                by[id] = by[id] or {}
                table.insert(by[id], ns.ClassColored(c))
            end
        end
    end
    for id, who in pairs(by) do
        local name = Spells.Name(id)
        if name then
            rows[#rows + 1] = { icon = Spells.Icon(id), name = name, text = table.concat(who, ", "), spell = id,
                sort = name, value = 0, who = "" }
        end
    end
end

function BUILD.cooldowns(chars, rows)
    for _, c in ipairs(chars) do
        for id, ready in pairs(c.cooldowns or {}) do
            local name = Spells.Name(id)
            if name then
                rows[#rows + 1] = { icon = Spells.Icon(id), name = name .. DOT .. ns.ClassColored(c), text = Left(ready), spell = id,
                    sort = name, value = 0, who = c.name }
            end
        end
    end
end

function BUILD.reputations(chars, rows)
    for _, c in ipairs(chars) do
        for _, f in pairs(c.reputations or {}) do
            local label = _G["FACTION_STANDING_LABEL" .. f.reaction] or f.reaction
            local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[f.reaction]
            local text = color and format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, label) or label
            if f.max > 0 then text = text .. format("  %d / %d", f.value, f.max) end
            rows[#rows + 1] = { icon = "Interface\\Icons\\INV_Misc_Note_02", name = f.name .. DOT .. ns.ClassColored(c), text = text,
                sort = f.name, value = f.reaction * 1000000 + f.value, who = c.name }
        end
    end
end

D.VIEWS = {
    { "items", L["Items"] },
    { "professions", L["Professions"] },
    { "recipes", L["Recipes"] },
    { "cooldowns", L["Cooldowns"] },
    { "reputations", L["Reputations"] },
}
D.EMPTY = {
    professions = L["No profession seen yet: log in with each character."],
    recipes = L["Open each character's profession windows to record their recipes."],
    cooldowns = L["No cooldown seen yet: they are read when a profession window is open."],
    reputations = L["No reputation seen yet: log in with each character."],
}

-- The rows of a view for these characters, those whose name holds the query (in lower case).
function D.Rows(view, chars, query)
    local rows, kept = {}, {}
    BUILD[view](chars, rows)
    for _, r in ipairs(rows) do
        if query == "" or r.name:lower():find(query, 1, true) then kept[#kept + 1] = r end
    end
    return Sorted(kept)
end

function D.Enable(moduleDB)
    db = moduleDB
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
        pcall(events.RegisterEvent, events, e)
    end
end

function D.Disable()
    events:UnregisterAllEvents()
    db = nil
end
