-- Optional auction economics: posts, deposits, bids, fees, and FIFO cost basis.

local VA = VanillaAddon
local Ledger = VA.Ledger
local Economics = { postCalls = {}, bidCalls = {} }
VA.LedgerEconomics = Economics
VA:RegisterModule("ledger-economics", Economics)

local function prunePending(rows, maximumAge)
    local cutoff = time() - maximumAge
    local write = 1
    for read = 1, VA:ArrayLen(rows) do
        local row = rows[read]
        if row and (row.t or 0) >= cutoff then rows[write] = row; write = write + 1 end
    end
    for i = write, VA:ArrayLen(rows) do rows[i] = nil end
end

local function takeMatching(rows, item, newest)
    local startIndex, endIndex, step = 1, VA:ArrayLen(rows), 1
    if newest then startIndex, endIndex, step = VA:ArrayLen(rows), 1, -1 end
    for i = startIndex, endIndex, step do
        local row = rows[i]
        if row and row.item == item then
            table.remove(rows, i)
            return row
        end
    end
    return nil
end

function Economics:ConfirmPost()
    local row = table.remove(self.postCalls, 1)
    if not row then return end
    tinsert(Ledger.db.pendingPosts, row)
    Ledger:Debug("Post captured: " .. row.item .. " x" .. row.qty .. ", deposit " .. VA:FormatCoins(row.deposit))
end

function Economics:ConfirmBid()
    local row = table.remove(self.bidCalls, 1)
    if not row then return end
    tinsert(Ledger.db.pendingBids, row)
    Ledger:Debug("Bid captured: " .. row.item .. " x" .. row.qty .. " for " .. VA:FormatCoins(row.cost))
end

function Economics:RejectPost() table.remove(self.postCalls, 1) end
function Economics:RejectBid() table.remove(self.bidCalls, 1) end

function Economics:AddCostLot(item, qty, totalCost, timestamp)
    if not item or not totalCost or totalCost <= 0 then return end
    tinsert(Ledger.db.costLots, { item = item, qty = max(1, qty or 1), cost = totalCost, t = timestamp or time() })
end

function Economics:ConsumeCost(item, requestedQty)
    local needed = max(1, tonumber(requestedQty or 1) or 1)
    local total = 0
    local knownQty = 0
    local index = 1
    while index <= VA:ArrayLen(Ledger.db.costLots) and needed > 0 do
        local lot = Ledger.db.costLots[index]
        if lot.item == item and (lot.qty or 0) > 0 then
            local take = min(needed, lot.qty)
            local unitCost = (lot.cost or 0) / lot.qty
            total = total + unitCost * take
            knownQty = knownQty + take
            needed = needed - take
            lot.qty = lot.qty - take
            lot.cost = max(0, lot.cost - unitCost * take)
            if lot.qty <= 0 then table.remove(Ledger.db.costLots, index) else index = index + 1 end
        else
            index = index + 1
        end
    end
    if knownQty == 0 then return nil, 0 end
    return floor(total + 0.5), knownQty
end

function Economics:Enrich(bucket, row)
    Ledger:EnsureDB()
    prunePending(Ledger.db.pendingPosts, 35 * 24 * 60 * 60)
    prunePending(Ledger.db.pendingBids, 35 * 24 * 60 * 60)
    if bucket == "bought" then
        if not row.purchaseCost then
            -- Re-bids on the same auction are common; the newest accepted bid
            -- is the best cost candidate for the eventual win mail.
            local bid = takeMatching(Ledger.db.pendingBids, row.item, true)
            if bid then
                row.purchaseCost = bid.cost
                row.qty = bid.qty or row.qty
                row.buyout = bid.buyout
            end
        end
        if row.purchaseCost and not row.costLotAdded then
            self:AddCostLot(row.item, row.qty, row.purchaseCost, row.t)
            row.costLotAdded = true
        end
    elseif bucket == "sold" then
        if not row.postMatched then
            local post = takeMatching(Ledger.db.pendingPosts, row.item)
            if post then
                row.postMatched = true
                row.qty = post.qty or row.qty
                row.deposit = post.deposit
                row.ask = post.buyout
            end
        end
        if row.money and row.money > 0 then
            local rate = tonumber(VA.settings.ledger.cutRate or 0.05) or 0.05
            row.estimatedGross = floor((row.money / max(0.01, 1 - rate)) + 0.5)
            row.estimatedCut = max(0, row.estimatedGross - row.money)
        end
        if row.costBasis == nil then
            local cost, knownQty = self:ConsumeCost(row.item, row.qty)
            if cost then
                row.costBasis = cost
                row.costBasisQty = knownQty
                row.costBasisComplete = knownQty >= (tonumber(row.qty or 1) or 1)
            end
        end
    elseif bucket == "expired" and not row.postMatched then
        local post = takeMatching(Ledger.db.pendingPosts, row.item)
        if post then
            row.postMatched = true
            row.qty = post.qty or row.qty
            row.depositLost = post.deposit or 0
            row.ask = post.buyout
        end
    end
end

function Economics:PrintStatus()
    local totals = Ledger:GetTotals()
    Ledger:Print("Revenue " .. VA:FormatCoins(totals.revenue) .. ", known cost " .. VA:FormatCoins(totals.knownCost) .. ", lost deposits " .. VA:FormatCoins(totals.depositsLost) .. ", known profit " .. VA:FormatCoins(totals.profit))
    Ledger:Print(format("Profit basis complete for %d sales; unknown/incomplete for %d", totals.knownProfitSales, totals.unknownProfitSales))
    Ledger:Print(format("Pending posts %d, bids %d, cost lots %d", VA:ArrayLen(Ledger.db.pendingPosts), VA:ArrayLen(Ledger.db.pendingBids), VA:ArrayLen(Ledger.db.costLots)))
end

local originalStartAuction = StartAuction
if originalStartAuction then
    function StartAuction(minBid, buyoutPrice, runTime)
        local item, _, count = GetAuctionSellItemInfo()
        if item and count then
            local deposit = CalculateAuctionDeposit and CalculateAuctionDeposit(runTime) or 0
            tinsert(Economics.postCalls, { item = item, qty = count, minBid = minBid, buyout = buyoutPrice, duration = runTime, deposit = deposit or 0, t = time() })
        end
        return originalStartAuction(minBid, buyoutPrice, runTime)
    end
end

local originalPlaceAuctionBid = PlaceAuctionBid
if originalPlaceAuctionBid then
    function PlaceAuctionBid(listType, index, bid)
        local item, _, count, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo(listType, index)
        if item and count and bid then
            tinsert(Economics.bidCalls, { item = item, qty = count, cost = bid, buyout = buyoutPrice and bid == buyoutPrice, t = time() })
        end
        return originalPlaceAuctionBid(listType, index, bid)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_SYSTEM" then
        if ERR_AUCTION_STARTED and arg1 == ERR_AUCTION_STARTED then Economics:ConfirmPost() end
        if ERR_AUCTION_BID_PLACED and arg1 == ERR_AUCTION_BID_PLACED then Economics:ConfirmBid() end
    elseif event == "UI_ERROR_MESSAGE" then
        if arg1 == ERR_NOT_ENOUGH_MONEY then Economics:RejectPost(); Economics:RejectBid()
        elseif arg1 == ERR_ITEM_NOT_FOUND or arg1 == ERR_AUCTION_BID_OWN or arg1 == ERR_AUCTION_HIGHER_BID then Economics:RejectBid() end
    end
end)
