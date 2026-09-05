-- Optional Aux search window, filters, sorting, debounce, and minimap button.

local VA = VanillaAddon
local Search = VA.AuxSearch
local UI = { visibleRows = 14, offset = 0, lastQuery = "" }
VA.AuxUI = UI
VA:RegisterModule("aux-ui", UI)

local function newInput(name, parent, width)
    local input = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    input:SetAutoFocus(false); input:SetWidth(width); input:SetHeight(20)
    return input
end

local function newHeader(parent, text, x, width, key, right)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0); button:SetWidth(width); button:SetHeight(18)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(button); label:SetJustifyH(right and "RIGHT" or "LEFT"); label:SetText(text)
    button.label = label
    button:SetScript("OnClick", function()
        Search:SetSort(key)
        Search:Run(UI.lastQuery)
    end)
    return button
end

function UI:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "AuxFindFrame", UIParent)
    frame:SetWidth(580); frame:SetHeight(370)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0, 0, 0, 0.96)
    VA:ApplyFramePosition("auxSearch", frame, "CENTER", 0, 0)
    VA:MakeMovable(frame, "auxSearch")
    self.frame = frame

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12); title:SetText("Aux Offline Search")

    local query = newInput("AuxFindEditBox", frame, 330)
    query:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -38)
    self.query = query
    local searchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    searchButton:SetWidth(72); searchButton:SetHeight(20); searchButton:SetPoint("LEFT", query, "RIGHT", 6, 0); searchButton:SetText("Search")

    local minLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66); minLabel:SetText("Min gold")
    local minInput = newInput("AuxFindMinGold", frame, 54)
    minInput:SetPoint("LEFT", minLabel, "RIGHT", 6, 0); minInput:SetText(tostring((VA.settings.aux.minCopper or 0) / 10000))
    self.minInput = minInput
    local maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("LEFT", minInput, "RIGHT", 12, 0); maxLabel:SetText("Max gold")
    local maxInput = newInput("AuxFindMaxGold", frame, 54)
    maxInput:SetPoint("LEFT", maxLabel, "RIGHT", 6, 0); maxInput:SetText(tostring((VA.settings.aux.maxCopper or 0) / 10000))
    self.maxInput = maxInput

    local cached = CreateFrame("CheckButton", "AuxFindCachedOnly", frame, "UICheckButtonTemplate")
    cached:SetPoint("LEFT", maxInput, "RIGHT", 10, 0); cached:SetWidth(22); cached:SetHeight(22)
    cached:SetChecked(VA.settings.aux.cachedOnly and 1 or nil)
    local cachedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cachedLabel:SetPoint("LEFT", cached, "RIGHT", 1, 0); cachedLabel:SetText("Cached only")
    self.cached = cached

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -91); subtitle:SetText("")
    self.subtitle = subtitle

    local tableFrame = CreateFrame("Frame", nil, frame)
    tableFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -112); tableFrame:SetWidth(548); tableFrame:SetHeight(238)
    -- See ledger_ui: the Vanilla scrollbar template updates its parent before
    -- our own OnValueChanged handler can be installed.
    tableFrame.SetVerticalScroll = function() end
    self.nameHeader = newHeader(tableFrame, "Item", 0, 300, "name", false)
    self.idHeader = newHeader(tableFrame, "ID", 304, 62, "id", true)
    self.priceHeader = newHeader(tableFrame, "Price", 370, 160, "price", true)

    local rowArea = CreateFrame("Frame", nil, tableFrame)
    rowArea:SetPoint("TOPLEFT", tableFrame, "TOPLEFT", 0, -22); rowArea:SetWidth(530); rowArea:SetHeight(210); rowArea:EnableMouseWheel(true)
    self.rows = {}
    for i = 1, self.visibleRows do
        local row = CreateFrame("Frame", nil, rowArea)
        row:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, -((i - 1) * 15)); row:SetWidth(530); row:SetHeight(15)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 3, 0); row.name:SetWidth(294); row.name:SetJustifyH("LEFT")
        row.id = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.id:SetPoint("TOPLEFT", row, "TOPLEFT", 307, 0); row.id:SetWidth(56); row.id:SetJustifyH("RIGHT")
        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.price:SetPoint("TOPLEFT", row, "TOPLEFT", 373, 0); row.price:SetWidth(154); row.price:SetJustifyH("RIGHT")
        self.rows[i] = row
    end
    local slider = CreateFrame("Slider", nil, tableFrame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPRIGHT", tableFrame, "TOPRIGHT", 10, -20); slider:SetPoint("BOTTOMRIGHT", tableFrame, "BOTTOMRIGHT", 10, 0)
    slider:SetMinMaxValues(0, 0); slider:SetValueStep(1); slider:SetValue(0)
    slider:SetScript("OnValueChanged", function() if not UI.syncing then UI.offset = floor((this:GetValue() or 0) + 0.5); UI:Render() end end)
    self.slider = slider
    rowArea:SetScript("OnMouseWheel", function() UI.offset = max(0, min(UI.maxOffset or 0, UI.offset + (arg1 > 0 and -3 or 3))); UI:Render() end)

    local function applyFilters()
        VA.settings.aux.minCopper = max(0, (tonumber(minInput:GetText()) or 0) * 10000)
        VA.settings.aux.maxCopper = max(0, (tonumber(maxInput:GetText()) or 0) * 10000)
        VA.settings.aux.cachedOnly = cached:GetChecked() and true or false
    end
    local function runNow()
        frame.pendingAt = nil
        applyFilters()
        Search:Run(query:GetText() or "")
    end
    searchButton:SetScript("OnClick", runNow)
    query:SetScript("OnEnterPressed", runNow)
    minInput:SetScript("OnEnterPressed", runNow); maxInput:SetScript("OnEnterPressed", runNow)
    cached:SetScript("OnClick", runNow)
    query:SetScript("OnTextChanged", function()
        if frame.settingQuery then return end
        local text = this:GetText() or ""
        if strlen(text) >= 3 then frame.pendingAt = GetTime() + 0.45 else frame.pendingAt = nil end
    end)
    frame:SetScript("OnUpdate", function()
        if this.pendingAt and GetTime() >= this.pendingAt then runNow() end
    end)
    UISpecialFrames = UISpecialFrames or {}; tinsert(UISpecialFrames, "AuxFindFrame")
end

function UI:Display(rows, query, total)
    self:Create()
    self.lastQuery = query or ""
    if self.query:GetText() ~= self.lastQuery then
        self.frame.settingQuery = true
        self.query:SetText(self.lastQuery)
        self.frame.settingQuery = nil
    end
    self.data = rows or {}; self.offset = 0
    local shown = VA:ArrayLen(self.data)
    self.subtitle:SetText(format("%d%s matches | sort %s %s", shown, total > shown and (" of " .. total) or "", VA.settings.aux.sort, VA.settings.aux.ascending and "ascending" or "descending"))
    self:Render()
end

function UI:ShowMessage(message)
    self:Display({ { name = message, id = "", price = "" } }, "", 1)
    self:Show()
end

function UI:Render()
    local count = VA:ArrayLen(self.data or {})
    self.maxOffset = max(0, count - self.visibleRows); self.offset = min(self.offset or 0, self.maxOffset)
    self.syncing = true; self.slider:SetMinMaxValues(0, self.maxOffset); self.slider:SetValue(self.offset); self.syncing = nil
    if self.maxOffset > 0 then self.slider:Show() else self.slider:Hide() end
    for i = 1, self.visibleRows do
        local row, data = self.rows[i], self.data[self.offset + i]
        if data then row.name:SetText(data.name or ""); row.id:SetText(tostring(data.id or "")); row.price:SetText(data.price or ""); row:Show() else row:Hide() end
    end
end

function UI:Show()
    self:Create(); self.frame:Show(); self.query:SetFocus()
end

VA:On("PLAYER_READY", function()
    local button = CreateFrame("Button", "AuxSearchMinimapButton", Minimap or UIParent)
    button:SetWidth(31); button:SetHeight(31); button:SetFrameStrata("HIGH"); button:SetFrameLevel(10)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    VA:ApplyFramePosition("auxButton", button, "TOPRIGHT", -8, -8, Minimap or UIParent); VA:MakeMovable(button, "auxButton")
    local overlay = button:CreateTexture(nil, "OVERLAY"); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetWidth(52); overlay:SetHeight(52); overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    local icon = button:CreateTexture(nil, "ARTWORK"); icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02"); icon:SetTexCoord(0.05, 0.95, 0.05, 0.95); icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnClick", function() UI:Show() end)
    button:SetScript("OnEnter", function() GameTooltip:SetOwner(button, "ANCHOR_LEFT"); GameTooltip:SetText("Aux Search"); GameTooltip:AddLine("Drag to move", 0.9, 0.9, 0.9); GameTooltip:Show() end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.minimapButton = button
end)
