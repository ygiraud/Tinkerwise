-- AwayModes: one module for the scenes that play while the player isn't at the controls, each with
-- its own switch: AfkMode (away) and FlightMode (on a flight master trip).

local _, ns = ...
local L = ns.L
local TW = ns.TW

local function Apply(db)
    ns.AfkMode.Disable()
    ns.FlightMode.Disable()
    if db.afk then ns.AfkMode.Enable(db) end
    if db.flight then ns.FlightMode.Enable(db) end
end

local mod = TW:NewModule("AwayModes", {
    title = L["AFK and Flight Modes"],
    icon = "Interface\\Icons\\Spell_Nature_Sleep",
    section = "Immersion",
    desc = L["When you go AFK (/afk or after a while), the interface fades away and the camera turns slowly around your character. The screen shows the time away and the whispers received. Move or send a message to come back, or click the cross or press Escape to get the interface back while staying AFK. Out of combat only. The camera uses the game's view slot 5."]
        .. "\n\n" .. L["During a flight master trip, the interface fades away and the screen shows the destination, the zone below and the flight time. The time left appears once you have flown that route. The camera doesn't move. Click the cross or press Escape to get the interface back. Out of combat only."],
    defaults = { afk = true, flight = true, camera = true, routes = {} },
    replaces = { AfkMode = "afk", FlightMode = "flight" },
    options = {
        { type = "header", label = L["Away"] },
        { type = "toggle", key = "afk", label = L["When I am AFK"] },
        { type = "toggle", key = "camera", label = L["Camera movement"] },
        { type = "execute", label = L["Test (15 s)"], func = function(self) ns.AfkMode.Test(self.db) end },
        { type = "header", label = L["In flight"] },
        { type = "toggle", key = "flight", label = L["During a flight"] },
        { type = "execute", label = L["Test (15 s)"], func = function(self) ns.FlightMode.Test(self.db) end },
    },
})

function mod:OnEnable()
    Apply(self.db)
end

function mod:OnDisable()
    ns.AfkMode.Disable()
    ns.FlightMode.Disable()
end

function mod:OnOptionChanged(key)
    if key == "afk" or key == "flight" then
        Apply(self.db)
    elseif key == "camera" then
        ns.AfkMode.OnCameraChanged()
    end
end
