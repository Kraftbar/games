-- Auction ledger storage, summaries, and commands. No mailbox or UI dependencies.

local VA = VanillaAddon
local Ledger = {}
VA.Ledger = Ledger
VA:RegisterModule("ledger-core", Ledger)

Ledger.maxRows = 50000

function Ledger:EnsureDB()
    VanillaLedgerDB = VanillaLedgerDB or {}
    VanillaLedgerDB.sold = VanillaLedgerDB.sold or {}
    VanillaLedgerDB.expired = VanillaLedgerDB.expired or {}
    VanillaLedgerDB.bought = VanillaLedgerDB.bought or {}
    VanillaLedgerDB.mailSeen = VanillaLedgerDB.mailSeen or {}
    VanillaLedgerDB.pendingPosts = VanillaLedgerDB.pendingPosts or {}
    VanillaLedgerDB.pendingBids = VanillaLedgerDB.pendingBids or {}
    VanillaLedgerDB.costLots = VanillaLedgerDB.costLots or {}
    VanillaLedgerDB.version = 3
    if VanillaLedgerDB.debug == nil then VanillaLedgerDB.debug = false end
    VanillaLedgerErrors = VanillaLedgerErrors or {}
    self.db = VanillaLedgerDB
    if not VanillaLedgerDB.modularViewMigrated then
        if (VanillaLedgerDB.view == "sold" or VanillaLedgerDB.view == "expired" or VanillaLedgerDB.view == "bought") and VA.settings.ledger.view == "all" then
            VA.settings.ledger.view = VanillaLedgerDB.view
        end
        VanillaLedgerDB.modularViewMigrated = true
    end
    return self.db
end

function Ledger:Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Ledger]|r " .. tostring(message or "")) end
end

function Ledger:Debug(message)
    self:EnsureDB()
    if self.db.debug then self:Print(message) end
    VA:Diag("ledger", message)
end

local function trimHead(rows, maximum)
    local count = VA:ArrayLen(rows)
    if count <= maximum + 200 then return end
    local cut = count - maximum
    local write = 1
    for read = cut + 1, count do rows[write] = rows[read]; write = write + 1 end
    for i = write, count do rows[i] = nil end
end

function Ledger:Add(bucket, row)
    self:EnsureDB()
    row.t = row.t or time()
    row.qty = tonumber(row.qty or 1) or 1
    if VA.LedgerEconomics and VA.LedgerEconomics.Enrich then
        VA.LedgerEconomics:Enrich(bucket, row)
    end
    tinsert(self.db[bucket], row)
    trimHead(self.db[bucket], self.maxRows)
    VA:Emit("LEDGER_UPDATED", { bucket = bucket, row = row })
    return row
end

function Ledger:FindMergeCandidate(bucket, item, deliveredAt)
    self:EnsureDB()
    local rows = self.db[bucket]
    local count = VA:ArrayLen(rows)
    for i = count, max(1, count - 400), -1 do
        local row = rows[i]
        if row and row.item == item and (row.source == "chat" or (not row.source and not row.money)) then
            local difference = (deliveredAt or 0) - (row.t or 0)
            if difference > -600 and difference < 36 * 60 * 60 then return row end
        end
    end
    return nil
end

function Ledger:RecordMail(bucket, item, qty, deliveredAt, money, reason)
    local row = self:FindMergeCandidate(bucket, item, deliveredAt)
    if row then
        row.qty = tonumber(qty or row.qty or 1) or 1
        if money and money > 0 then row.money = money end
        row.source = "chat+mail"
        if VA.LedgerEconomics then VA.LedgerEconomics:Enrich(bucket, row) end
        VA:Emit("LEDGER_UPDATED", { bucket = bucket, row = row })
        return row
    end
    return self:Add(bucket, {
        item = item,
        qty = qty or 1,
        t = deliveredAt,
        money = money,
        source = "mail",
        mailReason = reason,
    })
end

function Ledger:RecordChat(bucket, item)
    return self:Add(bucket, { item = item, qty = 1, t = time(), source = "chat" })
end

function Ledger:GetProfit(row)
    local proceeds = tonumber(row.money or 0) or 0
    local cost = tonumber(row.costBasis or 0) or 0
    local lostDeposit = tonumber(row.depositLost or 0) or 0
    return proceeds - cost - lostDeposit
end

function Ledger:GetTotals()
    self:EnsureDB()
    local totals = { revenue = 0, knownCost = 0, profit = 0, knownProfitSales = 0, unknownProfitSales = 0, depositsLost = 0, sold = VA:ArrayLen(self.db.sold), expired = VA:ArrayLen(self.db.expired), bought = VA:ArrayLen(self.db.bought) }
    for i = 1, totals.sold do
        local row = self.db.sold[i]
        totals.revenue = totals.revenue + (tonumber(row.money or 0) or 0)
        totals.knownCost = totals.knownCost + (tonumber(row.costBasis or 0) or 0)
        if row.costBasisComplete then
            totals.profit = totals.profit + self:GetProfit(row)
            totals.knownProfitSales = totals.knownProfitSales + 1
        else
            totals.unknownProfitSales = totals.unknownProfitSales + 1
        end
    end
    for i = 1, totals.expired do
        local row = self.db.expired[i]
        totals.depositsLost = totals.depositsLost + (tonumber(row.depositLost or 0) or 0)
        totals.profit = totals.profit - (tonumber(row.depositLost or 0) or 0)
    end
    return totals
end

function Ledger:BuildRows(view)
    self:EnsureDB()
    view = view or VA.settings.ledger.view or "all"
    local rows = {}
    local count = 0
    local function push(bucket, label, row)
        count = count + 1
        local amount = tonumber(row.money or 0) or 0
        rows[count] = {
            bucket = bucket,
            label = label,
            t = tonumber(row.t or 0) or 0,
            qty = tonumber(row.qty or 1) or 1,
            amount = amount,
            profit = bucket == "sold" and self:GetProfit(row) or (bucket == "expired" and -(tonumber(row.depositLost or 0) or 0) or 0),
            profitKnown = (bucket == "sold" and row.costBasisComplete) or (bucket == "expired" and row.depositLost ~= nil),
            item = row.item or "?",
            raw = row,
        }
    end
    if view == "all" or view == "sold" then for i = 1, VA:ArrayLen(self.db.sold) do push("sold", "Sold", self.db.sold[i]) end end
    if view == "all" or view == "expired" then for i = 1, VA:ArrayLen(self.db.expired) do push("expired", "Exp", self.db.expired[i]) end end
    if view == "all" or view == "bought" then for i = 1, VA:ArrayLen(self.db.bought) do push("bought", "Buy", self.db.bought[i]) end end
    table.sort(rows, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return (a.item or "") < (b.item or "")
    end)
    return rows
end

function Ledger:SetView(view)
    if view ~= "all" and view ~= "sold" and view ~= "expired" and view ~= "bought" then
        self:Print("View must be all, sold, expired, or bought")
        return
    end
    VA.settings.ledger.view = view
    VA:Emit("LEDGER_VIEW_CHANGED", view)
end

Ledger:EnsureDB()
VA:On("PLAYER_READY", function() Ledger:EnsureDB() end)

SLASH_LEDGER1 = "/ledger"
SlashCmdList["LEDGER"] = function(message)
    Ledger:EnsureDB()
    message = gsub(message or "", "^%s+", "")
    message = gsub(message, "%s+$", "")
    local _, _, command, argument = strfind(message, "^(%S+)%s*(.*)$")
    command = strlower(command or "ui")
    argument = strlower(argument or "")
    if command == "ui" or command == "show" then
        if VA.LedgerUI then VA.LedgerUI:Show() else Ledger:Print("Ledger UI module is disabled") end
    elseif command == "view" then
        Ledger:SetView(argument)
    elseif command == "debug" then
        if argument == "on" then Ledger.db.debug = true
        elseif argument == "off" then Ledger.db.debug = false
        else Ledger.db.debug = not Ledger.db.debug end
        Ledger:Print("Debug " .. (Ledger.db.debug and "enabled" or "disabled"))
    elseif command == "clear" or command == "reset" then
        local debug = Ledger.db.debug
        local addon = VanillaLedgerDB.addon or VanillaAddonDB
        VanillaLedgerDB = { sold = {}, expired = {}, bought = {}, mailSeen = {}, pendingPosts = {}, pendingBids = {}, costLots = {}, version = 3, debug = debug, addon = addon }
        VA:EnsureDB()
        Ledger:EnsureDB()
        VA:Emit("LEDGER_UPDATED")
        Ledger:Print("Ledger reset")
    elseif command == "errors" then
        local count = VA:ArrayLen(VanillaLedgerErrors)
        for i = max(1, count - 9), count do DEFAULT_CHAT_FRAME:AddMessage(VanillaLedgerErrors[i]) end
    elseif command == "clrerrors" then
        VanillaLedgerErrors = {}
        Ledger:Print("Error log cleared")
    elseif command == "cut" then
        local percent = tonumber(argument)
        if percent and percent >= 0 and percent < 100 then
            VA.settings.ledger.cutRate = percent / 100
            for i = 1, VA:ArrayLen(Ledger.db.sold) do
                local row = Ledger.db.sold[i]
                if row.money and row.money > 0 then
                    row.estimatedGross = floor((row.money / max(0.01, 1 - VA.settings.ledger.cutRate)) + 0.5)
                    row.estimatedCut = max(0, row.estimatedGross - row.money)
                end
            end
            VA:Emit("LEDGER_UPDATED")
            Ledger:Print("Estimated AH cut set to " .. percent .. "%")
        else Ledger:Print("Usage: /ledger cut <percent>") end
    elseif command == "economics" and VA.LedgerEconomics then
        VA.LedgerEconomics:PrintStatus()
    else
        local totals = Ledger:GetTotals()
        Ledger:Print(format("Sold %d, expired %d, bought %d | revenue %s | known profit %s (%d sales unknown)",
            totals.sold, totals.expired, totals.bought, VA:FormatCoins(totals.revenue), VA:FormatCoins(totals.profit), totals.unknownProfitSales))
        Ledger:Print("Commands: ui | view all|sold|expired|bought | economics | cut <percent> | debug | reset")
    end
end
