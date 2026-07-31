-- !MoneyFrameFix -----------------------------------------------------------------
-- Originally a diagnostic for nil money reaching MoneyFrame_Update; the culprit
-- was found (2026-07-31): Puppeteer's HealComm-1.0 creates healcommTip from
-- GameTooltipTemplate, whose child money frame runs MoneyFrame_SetType("STATIC")
-- while this.staticMoney is still nil, so the STATIC UpdateFunc feeds nil into
-- MoneyFrame_Update (line 185 arithmetic error).
--
-- This file now carries the permanent root fix (STATIC UpdateFunc guard) and
-- keeps the nil-money capture hooks as a safety net. /moneyfix (or legacy
-- /moneyprobe) prints any captures; MoneyProbeDB persists them across sessions.
--------------------------------------------------------------------------------

local log = {}
MoneyFrameFixLog = log
MoneyProbeLog = log

-- Root fix: all static money frames share this table, so one guard covers every
-- addon that instantiates a money-frame template (HealComm, EQL3, Bagnon, ...).
if MoneyTypeInfo and MoneyTypeInfo["STATIC"] then
    local originalStatic = MoneyTypeInfo["STATIC"].UpdateFunc
    MoneyTypeInfo["STATIC"].UpdateFunc = function()
        local money
        if originalStatic then money = originalStatic() end
        return money or 0
    end
end

-- Safety net: record and coerce nil values from any remaining money-frame path.
local function asText(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function safeName(frame)
    if frame and frame.GetName then
        local ok, name = pcall(frame.GetName, frame)
        if ok and name then return name end
    end
    return "nil"
end

local function record(tag, frameName)
    local entry = {
        tag = tag,
        frameName = asText(frameName),
        thisName = safeName(this),
    }
    if this then
        entry.moneyType = asText(this.moneyType)
        entry.staticMoney = asText(this.staticMoney)
        if this.info then entry.hasUpdateFunc = asText(this.info.UpdateFunc ~= nil)
        else entry.info = "nil" end
    else
        entry.thisName = "no this"
    end
    if debugstack then entry.stack = debugstack(3, 12, 0) end
    table.insert(log, entry)
end

local originalMoneyFrameUpdate = MoneyFrame_Update
function MoneyFrame_Update(frameName, money)
    if money == nil then
        record("MoneyFrame_Update received nil money", frameName)
        money = 0
    end
    return originalMoneyFrameUpdate(frameName, money)
end

local originalMoneyFrameUpdateMoney = MoneyFrame_UpdateMoney
function MoneyFrame_UpdateMoney()
    if this and this.info and this.info.UpdateFunc then
        local ok, money = pcall(this.info.UpdateFunc)
        if not ok then
            record("info.UpdateFunc errored: " .. asText(money), safeName(this))
            return
        end
        if money == nil then record("info.UpdateFunc returned nil", safeName(this)) end
        return originalMoneyFrameUpdateMoney()
    end
    record("MoneyFrame_UpdateMoney with no this.info", safeName(this))
    if this and this.GetName then MoneyFrame_Update(this:GetName(), 0) end
end

local function say(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00MoneyFrameFix:|r " .. message)
    end
end

local function printEntry(index, entry)
    say(string.format(
        "[%d] %s | frameName=%s | this=%s | moneyType=%s | staticMoney=%s | hasUpdateFunc=%s",
        index, asText(entry.tag), asText(entry.frameName), asText(entry.thisName),
        asText(entry.moneyType), asText(entry.staticMoney), asText(entry.hasUpdateFunc)))
    if entry.stack then say("stack: " .. entry.stack) end
end

SLASH_MONEYFRAMEFIX1 = "/moneyfix"
SLASH_MONEYFRAMEFIX2 = "/moneyprobe"
SlashCmdList["MONEYFRAMEFIX"] = function()
    local count = table.getn(log)
    say(count .. " nil-money capture(s) this session.")
    for i = 1, count do printEntry(i, log[i]) end
end

local reporter = CreateFrame("Frame")
reporter:RegisterEvent("VARIABLES_LOADED")
reporter:RegisterEvent("PLAYER_ENTERING_WORLD")
reporter:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        -- Retain the original saved-variable name for existing installations.
        MoneyProbeDB = log
    elseif event == "PLAYER_ENTERING_WORLD" then
        local count = table.getn(log)
        if count > 0 then
            say(count .. " nil-money call(s) captured during load. Type /moneyfix for details.")
        end
    end
end)
