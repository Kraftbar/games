-- Auction chat/mail collection. Remove this file to keep a manual/read-only ledger.

local VA = VanillaAddon
local Ledger = VA.Ledger
local Mail = {}
VA.LedgerMail = Mail
VA:RegisterModule("ledger-mail", Mail)

local soldPattern, expiredPattern, wonPattern
local mailSoldPattern, mailExpiredPattern, mailWonPattern
local maxMailDays = 30

local function formatPattern(template, fallback)
    if not template then return fallback end
    return gsub(template, "%%s", "(.+)")
end

function Mail:InitializePatterns()
    soldPattern = formatPattern(ERR_AUCTION_SOLD_S, "^A buyer has been found for your auction of%s+(.+)%.$")
    expiredPattern = formatPattern(ERR_AUCTION_EXPIRED_S, "^Your auction of%s+(.+) has expired%.$")
    wonPattern = formatPattern(ERR_AUCTION_WON_S, "^You won an auction for%s+(.+)%.$")
    mailSoldPattern = formatPattern(AUCTION_SOLD_MAIL_SUBJECT, "^Auction successful:%s*(.+)$")
    mailExpiredPattern = formatPattern(AUCTION_EXPIRED_MAIL_SUBJECT, "^Auction expired:%s*(.+)$")
    mailWonPattern = formatPattern(AUCTION_WON_MAIL_SUBJECT, "^Auction won:%s*(.+)$")
end

local function deliveryTimestamp(daysLeft)
    local remaining = tonumber(daysLeft or maxMailDays) or maxMailDays
    local age = floor(((maxMailDays - remaining) * 24 * 60 * 60) + 0.5)
    age = max(0, min(maxMailDays * 24 * 60 * 60, age))
    return time() - age
end

local function signature(subject, money, sender, deliveredAt, cod, hasItem)
    local bucket = floor(((deliveredAt or 0) / 3600) + 0.5)
    return (subject or "") .. "|" .. tostring(tonumber(money or 0) or 0) .. "|" .. (sender or "") .. "|" .. tostring(bucket) .. "|" .. tostring(tonumber(cod or 0) or 0) .. "|" .. (hasItem and "1" or "0")
end

local function seenCount(sig)
    local value = Ledger.db.mailSeen[sig]
    if type(value) == "table" then return tonumber(value.n) or 0 end
    if value then return 1 end
    return 0
end

local function classify(subject)
    local _, _, item = strfind(subject or "", mailSoldPattern or "")
    if item then return "sold", item end
    _, _, item = strfind(subject or "", mailExpiredPattern or "")
    if item then return "expired", item end
    _, _, item = strfind(subject or "", mailWonPattern or "")
    if item then return "bought", item end
    return nil, nil
end

local function trustedSender(sender, stationery)
    local icon = strlower(stationery or "")
    if strfind(icon, "auction", 1, 1) then return true end
    local name = strlower(gsub(gsub(sender or "", "^%s+", ""), "%s+$", ""))
    if name == "" then return true end
    if strfind(name, "auction", 1, 1) or strfind(name, "auktions", 1, 1) or strfind(name, "subasta", 1, 1) then return true end
    if strfind(name, "%s") then return true end
    return false
end

local function inboxItem(index)
    if not GetInboxItem then return nil, 1 end
    local name, _, count = GetInboxItem(index)
    return name, max(1, tonumber(count or 1) or 1)
end

local function record(kind, item, qty, deliveredAt, money, reason)
    if kind == "sold" and (not money or money <= 0) then return nil end
    return Ledger:RecordMail(kind, item, qty, deliveredAt, money, reason)
end

function Mail:ScanInbox()
    Ledger:EnsureDB()
    local count = GetInboxNumItems() or 0
    local present = {}
    for index = 1, count do
        local _, stationery, sender, subject, money, cod, daysLeft, hasItem, wasRead = GetInboxHeaderInfo(index)
        local kind, subjectItem = classify(subject)
        if kind and trustedSender(sender, stationery) then
            local deliveredAt = deliveryTimestamp(daysLeft)
            local sig = signature(subject, money, sender, deliveredAt, cod, hasItem)
            local group = present[sig]
            if not group then
                group = { count = 0, unread = 0, kind = kind, item = subjectItem, money = money or 0, deliveredAt = deliveredAt, index = index, hasItem = hasItem }
                present[sig] = group
            end
            group.count = group.count + 1
            if not wasRead then group.unread = group.unread + 1; group.index = index end
        elseif kind then
            VA:Diag("mail-ignored", tostring(sender) .. " | " .. tostring(subject))
        elseif type(stationery) == "string" and strfind(strlower(stationery), "auction", 1, 1) then
            VA:Diag("mail-unparsed", tostring(sender) .. " | " .. tostring(subject))
        end
    end

    for sig, group in pairs(present) do
        local seen = min(seenCount(sig), group.count)
        local newCount = min(group.count - seen, group.unread)
        if newCount > 0 then
            local item, qty = group.item, 1
            if group.hasItem then item, qty = inboxItem(group.index); item = item or group.item end
            for _ = 1, newCount do record(group.kind, item, qty, group.deliveredAt, group.money, "scan") end
            seen = seen + newCount
        end
        Ledger.db.mailSeen[sig] = { n = seen, t = group.deliveredAt }
    end
    for sig in pairs(Ledger.db.mailSeen) do if not present[sig] then Ledger.db.mailSeen[sig] = nil end end
end

function Mail:RecordInteraction(index)
    Ledger:EnsureDB()
    local _, stationery, sender, subject, money, cod, daysLeft, hasItem = GetInboxHeaderInfo(index)
    local kind, subjectItem = classify(subject)
    if not kind or not trustedSender(sender, stationery) then return end
    local deliveredAt = deliveryTimestamp(daysLeft)
    local sig = signature(subject, money, sender, deliveredAt, cod, hasItem)
    if seenCount(sig) > 0 then return end
    local item, qty = subjectItem, 1
    if hasItem then item, qty = inboxItem(index); item = item or subjectItem end
    if record(kind, item, qty, deliveredAt, money or 0, "interaction") then
        Ledger.db.mailSeen[sig] = { n = 1, t = deliveredAt }
    end
end

function Mail:HandleSystem(message)
    if type(message) ~= "string" or not soldPattern then return end
    if strfind(strlower(message), "^::whc::") then return end
    local _, _, item = strfind(message, soldPattern)
    if item then Ledger:RecordChat("sold", item); return end
    _, _, item = strfind(message, expiredPattern)
    if item then Ledger:RecordChat("expired", item); return end
    _, _, item = strfind(message, wonPattern)
    if item then Ledger:RecordChat("bought", item); return end
    VA:Diag("system-unparsed", message)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then Mail:InitializePatterns()
    elseif event == "CHAT_MSG_SYSTEM" then Mail:HandleSystem(arg1)
    elseif event == "MAIL_SHOW" then CheckInbox()
    elseif event == "MAIL_INBOX_UPDATE" then Mail:ScanInbox() end
end)

Mail:InitializePatterns()

local originalTakeInboxMoney = TakeInboxMoney
if originalTakeInboxMoney then
    function TakeInboxMoney(index)
        Mail:RecordInteraction(index)
        return originalTakeInboxMoney(index)
    end
end

local originalAutoLootMailItem = AutoLootMailItem
if originalAutoLootMailItem then
    function AutoLootMailItem(index)
        Mail:RecordInteraction(index)
        return originalAutoLootMailItem(index)
    end
end

local originalTakeInboxItem = TakeInboxItem
if originalTakeInboxItem then
    function TakeInboxItem(index, attachment)
        Mail:RecordInteraction(index)
        return originalTakeInboxItem(index, attachment)
    end
end

local originalDeleteInboxItem = DeleteInboxItem
if originalDeleteInboxItem then
    function DeleteInboxItem(index)
        Mail:RecordInteraction(index)
        return originalDeleteInboxItem(index)
    end
end
