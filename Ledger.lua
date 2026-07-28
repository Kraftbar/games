-- Vanilla 1.12 sales ledger for auctions (no dependency on Aux)

local function ensure_db()
    if not VanillaLedgerDB then
        VanillaLedgerDB = {}
    end
    VanillaLedgerDB.sold = VanillaLedgerDB.sold or {}
    VanillaLedgerDB.expired = VanillaLedgerDB.expired or {}
    VanillaLedgerDB.bought = VanillaLedgerDB.bought or {}
    VanillaLedgerDB.version = VanillaLedgerDB.version or 1
    if VanillaLedgerDB.debug == nil then
        VanillaLedgerDB.debug = false
    end
    VanillaLedgerDB.mailSeen = VanillaLedgerDB.mailSeen or {}
    -- Signature format changed (v2: stable delivery-time buckets); old entries can never match.
    if VanillaLedgerDB.mailSeenV ~= 2 then
        VanillaLedgerDB.mailSeen = {}
        VanillaLedgerDB.mailSeenV = 2
    end
    -- UI preferences (view: all|sold|expired|bought)
    VanillaLedgerDB.view = VanillaLedgerDB.view or "all"
    if VanillaLedgerDB.view ~= "all" and VanillaLedgerDB.view ~= "sold" and VanillaLedgerDB.view ~= "expired" and VanillaLedgerDB.view ~= "bought" then
        VanillaLedgerDB.view = "all"
    end
    VanillaLedgerErrors = VanillaLedgerErrors or {}
end

local LEDGER_MAX_BUCKET_ROWS = 50000
local LEDGER_MAX_MAILSEEN = 120000
local MAILSEEN_TTL_SECONDS = 45 * 24 * 60 * 60

local function trimArrayHead(t, maxRows)
    local n = getn(t)
    local trimBatch = 200
    if n <= (maxRows + trimBatch) then return end
    local cut = n - maxRows
    local write = 1
    for read = cut + 1, n do
        t[write] = t[read]
        write = write + 1
    end
    for i = write, n do
        t[i] = nil
    end
end

local function addLedgerRow(bucket, row)
    ensure_db()
    tinsert(VanillaLedgerDB[bucket], row)
    trimArrayHead(VanillaLedgerDB[bucket], LEDGER_MAX_BUCKET_ROWS)
end

local function pruneMailSeen(nowTs)
    ensure_db()
    local seen = VanillaLedgerDB.mailSeen or {}
    local ttlCut = (nowTs or time()) - MAILSEEN_TTL_SECONDS
    local kept = 0
    for k, v in pairs(seen) do
        local keep = false
        if type(v) == "table" then
            keep = ((tonumber(v.t) or 0) >= ttlCut)
        elseif type(v) == "number" then
            keep = (v >= ttlCut)
        end
        if keep then
            kept = kept + 1
        else
            seen[k] = nil
        end
    end
    if kept > LEDGER_MAX_MAILSEEN then
        VanillaLedgerDB.mailSeen = {}
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")

local soldPattern
local expiredPattern
local wonPattern
local mailSoldPattern
local mailExpiredPattern
local mailWonPattern

local function add_entry(bucket, item)
    addLedgerRow(bucket, {
        item = item,
        t = time(),
        source = "chat",
    })
end

local function ledgerPrint(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Ledger]|r " .. msg)
end

local function debugPrint(msg)
    if VanillaLedgerDB and VanillaLedgerDB.debug then
        ledgerPrint(msg)
    end
end

local function openAuxSearch()
    if AuxFind_Open then
        AuxFind_Open()
    elseif SlashCmdList and SlashCmdList["AUXFIND"] then
        SlashCmdList["AUXFIND"]("")
    elseif AuxFind_Run then
        AuxFind_Run("")
    else
        ledgerPrint("Aux search is not loaded.")
    end
end

local auxMinimapPositions = {
    { point = "TOPRIGHT", dx = -8, dy = -8 },
    { point = "TOPLEFT",  dx =  8, dy = -8 },
    { point = "BOTTOMLEFT", dx =  8, dy =  8 },
    { point = "BOTTOMRIGHT", dx = -8, dy =  8 },
}
local ledgerAuxPosIndex = 1
local function positionLedgerAuxButton(btn)
    local p = auxMinimapPositions[ledgerAuxPosIndex]
    btn:ClearAllPoints()
    local anchor = Minimap or UIParent
    btn:SetPoint(p.point, anchor, p.point, p.dx, p.dy)
end

local function formatCoins(copper)
    copper = tonumber(copper or 0) or 0
    local g = floor(copper / 10000)
    local s = floor(mod(copper, 10000) / 100)
    local c = floor(mod(copper, 100))
    return format("%dg %ds %dc", g, s, c)
end

-- Stable across sessions: keyed on estimated delivery time (1h bucket), not the
-- ever-decreasing daysLeft. Identical mails in the same bucket share a signature;
-- the scan counts them instead of dropping duplicates.
local function stableMailSig(subject, money, sender, deliveredAt, CODAmount, hasItem)
    subject = subject or ""
    sender = sender or ""
    money = tonumber(money or 0) or 0
    local bucket = floor(((deliveredAt or 0) / 3600) + 0.5)
    local cod = tonumber(CODAmount or 0) or 0
    local hi = hasItem and 1 or 0
    return subject .. "|" .. tostring(money) .. "|" .. sender .. "|" .. tostring(bucket) .. "|" .. tostring(cod) .. "|" .. tostring(hi)
end

local function seenMailCount(sig)
    local v = VanillaLedgerDB.mailSeen[sig]
    if type(v) == "table" then return tonumber(v.n) or 1 end
    if v then return 1 end
    return 0
end

local MAIL_MAX_DAYS = 30
local function inboxDeliveryTimestamp(daysLeft)
    local nowTs = time()
    local dl = tonumber(daysLeft or MAIL_MAX_DAYS) or MAIL_MAX_DAYS
    local age = floor(((MAIL_MAX_DAYS - dl) * 24 * 60 * 60) + 0.5)
    if age < 0 then age = 0 end
    if age > (MAIL_MAX_DAYS * 24 * 60 * 60) then
        age = MAIL_MAX_DAYS * 24 * 60 * 60
    end
    return nowTs - age
end

local function safeInboxItem(index)
    if not GetInboxItem then return nil, 1 end
    local itemName, _, itemCount = GetInboxItem(index)
    if not itemName or itemName == "" then return nil, 1 end
    itemCount = tonumber(itemCount or 1) or 1
    if itemCount < 1 then itemCount = 1 end
    return itemName, itemCount
end

local function classifyAuctionSubject(subject)
    local _, _, soldItem = string.find(subject or "", mailSoldPattern or "")
    if soldItem then return "sold", soldItem end
    local _, _, expItem = string.find(subject or "", mailExpiredPattern or "")
    if expItem then return "expired", expItem end
    local _, _, wonItem = string.find(subject or "", mailWonPattern or "")
    if wonItem then return "bought", wonItem end
    return nil, nil
end

local function isAuctionStationery(stationeryIcon)
    if type(stationeryIcon) ~= "string" then return false end
    local icon = strlower(stationeryIcon)
    if string.find(icon, "auctionstationery", 1, 1) then return true end
    if string.find(icon, "auction", 1, 1) then return true end
    return false
end

local function normalizeSender(sender)
    sender = sender or ""
    sender = gsub(sender, "^%s+", "")
    sender = gsub(sender, "%s+$", "")
    return sender
end

local function isKnownAuctionSender(sender)
    sender = strlower(normalizeSender(sender))
    if sender == "" then return false end
    if sender == "alliance auction house" or sender == "horde auction house" then return true end
    if string.find(sender, "auction", 1, 1) then return true end
    if string.find(sender, "auktions", 1, 1) then return true end
    if string.find(sender, "subasta", 1, 1) then return true end
    if string.find(sender, "ench", 1, 1) then return true end
    if string.find(sender, "aste", 1, 1) then return true end
    if string.find(sender, "leil", 1, 1) then return true end
    return false
end

local function looksLikePlayerSender(sender)
    sender = normalizeSender(sender)
    if sender == "" then return false end
    if string.find(sender, "%s") then return false end
    if string.find(sender, "^[A-Za-z][A-Za-z%-']+$") then return true end
    return false
end

local function shouldTrustAuctionMailSender(sender, stationeryIcon)
    if isAuctionStationery(stationeryIcon) then
        return true, "stationery"
    end
    if isKnownAuctionSender(sender) then
        return true, "sender"
    end
    sender = normalizeSender(sender)
    if sender == "" then
        return true, "no-sender-fallback"
    end
    if looksLikePlayerSender(sender) then
        return false, "player-like-sender"
    end
    return true, "unknown-sender-fallback"
end

-- A live CHAT_MSG_SYSTEM record and the later AH mail describe the same event.
-- Upgrade the chat entry in place instead of adding a duplicate row.
local LEDGER_CHAT_MERGE_WINDOW = 36 * 60 * 60
local function upgradeChatEntry(bucket, item, deliveredAt, money, qty)
    local rows = VanillaLedgerDB[bucket]
    local n = getn(rows)
    for i = n, max(1, n - 400), -1 do
        local e = rows[i]
        if e and e.item == item and (e.source == "chat" or (e.source == nil and not e.money)) then
            local dt = (deliveredAt or 0) - (e.t or 0)
            if dt > -600 and dt < LEDGER_CHAT_MERGE_WINDOW then
                if money and money > 0 then e.money = money end
                local q = tonumber(qty or 1) or 1
                if q > 1 then e.qty = q end
                e.source = "chat+mail"
                return true
            end
        end
    end
    return false
end

local function recordMailEntry(entryType, item, qty, deliveredAt, money, senderReason)
    if entryType == "sold" then
        if not (money and money > 0) then return end
        if upgradeChatEntry("sold", item, deliveredAt, money, 1) then
            debugPrint("Mail sold merged into chat entry: " .. item .. " for " .. tostring(money) .. "c")
            return
        end
        addLedgerRow("sold", { item = item, qty = 1, t = deliveredAt, money = money, source = "mail" })
        debugPrint("Mail sold recorded: " .. item .. " for " .. tostring(money) .. "c (" .. senderReason .. ", at " .. date("%Y-%m-%d %H:%M", deliveredAt) .. ")")
    else
        if upgradeChatEntry(entryType, item, deliveredAt, nil, qty) then
            debugPrint("Mail " .. entryType .. " merged into chat entry: " .. item .. " x" .. tostring(qty or 1))
            return
        end
        addLedgerRow(entryType, { item = item, qty = qty or 1, t = deliveredAt, source = "mail" })
        debugPrint("Mail " .. entryType .. " recorded: " .. item .. " x" .. tostring(qty or 1) .. " (" .. senderReason .. ", at " .. date("%Y-%m-%d %H:%M", deliveredAt) .. ")")
    end
end

local function scanInbox()
    ensure_db()
    local num = GetInboxNumItems() or 0
    debugPrint("Inbox scan: items=" .. tostring(num))
    local present = {}
    for i = 1, num do
        local _, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead = GetInboxHeaderInfo(i)
        subject = subject or ""
        sender = sender or ""
        money = money or 0
        -- BeanCounter-style guard: process unread mail only.
        if not wasRead then
            local entryType, subjectItem = classifyAuctionSubject(subject)
            if entryType then
                local trustSender, senderReason = shouldTrustAuctionMailSender(sender, stationeryIcon)
                if trustSender then
                    local deliveredAt = inboxDeliveryTimestamp(daysLeft)
                    local sig = stableMailSig(subject, money, sender, deliveredAt, CODAmount, hasItem)
                    local p = present[sig]
                    if not p then
                        p = { count = 0, entryType = entryType, item = subjectItem, money = money,
                              deliveredAt = deliveredAt, index = i, hasItem = hasItem, reason = senderReason }
                        present[sig] = p
                    end
                    p.count = p.count + 1
                else
                    debugPrint("Inbox(" .. tostring(i) .. ") ignored non-AH sender '" .. tostring(sender) .. "' for auction-like subject.")
                end
            end
        end
    end
    for sig, p in pairs(present) do
        local seen = seenMailCount(sig)
        if p.count > seen then
            local itemName, itemCount = nil, 1
            if p.hasItem then
                itemName, itemCount = safeInboxItem(p.index)
            end
            for r = 1, p.count - seen do
                recordMailEntry(p.entryType, itemName or p.item, itemCount or 1, p.deliveredAt, p.money, p.reason)
            end
            seen = p.count
        end
        VanillaLedgerDB.mailSeen[sig] = { n = seen, t = p.deliveredAt }
    end
end

-- Looting/deleting destroys the mail, so record it now even if it was read
-- (read mail is skipped by the background scan).
local function recordInboxInteract(index)
    ensure_db()
    local _, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem = GetInboxHeaderInfo(index)
    subject = subject or ""
    sender = sender or ""
    money = money or 0
    local entryType, subjectItem = classifyAuctionSubject(subject)
    if not entryType then return end
    local trustSender = shouldTrustAuctionMailSender(sender, stationeryIcon)
    if not trustSender then return end
    local deliveredAt = inboxDeliveryTimestamp(daysLeft)
    local sig = stableMailSig(subject, money, sender, deliveredAt, CODAmount, hasItem)
    if seenMailCount(sig) > 0 then return end
    local itemName, itemCount = nil, 1
    if hasItem then
        itemName, itemCount = safeInboxItem(index)
    end
    recordMailEntry(entryType, itemName or subjectItem, itemCount or 1, deliveredAt, money, "interact")
    VanillaLedgerDB.mailSeen[sig] = { n = 1, t = deliveredAt }
end

local function dateKey(ts)
    return date("%Y-%m-%d", ts)
end

local function buildSoldGroups(filterDayKey)
    ensure_db()
    local groups = {}
    for i = 1, getn(VanillaLedgerDB.sold) do
        local e = VanillaLedgerDB.sold[i]
        local dkey = dateKey(e.t or time())
        if not filterDayKey or dkey == filterDayKey then
            local price = e.money or -1
            local key = dkey .. "\031" .. (e.item or "?") .. "\031" .. tostring(price)
            if not groups[key] then
                groups[key] = { day = dkey, item = e.item or "?", price = price, count = 0, total = 0 }
            end
            groups[key].count = groups[key].count + 1
            if e.money and e.money > 0 then
                groups[key].total = groups[key].total + e.money
            end
        end
    end
    -- flatten to array
    local arr, n = {}, 0
    for _, g in pairs(groups) do
        n = n + 1
        arr[n] = g
    end
    -- sort: by day desc, then by count desc
    table.sort(arr, function(a, b)
        if a.day ~= b.day then return a.day > b.day end
        if a.count ~= b.count then return a.count > b.count end
        return (a.item or "") < (b.item or "")
    end)
    return arr
end

local function buildDaySummaries()
    ensure_db()
    local dayMap = {}
    for i = 1, getn(VanillaLedgerDB.sold) do
        local e = VanillaLedgerDB.sold[i]
        local dkey = dateKey(e.t or time())
        local price = e.money or -1
        dayMap[dkey] = dayMap[dkey] or { day = dkey, totalCount = 0, totalMoney = 0, groups = {} }
        local day = dayMap[dkey]
        day.totalCount = day.totalCount + 1
        if e.money and e.money > 0 then day.totalMoney = day.totalMoney + e.money end
        local gkey = (e.item or "?") .. "\031" .. tostring(price)
        local g = day.groups[gkey]
        if not g then
            g = { item = e.item or "?", price = price, count = 0, total = 0, pricedCount = 0 }
            day.groups[gkey] = g
        end
        g.count = g.count + 1
        if e.money and e.money > 0 then
            g.total = g.total + e.money
            g.pricedCount = g.pricedCount + 1
        end
    end
    -- flatten and sort per-day groups and days
    local days, n = {}, 0
    for _, d in pairs(dayMap) do
        -- flatten groups
        local arr, m = {}, 0
        for _, g in pairs(d.groups) do m = m + 1; arr[m] = g end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.item or "") < (b.item or "")
        end)
        d.groups = arr
        n = n + 1; days[n] = d
    end
    table.sort(days, function(a, b) return a.day > b.day end)
    return days
end

-- Build grouped counts for expired (unsold) items
local function buildExpiredGroups(filterDayKey)
    ensure_db()
    local groups = {}
    for i = 1, getn(VanillaLedgerDB.expired) do
        local e = VanillaLedgerDB.expired[i]
        local qty = tonumber(e.qty or 1) or 1
        if qty < 1 then qty = 1 end
        local dkey = dateKey(e.t or time())
        if not filterDayKey or dkey == filterDayKey then
            local key = dkey .. "\031" .. (e.item or "?")
            if not groups[key] then
                groups[key] = { day = dkey, item = e.item or "?", count = 0 }
            end
            groups[key].count = groups[key].count + qty
        end
    end
    local arr, n = {}, 0
    for _, g in pairs(groups) do
        n = n + 1
        arr[n] = g
    end
    table.sort(arr, function(a, b)
        if a.day ~= b.day then return a.day > b.day end
        if a.count ~= b.count then return a.count > b.count end
        return (a.item or "") < (b.item or "")
    end)
    return arr
end

-- Build per-day summaries for expired items
local function buildExpiredDaySummaries()
    ensure_db()
    local dayMap = {}
    for i = 1, getn(VanillaLedgerDB.expired) do
        local e = VanillaLedgerDB.expired[i]
        local qty = tonumber(e.qty or 1) or 1
        if qty < 1 then qty = 1 end
        local dkey = dateKey(e.t or time())
        dayMap[dkey] = dayMap[dkey] or { day = dkey, totalCount = 0, groups = {} }
        local day = dayMap[dkey]
        day.totalCount = day.totalCount + qty
        local gkey = (e.item or "?")
        local g = day.groups[gkey]
        if not g then
            g = { item = e.item or "?", count = 0 }
            day.groups[gkey] = g
        end
        g.count = g.count + qty
    end
    local days, n = {}, 0
    for _, d in pairs(dayMap) do
        local arr, m = {}, 0
        for _, g in pairs(d.groups) do m = m + 1; arr[m] = g end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.item or "") < (b.item or "")
        end)
        d.groups = arr
        n = n + 1; days[n] = d
    end
    table.sort(days, function(a, b) return a.day > b.day end)
    return days
end

-- Build grouped counts for bought items
local function buildBoughtGroups(filterDayKey)
    ensure_db()
    local groups = {}
    for i = 1, getn(VanillaLedgerDB.bought) do
        local e = VanillaLedgerDB.bought[i]
        local qty = tonumber(e.qty or 1) or 1
        if qty < 1 then qty = 1 end
        local dkey = dateKey(e.t or time())
        if not filterDayKey or dkey == filterDayKey then
            local key = dkey .. "\031" .. (e.item or "?")
            if not groups[key] then
                groups[key] = { day = dkey, item = e.item or "?", count = 0 }
            end
            groups[key].count = groups[key].count + qty
        end
    end
    local arr, n = {}, 0
    for _, g in pairs(groups) do
        n = n + 1
        arr[n] = g
    end
    table.sort(arr, function(a, b)
        if a.day ~= b.day then return a.day > b.day end
        if a.count ~= b.count then return a.count > b.count end
        return (a.item or "") < (b.item or "")
    end)
    return arr
end

-- Build per-day summaries for bought items
local function buildBoughtDaySummaries()
    ensure_db()
    local dayMap = {}
    for i = 1, getn(VanillaLedgerDB.bought) do
        local e = VanillaLedgerDB.bought[i]
        local qty = tonumber(e.qty or 1) or 1
        if qty < 1 then qty = 1 end
        local dkey = dateKey(e.t or time())
        dayMap[dkey] = dayMap[dkey] or { day = dkey, totalCount = 0, groups = {} }
        local day = dayMap[dkey]
        day.totalCount = day.totalCount + qty
        local gkey = (e.item or "?")
        local g = day.groups[gkey]
        if not g then
            g = { item = e.item or "?", count = 0 }
            day.groups[gkey] = g
        end
        g.count = g.count + qty
    end
    local days, n = {}, 0
    for _, d in pairs(dayMap) do
        local arr, m = {}, 0
        for _, g in pairs(d.groups) do m = m + 1; arr[m] = g end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.item or "") < (b.item or "")
        end)
        d.groups = arr
        n = n + 1; days[n] = d
    end
    table.sort(days, function(a, b) return a.day > b.day end)
    return days
end

local function printSummary(filter)
    local dk
    if filter == "today" then dk = dateKey(time()) end
    if dk then
        local groups = buildSoldGroups(dk)
        if getn(groups) == 0 then ledgerPrint("No sales recorded for " .. dk) return end
        local total = 0; for i = 1, getn(groups) do total = total + (groups[i].total or 0) end
        ledgerPrint("Summary for " .. dk .. " — total " .. formatCoins(total))
        for i = 1, getn(groups) do
            local g = groups[i]
            local priceText = (g.price and g.price > 0) and (" - total " .. formatCoins(g.total)) or ""
            DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s%s", g.count, g.item, priceText))
        end
        return
    end
    -- all days
    local days = buildDaySummaries()
    if getn(days) == 0 then ledgerPrint("No sales recorded") return end
    ledgerPrint("Daily totals:")
    for i = 1, getn(days) do
        local d = days[i]
        DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items — %s", d.day, d.totalCount, formatCoins(d.totalMoney)))
    end
end

-- UI view helpers
local function LedgerSetView(view)
    ensure_db()
    view = strlower(view or "")
    if view ~= "all" and view ~= "sold" and view ~= "expired" and view ~= "bought" then
        ledgerPrint("Unknown view. Use: all, sold, expired, bought")
        return
    end
    VanillaLedgerDB.view = view
    ledgerPrint("View set to: " .. view)
    if LedgerFrame and LedgerFrame:IsShown() then ShowLedgerUI() end
end

local function LedgerToggleView()
    ensure_db()
    local v = VanillaLedgerDB.view or "all"
    if v == "all" then
        v = "sold"
    elseif v == "sold" then
        v = "expired"
    elseif v == "expired" then
        v = "bought"
    else
        v = "all"
    end
    LedgerSetView(v)
end

eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        ensure_db()
        pruneMailSeen(time())
        soldPattern = gsub(ERR_AUCTION_SOLD_S, "%%s", "(.+)")
        expiredPattern = gsub(ERR_AUCTION_EXPIRED_S, "%%s", "(.+)")
        if ERR_AUCTION_WON_S then
            wonPattern = gsub(ERR_AUCTION_WON_S, "%%s", "(.+)")
        else
            wonPattern = "^You won an auction for%s+(.+)%.$"
        end
        if AUCTION_SOLD_MAIL_SUBJECT then
            mailSoldPattern = gsub(AUCTION_SOLD_MAIL_SUBJECT, "%%s", "(.+)")
        else
            mailSoldPattern = "^Auction successful:%s*(.+)$"
        end
        if AUCTION_EXPIRED_MAIL_SUBJECT then
            mailExpiredPattern = gsub(AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "(.+)")
        else
            mailExpiredPattern = "^Auction expired:%s*(.+)$"
        end
        if AUCTION_WON_MAIL_SUBJECT then
            mailWonPattern = gsub(AUCTION_WON_MAIL_SUBJECT, "%%s", "(.+)")
        else
            mailWonPattern = "^Auction won:%s*(.+)$"
        end
        debugPrint("VARIABLES_LOADED: patterns initialized")
    elseif event == "ADDON_LOADED" then
        if arg1 == "vanilla-addon" then
            debugPrint("ADDON_LOADED: vanilla-addon")
        end
    elseif event == "PLAYER_LOGIN" then
        ensure_db()
        pruneMailSeen(time())
        ledgerPrint("Hello from Ledger!")
        ledgerPrint(string.format("loaded. Sold: %d, Expired: %d, Bought: %d. Debug: %s", getn(VanillaLedgerDB.sold), getn(VanillaLedgerDB.expired), getn(VanillaLedgerDB.bought), VanillaLedgerDB.debug and "on" or "off"))
        -- Create minimap button and UI
        if not LedgerMinimapButton then
            local btn = CreateFrame("Button", "LedgerMinimapButton", Minimap)
            btn:SetWidth(31); btn:SetHeight(31)
            btn:SetFrameStrata("LOW"); btn:SetFrameLevel(8)
            btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 8, -8)
            local overlay = btn:CreateTexture(nil, "OVERLAY")
            overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            overlay:SetWidth(52); overlay:SetHeight(52)
            overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
            icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
            icon:SetWidth(20); icon:SetHeight(20)
            icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.icon = icon
            btn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                GameTooltip:SetText("Ledger", 1, 1, 1)
                GameTooltip:AddLine("Left-click: Toggle Ledger UI", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Right-click: Print today's summary", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Shift-click: Toggle view (All/Sold/Expired/Bought)", 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function()
                if arg1 == "RightButton" then
                    printSummary("today")
                else
                    if IsShiftKeyDown() then
                        LedgerToggleView()
                    else
                        if LedgerFrame and LedgerFrame:IsShown() then LedgerFrame:Hide() else ShowLedgerUI() end
                    end
                end
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        if not LedgerAuxMinimapButton and not AuxSearchMinimapButton then
            local parent = Minimap or UIParent
            local auxBtn = CreateFrame("Button", "LedgerAuxMinimapButton", parent)
            auxBtn:SetWidth(31); auxBtn:SetHeight(31)
            auxBtn:SetFrameStrata("HIGH"); auxBtn:SetFrameLevel(10)
            auxBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            positionLedgerAuxButton(auxBtn)
            auxBtn:SetMovable(true)
            auxBtn:EnableMouse(true)
            auxBtn:RegisterForDrag("LeftButton")
            auxBtn:SetScript("OnDragStart", function() auxBtn:StartMoving() end)
            auxBtn:SetScript("OnDragStop", function() auxBtn:StopMovingOrSizing() end)
            local overlay2 = auxBtn:CreateTexture(nil, "OVERLAY")
            overlay2:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            overlay2:SetWidth(52); overlay2:SetHeight(52)
            overlay2:SetPoint("TOPLEFT", auxBtn, "TOPLEFT", 0, 0)
            local icon2 = auxBtn:CreateTexture(nil, "ARTWORK")
            icon2:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
            icon2:SetTexCoord(0.05, 0.95, 0.05, 0.95)
            icon2:SetWidth(20); icon2:SetHeight(20)
            icon2:SetPoint("CENTER", auxBtn, "CENTER", 0, 0)
            auxBtn.icon = icon2
            auxBtn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(auxBtn, "ANCHOR_LEFT")
                GameTooltip:SetText("Aux Search", 1, 1, 1)
                GameTooltip:AddLine("Left-click: Open Aux DB search", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Drag: Free move", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Right-click: Snap to corner", 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end)
            auxBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            auxBtn:SetScript("OnClick", function()
                if arg1 == "RightButton" then
                    ledgerAuxPosIndex = ledgerAuxPosIndex + 1
                    if ledgerAuxPosIndex > 4 then ledgerAuxPosIndex = 1 end
                    positionLedgerAuxButton(auxBtn)
                else
                    openAuxSearch()
                end
            end)
            auxBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            -- If Aux creates its own minimap button after us, hide this fallback.
            auxBtn._dedupeUntil = (GetTime() or 0) + 5
            auxBtn:SetScript("OnUpdate", function()
                if AuxSearchMinimapButton and AuxSearchMinimapButton ~= this then
                    this:Hide()
                    this:SetScript("OnUpdate", nil)
                    return
                end
                if (GetTime() or 0) > (this._dedupeUntil or 0) then
                    this:SetScript("OnUpdate", nil)
                end
            end)
        end
    elseif event == "MAIL_SHOW" then
        -- Trigger an inbox refresh when mailbox opens
        pruneMailSeen(time())
        debugPrint("MAIL_SHOW: checking inbox")
        CheckInbox()
    elseif event == "MAIL_INBOX_UPDATE" then
        -- Process inbox to capture offline sold/expired/bought entries
        scanInbox()
    elseif event == "CHAT_MSG_SYSTEM" then
        if not soldPattern then return end
        local msg = arg1
        -- WHC server protocol lines are not auction results; skip them silently.
        if type(msg) == "string" and string.find(string.lower(msg), "^::whc::") then return end
        debugPrint("CHAT_MSG_SYSTEM: " .. tostring(msg))
        if type(msg) == "string" then
            local _, _, item = string.find(msg, soldPattern)
            if item then
                ensure_db()
                add_entry("sold", item)
                debugPrint("Recorded sold: " .. item .. string.format(" (total %d)", getn(VanillaLedgerDB.sold)))
                return
            end
            _, _, item = string.find(msg, expiredPattern)
            if item then
                ensure_db()
                add_entry("expired", item)
                debugPrint("Recorded expired: " .. item .. string.format(" (total %d)", getn(VanillaLedgerDB.expired)))
                return
            end
            _, _, item = string.find(msg, wonPattern or "")
            if item then
                ensure_db()
                add_entry("bought", item)
                debugPrint("Recorded bought: " .. item .. string.format(" (total %d)", getn(VanillaLedgerDB.bought)))
                return
            end
        end
    end
end)

SLASH_LEDGER1 = "/ledger"
SlashCmdList["LEDGER"] = function(msg)
    ensure_db()
    msg = msg or ""
    msg = gsub(msg, "^%s+", "")
    msg = gsub(msg, "%s+$", "")
    local cmd, argText = "", ""
    local s, e = string.find(msg, "%s+")
    if s then
        cmd = strlower(string.sub(msg, 1, s - 1))
        argText = strlower(string.sub(msg, e + 1))
    else
        cmd = strlower(msg)
    end

    if cmd == "debug" then
        if argText == "on" then
            VanillaLedgerDB.debug = true
            ledgerPrint("Debug enabled")
        elseif argText == "off" then
            VanillaLedgerDB.debug = false
            ledgerPrint("Debug disabled")
        else
            VanillaLedgerDB.debug = not VanillaLedgerDB.debug
            ledgerPrint("Debug " .. (VanillaLedgerDB.debug and "enabled" or "disabled"))
        end
    elseif cmd == "stats" or cmd == "" then
        ledgerPrint(string.format("Sold: %d, Expired: %d, Bought: %d", getn(VanillaLedgerDB.sold), getn(VanillaLedgerDB.expired), getn(VanillaLedgerDB.bought)))
    elseif cmd == "status" then
        ledgerPrint(string.format("Status — Sold: %d, Expired: %d, Bought: %d, Debug: %s", getn(VanillaLedgerDB.sold), getn(VanillaLedgerDB.expired), getn(VanillaLedgerDB.bought), VanillaLedgerDB.debug and "on" or "off"))
    elseif cmd == "reset" then
        local keepDebug = VanillaLedgerDB.debug
        VanillaLedgerDB = { sold = {}, expired = {}, bought = {}, version = 1, debug = keepDebug }
        ledgerPrint("Ledger reset.")
    elseif cmd == "list" then
        local n = 10
        ledgerPrint("Last 10 sold:")
        local soldCount = getn(VanillaLedgerDB.sold)
        for i = max(1, soldCount - n + 1), soldCount do
            local e = VanillaLedgerDB.sold[i]
            local extra = ""
            if e.money then extra = " - " .. formatCoins(e.money) end
            DEFAULT_CHAT_FRAME:AddMessage(format("- %s (%s)%s", e.item, date("%Y-%m-%d %H:%M", e.t), extra))
        end
    elseif cmd == "summary" then
        local which = nil
        if argText == "today" then which = "today" end
        printSummary(which)
    elseif cmd == "view" then
        if argText == nil or argText == "" then
            ledgerPrint("Usage: /ledger view [all|sold|expired|bought]")
        else
            LedgerSetView(argText)
        end
    elseif cmd == "toggleview" or cmd == "tview" then
        LedgerToggleView()
    elseif cmd == "listexpired" or cmd == "lexp" then
        local n = 10
        ledgerPrint("Last 10 expired:")
        local expCount = getn(VanillaLedgerDB.expired)
        for i = max(1, expCount - n + 1), expCount do
            local e = VanillaLedgerDB.expired[i]
            local qty = tonumber(e.qty or 1) or 1
            if qty < 1 then qty = 1 end
            DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s (%s)", qty, e.item, date("%Y-%m-%d %H:%M", e.t)))
        end
    elseif cmd == "expired" then
        local days = buildExpiredDaySummaries()
        if getn(days) == 0 then ledgerPrint("No expired auctions recorded") return end
        ledgerPrint("Daily expired totals:")
        for i = 1, getn(days) do
            local d = days[i]
            DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items", d.day, d.totalCount))
        end
    elseif cmd == "listbought" or cmd == "lbuy" then
        local n = 10
        ledgerPrint("Last 10 bought:")
        local buyCount = getn(VanillaLedgerDB.bought)
        for i = max(1, buyCount - n + 1), buyCount do
            local e = VanillaLedgerDB.bought[i]
            local qty = tonumber(e.qty or 1) or 1
            if qty < 1 then qty = 1 end
            DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s (%s)", qty, e.item, date("%Y-%m-%d %H:%M", e.t)))
        end
    elseif cmd == "bought" then
        local days = buildBoughtDaySummaries()
        if getn(days) == 0 then ledgerPrint("No bought auctions recorded") return end
        ledgerPrint("Daily bought totals:")
        for i = 1, getn(days) do
            local d = days[i]
            DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items", d.day, d.totalCount))
        end
    elseif cmd == "dayexp" then
        local dkey = argText and gsub(argText, "^%s+", "") or ""
        if dkey == "" then
            ledgerPrint("Usage: /ledger dayexp YYYY-MM-DD")
        else
            local groups = buildExpiredGroups(dkey)
            if getn(groups) == 0 then ledgerPrint("No expired auctions recorded for " .. dkey) return end
            ledgerPrint("Expired for " .. dkey .. ":")
            for i = 1, getn(groups) do
                local g = groups[i]
                DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s", g.count, g.item))
            end
        end
    elseif cmd == "daybuy" then
        local dkey = argText and gsub(argText, "^%s+", "") or ""
        if dkey == "" then
            ledgerPrint("Usage: /ledger daybuy YYYY-MM-DD")
        else
            local groups = buildBoughtGroups(dkey)
            if getn(groups) == 0 then ledgerPrint("No bought auctions recorded for " .. dkey) return end
            ledgerPrint("Bought for " .. dkey .. ":")
            for i = 1, getn(groups) do
                local g = groups[i]
                DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s", g.count, g.item))
            end
        end
    elseif cmd == "day" then
        local dkey = argText and gsub(argText, "^%s+", "") or ""
        if dkey == "" then
            ledgerPrint("Usage: /ledger day YYYY-MM-DD")
        else
            local groups = buildSoldGroups(dkey)
            if getn(groups) == 0 then ledgerPrint("No sales recorded for " .. dkey) return end
            local total = 0; for i = 1, getn(groups) do total = total + (groups[i].total or 0) end
            ledgerPrint("Summary for " .. dkey .. " — total " .. formatCoins(total))
            for i = 1, getn(groups) do
                local g = groups[i]
                local priceText = (g.price and g.price > 0) and (" - total " .. formatCoins(g.total)) or ""
                DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s%s", g.count, g.item, priceText))
            end
        end
    elseif cmd == "days" then
        local days = buildDaySummaries()
        if getn(days) == 0 then ledgerPrint("No sales recorded") return end
        ledgerPrint("Days with activity:")
        for i = 1, getn(days) do
            local d = days[i]
            DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items — %s", d.day, d.totalCount, formatCoins(d.totalMoney)))
        end
    elseif cmd == "revenue" or cmd == "total" or cmd == "sum" then
        local total = 0
        local counted = 0
        for i = 1, getn(VanillaLedgerDB.sold) do
            local e = VanillaLedgerDB.sold[i]
            if e.money and e.money > 0 then
                total = total + e.money
                counted = counted + 1
            end
        end
        ledgerPrint(format("Revenue: %s (from %d mailed sales)", formatCoins(total), counted))
    elseif cmd == "errors" then
        local n = getn(VanillaLedgerErrors)
        if n == 0 then ledgerPrint("No errors logged") return end
        ledgerPrint("Last errors:")
        for i = max(1, n - 9), n do
            DEFAULT_CHAT_FRAME:AddMessage(VanillaLedgerErrors[i])
        end
    elseif cmd == "clrerrors" then
        VanillaLedgerErrors = {}
        ledgerPrint("Error log cleared")
    else
        DEFAULT_CHAT_FRAME:AddMessage("/ledger [stats|status|list|summary [today]|days|day YYYY-MM-DD|revenue|listexpired|expired|dayexp YYYY-MM-DD|listbought|bought|daybuy YYYY-MM-DD|view [all|sold|expired|bought]|toggleview|errors|clrerrors|reset|debug [on|off]]")
    end
end

-- Minimal ledger UI (table view) toggled by the minimap button
local function ledgerTrimText(s, maxLen)
    s = s or "?"
    if string.len(s) <= maxLen then return s end
    if maxLen <= 3 then return string.sub(s, 1, maxLen) end
    return string.sub(s, 1, maxLen - 3) .. "..."
end

local function ledgerBuildRows()
    ensure_db()
    local rows, n = {}, 0

    local soldEntries = getn(VanillaLedgerDB.sold)
    local expEntries = getn(VanillaLedgerDB.expired)
    local boughtEntries = getn(VanillaLedgerDB.bought)
    local soldTotal = 0
    for i = 1, soldEntries do
        local e = VanillaLedgerDB.sold[i]
        if e.money and e.money > 0 then soldTotal = soldTotal + e.money end
    end

    local showSold = (VanillaLedgerDB.view == "all" or VanillaLedgerDB.view == "sold")
    local showExp  = (VanillaLedgerDB.view == "all" or VanillaLedgerDB.view == "expired")
    local showBought = (VanillaLedgerDB.view == "all" or VanillaLedgerDB.view == "bought")

    local function pushRow(typ, ts, qty, amount, item)
        n = n + 1
        rows[n] = {
            typ = typ or "",
            day = date("%Y-%m-%d %H:%M", ts or time()),
            ts = tonumber(ts or 0) or 0,
            qty = tostring(qty or 1),
            amount = amount or "",
            item = ledgerTrimText(item or "?", 52),
        }
    end

    if showSold then
        for i = 1, soldEntries do
            local e = VanillaLedgerDB.sold[i]
            local amountText = "no price"
            if e.money and e.money > 0 then amountText = formatCoins(e.money) end
            pushRow("Sold", e.t, 1, amountText, e.item)
        end
    end

    if showExp then
        for i = 1, expEntries do
            local e = VanillaLedgerDB.expired[i]
            local qty = tonumber(e.qty or 1) or 1
            if qty < 1 then qty = 1 end
            pushRow("Exp", e.t, qty, "n/a", e.item)
        end
    end

    if showBought then
        for i = 1, boughtEntries do
            local e = VanillaLedgerDB.bought[i]
            local qty = tonumber(e.qty or 1) or 1
            if qty < 1 then qty = 1 end
            pushRow("Buy", e.t, qty, "n/a", e.item)
        end
    end

    if n > 1 then
        local function typeRank(t)
            if t == "Sold" then return 3 end
            if t == "Exp" then return 2 end
            if t == "Buy" then return 1 end
            return 0
        end
        table.sort(rows, function(a, b)
            local ta = tonumber(a.ts or 0) or 0
            local tb = tonumber(b.ts or 0) or 0
            if ta ~= tb then
                return ta > tb
            end
            local ra = typeRank(a.typ)
            local rb = typeRank(b.typ)
            if ra ~= rb then return ra > rb end
            if (a.item or "") ~= (b.item or "") then
                return (a.item or "") < (b.item or "")
            end
            return (a.amount or "") > (b.amount or "")
        end)
    end

    if n == 0 then
        n = 1
        rows[n] = { typ = "", day = "", ts = 0, qty = "", amount = "", item = "No ledger entries for this view." }
    end

    return rows, soldEntries, expEntries, boughtEntries, soldTotal
end

function ShowLedgerUI()
    ensure_db()
    if not LedgerFrame then
        local f = CreateFrame("Frame", "LedgerFrame", UIParent)
        local fw, fh = 560, 380
        f:SetWidth(fw); f:SetHeight(fh)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() f:StartMoving() end)
        f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
        title:SetText("Ledger")
        f.title = title

        local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
        subtitle:SetText("")
        f.subtitle = subtitle

        local tableWrap = CreateFrame("Frame", nil, f)
        tableWrap:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -46)
        tableWrap:SetWidth(fw - 20)
        tableWrap:SetHeight(fh - 56)
        f.tableWrap = tableWrap

        local rowAreaWidth = fw - 46
        local rowAreaHeight = fh - 84
        local rowHeight = 15
        local visibleRows = floor(rowAreaHeight / rowHeight)

        local colType, colDate, colQty, colAmount = 42, 112, 36, 108
        local colItem = rowAreaWidth - (colType + colDate + colQty + colAmount + 16)
        if colItem < 120 then colItem = 120 end
        local colXType = 0
        local colXDate = colXType + colType + 4
        local colXQty = colXDate + colDate + 4
        local colXAmount = colXQty + colQty + 4
        local colXItem = colXAmount + colAmount + 4

        local function makeHeaderCell(xPos, width, text, justify)
            local bg = tableWrap:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
            bg:SetVertexColor(1, 1, 1, 0.20)
            bg:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", xPos, 0)
            bg:SetWidth(width)
            bg:SetHeight(16)
            local h = tableWrap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", xPos + 3, -2)
            h:SetWidth(width - 6)
            h:SetJustifyH(justify or "LEFT")
            h:SetText(text or "")
            return bg, h
        end
        makeHeaderCell(colXType, colType, "Type", "LEFT")
        makeHeaderCell(colXDate, colDate, "When", "LEFT")
        makeHeaderCell(colXQty, colQty, "Qty", "RIGHT")
        makeHeaderCell(colXAmount, colAmount, "Revenue", "RIGHT")
        makeHeaderCell(colXItem, colItem, "Item", "LEFT")

        local sep = tableWrap:CreateTexture(nil, "ARTWORK")
        sep:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        sep:SetVertexColor(1, 1, 1, 0.55)
        sep:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", 0, -16)
        sep:SetPoint("TOPRIGHT", tableWrap, "TOPRIGHT", -18, -16)
        sep:SetHeight(1)

        local rowArea = CreateFrame("Frame", nil, tableWrap)
        rowArea:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", 0, -20)
        rowArea:SetWidth(rowAreaWidth)
        rowArea:SetHeight(rowAreaHeight)
        rowArea:EnableMouseWheel(true)
        f.rowArea = rowArea

        local borderTop = tableWrap:CreateTexture(nil, "ARTWORK")
        borderTop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        borderTop:SetVertexColor(1, 1, 1, 0.35)
        borderTop:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, 0)
        borderTop:SetPoint("TOPRIGHT", rowArea, "TOPRIGHT", 0, 0)
        borderTop:SetHeight(1)
        local borderBottom = tableWrap:CreateTexture(nil, "ARTWORK")
        borderBottom:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        borderBottom:SetVertexColor(1, 1, 1, 0.35)
        borderBottom:SetPoint("BOTTOMLEFT", rowArea, "BOTTOMLEFT", 0, 0)
        borderBottom:SetPoint("BOTTOMRIGHT", rowArea, "BOTTOMRIGHT", 0, 0)
        borderBottom:SetHeight(1)
        local borderLeft = tableWrap:CreateTexture(nil, "ARTWORK")
        borderLeft:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        borderLeft:SetVertexColor(1, 1, 1, 0.35)
        borderLeft:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, 0)
        borderLeft:SetPoint("BOTTOMLEFT", rowArea, "BOTTOMLEFT", 0, 0)
        borderLeft:SetWidth(1)
        local borderRight = tableWrap:CreateTexture(nil, "ARTWORK")
        borderRight:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        borderRight:SetVertexColor(1, 1, 1, 0.35)
        borderRight:SetPoint("TOPRIGHT", rowArea, "TOPRIGHT", 0, 0)
        borderRight:SetPoint("BOTTOMRIGHT", rowArea, "BOTTOMRIGHT", 0, 0)
        borderRight:SetWidth(1)

        local function makeVSep(xPos)
            local v = tableWrap:CreateTexture(nil, "ARTWORK")
            v:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
            v:SetVertexColor(1, 1, 1, 0.18)
            v:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", xPos - 2, -1)
            v:SetPoint("BOTTOMLEFT", rowArea, "BOTTOMLEFT", xPos - 2, 0)
            v:SetWidth(1)
            return v
        end
        makeVSep(colXDate)
        makeVSep(colXQty)
        makeVSep(colXAmount)
        makeVSep(colXItem)

        local slider = CreateFrame("Slider", nil, tableWrap, "UIPanelScrollBarTemplate")
        slider:SetPoint("TOPRIGHT", tableWrap, "TOPRIGHT", 0, -20)
        slider:SetPoint("BOTTOMRIGHT", tableWrap, "BOTTOMRIGHT", 0, 0)
        slider:SetMinMaxValues(0, 0)
        slider:SetValueStep(1)
        slider:SetValue(0)
        f.slider = slider

        f.rows = {}
        f.rowHeight = rowHeight
        f.visibleRows = visibleRows
        f.rowOffset = 0
        f.rowAreaWidth = rowAreaWidth
        f.colType = colType
        f.colDate = colDate
        f.colQty = colQty
        f.colAmount = colAmount
        f.colItem = colItem

        for i = 1, visibleRows do
            local r = CreateFrame("Frame", nil, rowArea)
            r:SetWidth(rowAreaWidth)
            r:SetHeight(rowHeight)
            r:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, -((i - 1) * rowHeight))

            local rowShade = (mod(i, 2) == 0) and 0.16 or 0.10
            local function makeRowCell(xPos, width, justify)
                local bg = r:CreateTexture(nil, "BACKGROUND")
                bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
                bg:SetVertexColor(1, 1, 1, rowShade)
                bg:SetPoint("TOPLEFT", r, "TOPLEFT", xPos, 0)
                bg:SetWidth(width)
                bg:SetHeight(rowHeight)
                local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", r, "TOPLEFT", xPos + 3, 0)
                fs:SetWidth(width - 6)
                fs:SetJustifyH(justify or "LEFT")
                return bg, fs
            end
            local bgType, cType = makeRowCell(colXType, colType, "LEFT")
            local bgDate, cDate = makeRowCell(colXDate, colDate, "LEFT")
            local bgQty, cQty = makeRowCell(colXQty, colQty, "RIGHT")
            local bgAmount, cAmount = makeRowCell(colXAmount, colAmount, "RIGHT")
            local bgItem, cItem = makeRowCell(colXItem, colItem, "LEFT")
            r.bgType = bgType
            r.bgDate = bgDate
            r.bgQty = bgQty
            r.bgAmount = bgAmount
            r.bgItem = bgItem

            local rowSep = r:CreateTexture(nil, "ARTWORK")
            rowSep:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
            rowSep:SetVertexColor(1, 1, 1, 0.20)
            rowSep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
            rowSep:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
            rowSep:SetHeight(1)

            r.cType = cType
            r.cDate = cDate
            r.cQty = cQty
            r.cAmount = cAmount
            r.cItem = cItem

            f.rows[i] = r
        end

        f.RenderRows = function()
            local total = getn(f.dataRows or {})
            local maxOffset = max(0, total - f.visibleRows)
            if f.rowOffset > maxOffset then f.rowOffset = maxOffset end
            if f.rowOffset < 0 then f.rowOffset = 0 end
            f.maxOffset = maxOffset

            f._syncingSlider = true
            f.slider:SetMinMaxValues(0, maxOffset)
            f.slider:SetValue(f.rowOffset)
            f._syncingSlider = nil
            if maxOffset > 0 then f.slider:Show() else f.slider:Hide() end

            for i = 1, f.visibleRows do
                local row = f.rows[i]
                local data = f.dataRows[f.rowOffset + i]
                if data then
                    local typ = data.typ or ""
                    if typ == "Sold" then
                        row.cType:SetText("|cff66ff66Sold|r")
                    elseif typ == "Exp" then
                        row.cType:SetText("|cffff6666Exp|r")
                    elseif typ == "Buy" then
                        row.cType:SetText("|cffffff66Buy|r")
                    else
                        row.cType:SetText(typ)
                    end
                    row.cDate:SetText(data.day or "")
                    row.cQty:SetText(data.qty or "")
                    row.cAmount:SetText(data.amount or "")
                    row.cItem:SetText(data.item or "")
                    row:Show()
                else
                    row:Hide()
                end
            end
        end

        local function stepScroll(delta)
            local nextOffset = f.rowOffset
            local step = 4
            if IsShiftKeyDown and IsShiftKeyDown() then
                step = 16
            elseif IsControlKeyDown and IsControlKeyDown() then
                step = 1
            end
            if delta > 0 then nextOffset = nextOffset - step else nextOffset = nextOffset + step end
            if nextOffset < 0 then nextOffset = 0 end
            if nextOffset > (f.maxOffset or 0) then nextOffset = f.maxOffset or 0 end
            f.rowOffset = nextOffset
            f:RenderRows()
        end

        rowArea:SetScript("OnMouseWheel", function()
            stepScroll(arg1)
        end)

        slider:SetScript("OnValueChanged", function()
            if f._syncingSlider then return end
            local v = floor((this:GetValue() or 0) + 0.5)
            if v < 0 then v = 0 end
            f.rowOffset = v
            f:RenderRows()
        end)

        -- View buttons (All, Sold, Exp, Buy)
        local function makeBtn(name, text, xOff, handler)
            local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
            b:SetWidth(58); b:SetHeight(20)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", xOff, -30)
            b:SetText(text)
            b:SetScript("OnClick", handler)
            return b
        end
        makeBtn("LedgerBtnAll", "All", -14, function() LedgerSetView("all") end)
        makeBtn("LedgerBtnSold", "Sold", -76, function() LedgerSetView("sold") end)
        makeBtn("LedgerBtnExp", "Exp", -138, function() LedgerSetView("expired") end)
        makeBtn("LedgerBtnBuy", "Buy", -200, function() LedgerSetView("bought") end)

        local dbgBtn = CreateFrame("Button", "LedgerBtnDebug", f, "UIPanelButtonTemplate")
        dbgBtn:SetWidth(72); dbgBtn:SetHeight(20)
        dbgBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
        dbgBtn:SetText("Dbg On")
        dbgBtn:SetScript("OnClick", function()
            ensure_db()
            VanillaLedgerDB.debug = not VanillaLedgerDB.debug
            ledgerPrint("Debug " .. (VanillaLedgerDB.debug and "enabled" or "disabled"))
            if LedgerFrame and LedgerFrame:IsShown() then ShowLedgerUI() end
        end)
        f.debugBtn = dbgBtn

        -- Allow closing with ESC like standard UI panels
        UISpecialFrames = UISpecialFrames or {}
        local found = false
        local n = (getn and getn(UISpecialFrames)) or 0
        for i = 1, n do
            if UISpecialFrames[i] == "LedgerFrame" then
                found = true
                break
            end
        end
        if not found then tinsert(UISpecialFrames, "LedgerFrame") end

        LedgerFrame = f
    end

    local header = "Ledger"
    if VanillaLedgerDB and VanillaLedgerDB.view then
        header = header .. " - " .. strupper(string.sub(VanillaLedgerDB.view, 1, 1)) .. string.sub(VanillaLedgerDB.view, 2)
    end
    if LedgerFrame.title then LedgerFrame.title:SetText(header) end
    if LedgerFrame.debugBtn then
        LedgerFrame.debugBtn:SetText((VanillaLedgerDB.debug and "Dbg On") or "Dbg Off")
    end

    local rows, soldEntries, expEntries, boughtEntries, soldTotal = ledgerBuildRows()
    LedgerFrame.dataRows = rows
    LedgerFrame.rowOffset = 0
    if LedgerFrame.subtitle then
        LedgerFrame.subtitle:SetText(format("Sold: %d (%s)   Expired: %d   Bought: %d", soldEntries, formatCoins(soldTotal), expEntries, boughtEntries))
    end
    LedgerFrame:RenderRows()
    LedgerFrame:Show()
end

-- Error logging: wrap the error handler to collect into SavedVariables
do
    local origHandler = geterrorhandler and geterrorhandler() or nil
    local function handler(msg)
        ensure_db()
        local line = format("%s %s", date("%Y-%m-%d %H:%M:%S"), tostring(msg))
        tinsert(VanillaLedgerErrors, line)
        if getn(VanillaLedgerErrors) > 200 then
            table.remove(VanillaLedgerErrors, 1)
        end
        if origHandler then return origHandler(msg) end
    end
    if seterrorhandler then
        seterrorhandler(handler)
    end
end

-- Hook taking money to ensure recording even if dedupe or timing missed it
do
    local orig_TakeInboxMoney = TakeInboxMoney
    function TakeInboxMoney(index)
        recordInboxInteract(index)
        return orig_TakeInboxMoney(index)
    end
end

-- Hook other common mail API used by auto-mail addons
do
    local orig_AutoLootMailItem = AutoLootMailItem
    if orig_AutoLootMailItem then
        function AutoLootMailItem(index)
            recordInboxInteract(index)
            return orig_AutoLootMailItem(index)
        end
    end
end

do
    local orig_TakeInboxItem = TakeInboxItem
    if orig_TakeInboxItem then
        function TakeInboxItem(index, attachment)
            recordInboxInteract(index)
            return orig_TakeInboxItem(index, attachment)
        end
    end
end

do
    local orig_DeleteInboxItem = DeleteInboxItem
    if orig_DeleteInboxItem then
        function DeleteInboxItem(index)
            recordInboxInteract(index)
            return orig_DeleteInboxItem(index)
        end
    end
end
