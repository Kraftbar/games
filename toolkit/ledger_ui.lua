-- Optional ledger table and minimap button.

local VA = VanillaAddon
local Ledger = VA.Ledger
local UI = { offset = 0, visibleRows = 16 }
VA.LedgerUI = UI
VA:RegisterModule("ledger-ui", UI)

local columns = {
    { key = "type", x = 0, width = 42, title = "Type" },
    { key = "date", x = 46, width = 108, title = "When" },
    { key = "qty", x = 158, width = 34, title = "Qty", right = true },
    { key = "amount", x = 196, width = 96, title = "Revenue", right = true },
    { key = "profit", x = 296, width = 96, title = "Profit", right = true },
    { key = "item", x = 396, width = 190, title = "Item" },
}

local function makeText(parent, x, width, font, right)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 3, 0)
    text:SetWidth(width - 6)
    text:SetJustifyH(right and "RIGHT" or "LEFT")
    return text
end

function UI:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "LedgerFrame", UIParent)
    frame:SetWidth(620); frame:SetHeight(370)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0, 0, 0, 0.96)
    VA:ApplyFramePosition("ledger", frame, "CENTER", 0, 0)
    VA:MakeMovable(frame, "ledger")
    frame:Hide()
    self.frame = frame

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("Auction Ledger")
    frame.title = title
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -32)
    frame.subtitle = subtitle

    local views = { { "All", "all" }, { "Sold", "sold" }, { "Exp", "expired" }, { "Buy", "bought" } }
    for i = 1, VA:ArrayLen(views) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(52); button:SetHeight(20)
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12 - ((i - 1) * 56), -28)
        button:SetText(views[i][1])
        local view = views[i][2]
        button:SetScript("OnClick", function() Ledger:SetView(view) end)
    end

    local tableFrame = CreateFrame("Frame", nil, frame)
    tableFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -58)
    tableFrame:SetWidth(590); tableFrame:SetHeight(290)
    -- UIPanelScrollBarTemplate fires its inherited OnValueChanged during
    -- creation and expects its parent to implement this ScrollFrame method.
    -- Rows are offset manually, so the template callback should be a no-op.
    tableFrame.SetVerticalScroll = function() end
    self.tableFrame = tableFrame
    for i = 1, VA:ArrayLen(columns) do
        local column = columns[i]
        local header = makeText(tableFrame, column.x, column.width, "GameFontNormalSmall", column.right)
        header:SetText(column.title)
    end

    local rowArea = CreateFrame("Frame", nil, tableFrame)
    rowArea:SetPoint("TOPLEFT", tableFrame, "TOPLEFT", 0, -20)
    rowArea:SetWidth(586); rowArea:SetHeight(256)
    rowArea:EnableMouseWheel(true)
    self.rowArea = rowArea
    self.rows = {}
    for rowIndex = 1, self.visibleRows do
        local row = CreateFrame("Frame", nil, rowArea)
        row:SetWidth(586); row:SetHeight(16)
        row:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, -((rowIndex - 1) * 16))
        row.cells = {}
        for columnIndex = 1, VA:ArrayLen(columns) do
            local column = columns[columnIndex]
            row.cells[column.key] = makeText(row, column.x, column.width, "GameFontHighlightSmall", column.right)
        end
        self.rows[rowIndex] = row
    end

    local slider = CreateFrame("Slider", nil, tableFrame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPRIGHT", tableFrame, "TOPRIGHT", 10, -18)
    slider:SetPoint("BOTTOMRIGHT", tableFrame, "BOTTOMRIGHT", 10, 0)
    slider:SetMinMaxValues(0, 0); slider:SetValueStep(1); slider:SetValue(0)
    slider:SetScript("OnValueChanged", function()
        if UI.syncing then return end
        UI.offset = floor((this:GetValue() or 0) + 0.5)
        UI:Render()
    end)
    self.slider = slider
    rowArea:SetScript("OnMouseWheel", function()
        local step = IsShiftKeyDown and IsShiftKeyDown() and 10 or 3
        UI.offset = max(0, min(UI.maxOffset or 0, UI.offset + (arg1 > 0 and -step or step)))
        UI:Render()
    end)

    UISpecialFrames = UISpecialFrames or {}
    tinsert(UISpecialFrames, "LedgerFrame")
end

function UI:Refresh()
    self:Create()
    self.data = Ledger:BuildRows(VA.settings.ledger.view)
    self.offset = min(self.offset or 0, max(0, VA:ArrayLen(self.data) - self.visibleRows))
    local totals = Ledger:GetTotals()
    self.frame.title:SetText("Auction Ledger - " .. strupper(strsub(VA.settings.ledger.view, 1, 1)) .. strsub(VA.settings.ledger.view, 2))
    self.frame.subtitle:SetText(format("Sold %d | Expired %d | Bought %d | Revenue %s | Known profit %s (%d unknown)",
        totals.sold, totals.expired, totals.bought, VA:FormatCoins(totals.revenue), VA:FormatCoins(totals.profit), totals.unknownProfitSales))
    self:Render()
end

function UI:Render()
    local count = VA:ArrayLen(self.data or {})
    self.maxOffset = max(0, count - self.visibleRows)
    self.offset = max(0, min(self.offset or 0, self.maxOffset))
    self.syncing = true
    self.slider:SetMinMaxValues(0, self.maxOffset)
    self.slider:SetValue(self.offset)
    self.syncing = nil
    if self.maxOffset > 0 then self.slider:Show() else self.slider:Hide() end
    for i = 1, self.visibleRows do
        local frameRow = self.rows[i]
        local row = self.data[self.offset + i]
        if row then
            local color = row.bucket == "sold" and "|cff66ff66" or (row.bucket == "expired" and "|cffff6666" or "|cffffff66")
            frameRow.cells.type:SetText(color .. row.label .. "|r")
            frameRow.cells.date:SetText(date("%Y-%m-%d %H:%M", row.t))
            frameRow.cells.qty:SetText(tostring(row.qty))
            frameRow.cells.amount:SetText(row.amount > 0 and VA:FormatCoins(row.amount) or "-")
            frameRow.cells.profit:SetText(row.profitKnown and VA:FormatCoins(row.profit) or "?")
            frameRow.cells.item:SetText(VA:TrimText(row.item, 30))
            frameRow:Show()
        else frameRow:Hide() end
    end
end

function UI:Show()
    self:Refresh()
    self.frame:Show()
end

function UI:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

VA:On("LEDGER_UPDATED", function() if UI.frame and UI.frame:IsShown() then UI:Refresh() end end)
VA:On("LEDGER_VIEW_CHANGED", function() if UI.frame and UI.frame:IsShown() then UI:Refresh() end end)

VA:On("PLAYER_READY", function()
    local button = CreateFrame("Button", "LedgerMinimapButton", Minimap or UIParent)
    button:SetWidth(31); button:SetHeight(31)
    button:SetFrameStrata("LOW"); button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    VA:ApplyFramePosition("ledgerButton", button, "TOPLEFT", 8, -8, Minimap or UIParent)
    VA:MakeMovable(button, "ledgerButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetWidth(52); overlay:SetHeight(52); overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95); icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnClick", function()
        if arg1 == "RightButton" then SlashCmdList["LEDGER"]("status") else UI:Toggle() end
    end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT"); GameTooltip:SetText("Auction Ledger"); GameTooltip:AddLine("Left-click: ledger  Right-click: totals", 0.9, 0.9, 0.9); GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.minimapButton = button
end)
