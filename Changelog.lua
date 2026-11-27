-- Changelog: what each version brings, newest first. WhatsNew.lua shows each character, once, what
-- came out since the version it last played with, all versions in between gathered.
--
-- For a release: add an entry on top with the version of the toc, and its lines in three lists:
--   new       what did not exist
--   improved  what works better
--   fixed     what was broken
-- Each line is one sentence, translated in Locales/frFR.lua.

local _, ns = ...
local L = ns.L

ns.Changelog = {
    {
        version = "2.0.0",
        new = {
            L["A new settings window: night or grimoire style, a welcome page of tiles, a dot to turn each tool on or off, switches and sliders in rows."],
            L["A setup in a few steps chooses the tools to turn on, for the account and for each new character. /tw setup opens it again."],
            L["Quick by default, the setup opens for every new character and only asks for its Edit Mode layout and action bars."],
            L["The news of each version show once, like these. /tw news shows them all."],
            L["Hunters: the aspects on the class bar, and a favorite aspect offered when none is worn."],
        },
        improved = {
            L["The tools are sorted into seven sections; error messages, reminders and Wowhead links get pages of their own."],
            L["Warlocks: no summon reminder while another demon is out."],
        },
    },
    {
        version = "1.17.1",
        improved = {
            L["The favorite demon and stone come first on the class bar."],
        },
    },
    {
        version = "1.17.0",
        new = {
            L["The travel journal becomes an open book whose pages turn."],
            L["Warlocks choose their favorite demon and stone in the reminders."],
        },
    },
    {
        version = "1.16.0",
        new = {
            L["Sleeping bag check and alerts, a threshold for elixirs, and the demons summoned from the class bar."],
        },
    },
}
