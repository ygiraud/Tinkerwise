-- Mail: "take all" button on the inbox. Takes one attachment at a time, skipping
-- cash-on-delivery mail, and stops when the bags are full.

local _, ns = ...
local TW = ns.TW

local STEP = 0.4 -- seconds between two actions, leaving the server time to answer
local MAX_TRIES = 5 -- an attachment still there after this many tries cannot be taken (unique item...)

local ticker, button, bagsFull, skipped
local tries = {} -- "mail:slot:link" -> number of tries

local function Stop()
    if ticker then ticker:Cancel(); ticker = nil end
    if button then button:Enable() end
end

local function FreeSlots()
    return CalculateTotalNumberOfFreeBagSlots and CalculateTotalNumberOfFreeBagSlots() or 1
end

local function Step()
    local hasFree = FreeSlots() > 0
    for i = GetInboxNumItems(), 1, -1 do
        local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
        if (cod or 0) == 0 then
            if (money or 0) > 0 then return TakeInboxMoney(i) end
            if hasItem then
                if hasFree then
                    for slot = 1, ATTACHMENTS_MAX_RECEIVE or 12 do
                        if GetInboxItem(i, slot) then
                            local key = i .. ":" .. slot .. ":" .. (GetInboxItemLink(i, slot) or "")
                            local count = tries[key] or 0
                            if count < MAX_TRIES then
                                tries[key] = count + 1
                                return TakeInboxItem(i, slot)
                            end
                            skipped = true
                        end
                    end
                else
                    bagsFull = true
                end
            end
        end
    end
    TW:Print(bagsFull and "courrier : vos sacs sont pleins."
        or skipped and "courrier : certains objets n'ont pas pu être récupérés."
        or "courrier : tout est récupéré.")
    Stop()
end

local function Start()
    if ticker then return end
    bagsFull, skipped = false, false
    wipe(tries)
    button:Disable()
    ticker = C_Timer.NewTicker(STEP, Step)
end

local function BuildButton()
    button = CreateFrame("Button", "TinkerwiseMailButton", InboxFrame, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -10, 100)
    button:SetText("Tout récupérer")
    button:SetScript("OnClick", Start)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        -- Recent clients already have their own button.
        if not button and not _G.OpenAllMail then BuildButton() end
    else
        Stop()
    end
end)

local mod = TW:NewModule("Mail", {
    title = "Courrier",
    icon = "Interface\\Icons\\INV_Letter_15",
    section = "Objets",
    desc = "Ajoute un bouton « Tout récupérer » à la boîte aux lettres : or et objets, sauf les envois contre remboursement. S'arrête quand les sacs sont pleins.",
})

function mod:OnEnable()
    events:RegisterEvent("MAIL_SHOW")
    events:RegisterEvent("MAIL_CLOSED")
    if button then button:Show() end
end

function mod:OnDisable()
    events:UnregisterAllEvents()
    Stop()
    if button then button:Hide() end
end
