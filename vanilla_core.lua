-- Shared core: saved settings, diagnostics, events, and UI position helpers.
-- Vanilla WoW 1.12 / Lua 5.0.

VanillaAddon = VanillaAddon or {}
local VA = VanillaAddon

VA.version = "2.0.0"
VA.modules = VA.modules or {}
VA.listeners = VA.listeners or {}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

VA.defaults = {
    diagnostics = { enabled = false, maxEntries = 250 },
    combat = { historyLimit = 20, visible = true },
    warnings = { enabled = true, hpPct = 0.35, ttd = 5.0, cooldown = 8.0 },
    ledger = { view = "all", cutRate = 0.05 },
    aux = { sort = "name", ascending = true, cachedOnly = false, minCopper = 0, maxCopper = 0 },
    frames = {},
}

function VA:EnsureDB()
    -- Some 1.12 clients cache the original SavedVariables list and never write
    -- newly-added globals. Keep shared addon state below the ledger database,
    -- whose persistence is already established, and expose the old global as a
    -- compatibility alias for modules and existing installs.
    VanillaLedgerDB = VanillaLedgerDB or {}
    local shared
    if type(VanillaLedgerDB.addon) == "table" then
        shared = VanillaLedgerDB.addon
    elseif type(VanillaAddonDB) == "table" then
        shared = VanillaAddonDB
    else
        shared = {}
    end
    VanillaLedgerDB.addon = shared
    VanillaAddonDB = shared
    VanillaLedgerErrors = VanillaLedgerErrors or {}
    shared.settings = shared.settings or {}
    shared.diagnostics = shared.diagnostics or {}
    shared.combatHistory = shared.combatHistory or {}
    copyDefaults(shared.settings, self.defaults)
    self.db = shared
    self.settings = shared.settings
    return self.db
end

function VA:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[VanillaAddon]|r " .. tostring(message or ""))
    end
end

function VA:ArrayLen(value)
    local count = 0
    -- Lua 5.0's getn/table.getn may trust a stale internal `n` after slots are
    -- cleared directly. All addon arrays are contiguous, so scan the sequence.
    while value and rawget(value, count + 1) ~= nil do count = count + 1 end
    return count
end

function VA:ArrayPush(value, item)
    local index = self:ArrayLen(value) + 1
    value[index] = item
    return index
end

function VA:ArrayRemove(value, index)
    local count = self:ArrayLen(value)
    index = index or count
    if index < 1 or index > count then return nil end
    local removed = value[index]
    for i = index, count - 1 do value[i] = value[i + 1] end
    value[count] = nil
    return removed
end

function VA:Round(value, places)
    local mult = 10 ^ (places or 0)
    return floor((value or 0) * mult + 0.5) / mult
end

function VA:FormatCoins(copper)
    copper = tonumber(copper or 0) or 0
    local sign = ""
    if copper < 0 then sign = "-"; copper = -copper end
    local gold = floor(copper / 10000)
    local silver = floor(mod(copper, 10000) / 100)
    local coin = floor(mod(copper, 100))
    return sign .. format("%dg %ds %dc", gold, silver, coin)
end

function VA:TrimText(value, maxLength)
    local text = tostring(value or "")
    if strlen(text) <= maxLength then return text end
    if maxLength <= 3 then return strsub(text, 1, maxLength) end
    return strsub(text, 1, maxLength - 3) .. "..."
end

function VA:RegisterModule(name, module)
    self.modules[name] = module or true
end

function VA:On(signal, callback)
    self.listeners[signal] = self.listeners[signal] or {}
    self:ArrayPush(self.listeners[signal], callback)
end

function VA:Emit(signal, payload)
    local callbacks = self.listeners[signal] or {}
    for i = 1, self:ArrayLen(callbacks) do
        local ok, err = pcall(callbacks[i], payload)
        if not ok then self:Diag("listener", signal .. ": " .. tostring(err), true) end
    end
end

function VA:Diag(category, message, force)
    self:EnsureDB()
    if not force and not self.settings.diagnostics.enabled then return end
    local rows = self.db.diagnostics
    self:ArrayPush(rows, {
        t = time(),
        category = tostring(category or "general"),
        message = tostring(message or ""),
    })
    local limit = tonumber(self.settings.diagnostics.maxEntries or 250) or 250
    while self:ArrayLen(rows) > limit do self:ArrayRemove(rows, 1) end
end

function VA:SaveFramePosition(key, frame)
    if not frame or not frame.GetPoint then return end
    self:EnsureDB()
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    x = (x or parentX or 0) - (parentX or 0)
    y = (y or parentY or 0) - (parentY or 0)
    self.settings.frames[key] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
    }
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function VA:ApplyFramePosition(key, frame, defaultPoint, defaultX, defaultY, defaultRelative)
    self:EnsureDB()
    local saved = self.settings.frames[key]
    frame:ClearAllPoints()
    if saved then
        frame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or saved.point or "CENTER", saved.x or 0, saved.y or 0)
    else
        frame:SetPoint(defaultPoint or "CENTER", defaultRelative or UIParent, defaultPoint or "CENTER", defaultX or 0, defaultY or 0)
    end
end

function VA:MakeMovable(frame, positionKey)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        VA:SaveFramePosition(positionKey, frame)
    end)
end

VA:EnsureDB()
VA:RegisterModule("core", VA)

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("VARIABLES_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGIN")
coreFrame:SetScript("OnEvent", function()
    VA:EnsureDB()
    if event == "PLAYER_LOGIN" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:EnableMouseWheel(true)
            if not DEFAULT_CHAT_FRAME:GetScript("OnMouseWheel") then
                DEFAULT_CHAT_FRAME:SetScript("OnMouseWheel", function()
                    if arg1 > 0 then DEFAULT_CHAT_FRAME:ScrollUp() else DEFAULT_CHAT_FRAME:ScrollDown() end
                end)
            end
        end
        VA:Emit("PLAYER_READY")
        VA:Diag("core", "Loaded version " .. VA.version)
    end
end)

SLASH_VANILLAADDON1 = "/vanilla"
SlashCmdList["VANILLAADDON"] = function(message)
    VA:EnsureDB()
    message = gsub(message or "", "^%s+", "")
    message = gsub(message, "%s+$", "")
    local _, _, command, argument = strfind(message, "^(%S+)%s*(.*)$")
    command = strlower(command or "status")
    argument = strlower(argument or "")
    if command == "diag" or command == "diagnostics" then
        if argument == "on" then
            VA.settings.diagnostics.enabled = true
            VA:Print("Diagnostics enabled")
        elseif argument == "off" then
            VA.settings.diagnostics.enabled = false
            VA:Print("Diagnostics disabled")
        elseif argument == "clear" then
            VA.db.diagnostics = {}
            VanillaLedgerErrors = {}
            VA:Print("Diagnostics cleared")
        elseif argument == "show" then
            local rows = VA.db.diagnostics
            local count = VA:ArrayLen(rows)
            VA:Print("Last diagnostics (" .. count .. "):")
            for i = max(1, count - 9), count do
                local row = rows[i]
                if row then
                    DEFAULT_CHAT_FRAME:AddMessage(format("%s [%s] %s", date("%H:%M:%S", row.t), row.category, row.message))
                end
            end
        else
            VA:Print("Diagnostics " .. (VA.settings.diagnostics.enabled and "enabled" or "disabled") .. ". Use /vanilla diag on|off|show|clear")
        end
    elseif command == "modules" or command == "status" then
        local names = {}
        local count = 0
        for name in pairs(VA.modules) do count = count + 1; names[count] = name end
        table.sort(names)
        VA:Print("v" .. VA.version .. " modules: " .. table.concat(names, ", "))
    else
        VA:Print("Commands: status | modules | diag on|off|show|clear")
    end
end

-- Retain a bounded cross-addon error log for in-game diagnosis.
do
    local originalHandler = geterrorhandler and geterrorhandler() or nil
    local handling = false
    local function diagnosticHandler(message)
        if not handling then
            handling = true
            VA:EnsureDB()
            local line = format("%s %s", date("%Y-%m-%d %H:%M:%S"), tostring(message))
            VA:ArrayPush(VanillaLedgerErrors, line)
            while VA:ArrayLen(VanillaLedgerErrors) > 200 do VA:ArrayRemove(VanillaLedgerErrors, 1) end
            VA:Diag("lua-error", tostring(message), true)
            handling = false
        end
        if originalHandler then return originalHandler(message) end
    end
    if seterrorhandler then seterrorhandler(diagnosticHandler) end
end
