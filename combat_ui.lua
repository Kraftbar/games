-- Combat windows and history UI. Remove this file from the TOC for headless tracking.

local VA = VanillaAddon
local UI = {}
VA.CombatUI = UI
VA:RegisterModule("combat-ui", UI)

local function createMessageWindow(name, positionKey, width, height, xOffset)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:SetFrameStrata("HIGH")
    VA:ApplyFramePosition(positionKey, frame, "CENTER", xOffset, 0)
    VA:MakeMovable(frame, positionKey)

    local scroll = CreateFrame("ScrollingMessageFrame", name .. "Scroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    scroll:SetWidth(width - 20)
    scroll:SetHeight(height - 20)
    scroll:SetFontObject(GameFontNormal)
    scroll:SetJustifyH("LEFT")
    scroll:SetMaxLines(1000)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function()
        if arg1 > 0 then scroll:ScrollUp() else scroll:ScrollDown() end
    end)
    frame.scroll = scroll
    return frame
end

function UI:CreateWindows()
    if self.stats then return end
    self.stats = createMessageWindow("CombatStatsWindow", "combatStats", 300, 200, -310)
    self.death = createMessageWindow("SecondsUntilDeathWindow", "combatDeath", 300, 34, 0)
    self.info = createMessageWindow("CombatInfoWindow", "combatInfo", 300, 200, 310)
end

local function addMessage(frame, message)
    if frame and frame.scroll then
        frame.scroll:AddMessage(message)
        frame.scroll:ScrollToBottom()
    end
end

function UI:SetVisible(visible)
    self:CreateWindows()
    VA.settings.combat.visible = visible and true or false
    if visible then
        UI.stats:Show(); UI.death:Show(); UI.info:Show()
    else
        UI.stats:Hide(); UI.death:Hide(); UI.info:Hide()
    end
end

function UI:UpdateDeath(snapshot, attackers)
    local function estimate(value)
        if value and value > 0 then return format("%.1fs", value) end
        return "--"
    end
    addMessage(self.death, format("Target: %s / Me: %s%s",
        estimate(snapshot.timeToTargetDeath),
        estimate(snapshot.timeToPlayerDeath),
        attackers and attackers > 1 and (" [" .. attackers .. " attackers]") or ""))
end

local function updateEstimate(snapshot)
    local _, attackers = VA.Combat:GetRecent()
    UI:UpdateDeath(snapshot, attackers)
end

VA:On("COMBAT_UPDATED", function(payload)
    UI:CreateWindows()
    local snapshot = payload.snapshot
    if payload.source then
        addMessage(UI.info, format("Taken: %d | DTPS: %.1f | %s", payload.amount, snapshot.dtps, payload.source))
    else
        addMessage(UI.info, format("Dealt: %d | DPS: %.1f", payload.amount, snapshot.dps))
    end
    updateEstimate(snapshot)
end)

VA:On("COMBAT_ESTIMATE_UPDATED", function(payload) updateEstimate(payload.snapshot) end)

VA:On("COMBAT_ENDED", function(snapshot)
    UI:CreateWindows()
    addMessage(UI.stats, format("%.1fs | Dealt %d (%.1f DPS) | Taken %d (%.1f DTPS)",
        snapshot.elapsed, snapshot.damageDealt, snapshot.dps, snapshot.damageTaken, snapshot.dtps))
    addMessage(UI.death, "Target: -- / Me: --")
    if UI.historyFrame and UI.historyFrame:IsShown() then UI:RefreshHistory() end
end)

function UI:CreateHistory()
    if self.historyFrame then return end
    local frame = CreateFrame("Frame", "CombatHistoryFrame", UIParent)
    frame:SetWidth(520); frame:SetHeight(300)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0, 0, 0, 0.96)
    VA:ApplyFramePosition("combatHistory", frame, "CENTER", 0, 0)
    VA:MakeMovable(frame, "combatHistory")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("Combat History")
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -38)
    header:SetText("When                 Target                    Time       DPS      DTPS")

    local scroll = CreateFrame("ScrollingMessageFrame", "CombatHistoryScroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -58)
    scroll:SetWidth(492); scroll:SetHeight(220)
    scroll:SetFontObject(GameFontHighlightSmall)
    scroll:SetJustifyH("LEFT")
    scroll:SetMaxLines(100)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function()
        if arg1 > 0 then scroll:ScrollUp() else scroll:ScrollDown() end
    end)
    frame.scroll = scroll
    self.historyFrame = frame
    UISpecialFrames = UISpecialFrames or {}
    tinsert(UISpecialFrames, "CombatHistoryFrame")
end

function UI:RefreshHistory()
    self:CreateHistory()
    local scroll = self.historyFrame.scroll
    if scroll.Clear then scroll:Clear() end
    local rows = VA.db.combatHistory
    local count = VA:ArrayLen(rows)
    if count == 0 then scroll:AddMessage("No completed encounters yet.") end
    for i = count, 1, -1 do
        local row = rows[i]
        scroll:AddMessage(format("%-20s %-24s %6.1fs %8.1f %8.1f",
            date("%Y-%m-%d %H:%M", row.endedAt or time()),
            VA:TrimText(row.target or "Unknown", 24), row.elapsed or 0, row.dps or 0, row.dtps or 0))
    end
end

function UI:ShowHistory()
    self:RefreshHistory()
    self.historyFrame:Show()
end

VA:On("PLAYER_READY", function()
    UI:CreateWindows()
    UI:SetVisible(VA.settings.combat.visible)
    addMessage(UI.info, "CombatStats v" .. VA.version .. " loaded. /combatstats")
end)
