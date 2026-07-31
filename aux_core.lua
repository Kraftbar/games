-- Aux offline-database search engine. No UI dependencies.

local VA = VanillaAddon
local Search = { limit = 50 }
VA.AuxSearch = Search
VA:RegisterModule("aux-core", Search)

local function factionKey()
    return (GetCVar("realmName") or "?") .. "|" .. (UnitFactionGroup("player") or "Alliance")
end

local function parsePost(value)
    if type(value) ~= "string" then return nil, nil end
    local _, _, _, minimum, buyout = strfind(value, "^(%d+)%#([%d%.]+)%#([%d%.]+)")
    return tonumber(minimum), tonumber(buyout)
end

local function historyMedian(value)
    if type(value) ~= "string" then return nil end
    local values = {}
    local count = 0
    for price in string.gfind(value, "([%d%.]+)@") do
        local number = tonumber(price)
        if number and number > 0 then count = count + 1; values[count] = number end
    end
    if count == 0 then return nil end
    table.sort(values)
    if mod(count, 2) == 1 then return values[(count + 1) / 2] end
    return (values[count / 2] + values[count / 2 + 1]) / 2
end

function Search:GetPrice(itemId)
    if not aux or not aux.faction then return "(no cached price)", nil end
    local faction = aux.faction[factionKey()]
    local posts = faction and faction.post
    local history = faction and faction.history
    local prefix = tostring(itemId) .. ":"
    if posts then
        local value = posts[prefix .. "0"]
        if not value then
            for key, candidate in pairs(posts) do if strfind(key, "^" .. prefix) then value = candidate; break end end
        end
        local minimum, buyout = parsePost(value)
        local price = buyout or minimum
        if price and price > 0 then
            return (minimum and VA:FormatCoins(minimum) or "-") .. " | " .. (buyout and VA:FormatCoins(buyout) or "-"), price, "post"
        end
    end
    if history then
        local value = history[prefix .. "0"]
        if not value then
            for key, candidate in pairs(history) do if strfind(key, "^" .. prefix) then value = candidate; break end end
        end
        local median = historyMedian(value)
        if median and median > 0 then return "median ~ " .. VA:FormatCoins(median), median, "history" end
    end
    return "(no cached price)", nil, nil
end

local function matches(name, query)
    if query == "" or query == "*" then return true end
    local normalized = " " .. gsub(gsub(strlower(name or ""), "[^%w]+", " "), "%s+", " ") .. " "
    for token in string.gfind(strlower(query), "(%w+)") do
        if not strfind(normalized, " " .. token .. " ", 1, 1) then return false end
    end
    return true
end

function Search:Run(query)
    query = gsub(gsub(tostring(query or ""), "^%s+", ""), "%s+$", "")
    if not aux or not aux.account or not aux.account.item_ids then
        if VA.AuxUI then VA.AuxUI:ShowMessage("Aux DB is unavailable. Enable aux-addon first.") end
        VA:Diag("aux", "Database unavailable")
        return {}, 0
    end
    local settings = VA.settings.aux
    local numericId = tonumber(query)
    local results = {}
    local count = 0
    for name, itemId in pairs(aux.account.item_ids) do
        if (numericId and tonumber(itemId) == numericId) or (not numericId and matches(name, query)) then
            local priceText, priceValue, priceSource = self:GetPrice(itemId)
            local inMinimum = (settings.minCopper or 0) <= 0 or (priceValue and priceValue >= settings.minCopper)
            local inMaximum = (settings.maxCopper or 0) <= 0 or (priceValue and priceValue <= settings.maxCopper)
            local cached = priceValue ~= nil
            if inMinimum and inMaximum and (not settings.cachedOnly or cached) then
                count = count + 1
                results[count] = { name = name, id = tonumber(itemId) or 0, price = priceText, priceValue = priceValue, source = priceSource }
            end
        end
    end
    local key = settings.sort or "name"
    local ascending = settings.ascending ~= false
    table.sort(results, function(a, b)
        local left, right
        if key == "price" then
            if a.priceValue == nil and b.priceValue ~= nil then return false end
            if a.priceValue ~= nil and b.priceValue == nil then return true end
            left = a.priceValue or 0; right = b.priceValue or 0
        elseif key == "id" then left = a.id; right = b.id
        else left = strlower(a.name or ""); right = strlower(b.name or "") end
        if left == right then return (a.name or "") < (b.name or "") end
        if ascending then return left < right else return left > right end
    end)
    local total = count
    for i = count, self.limit + 1, -1 do results[i] = nil end
    if VA.AuxUI then VA.AuxUI:Display(results, query, total) end
    VA:Diag("aux", "Search '" .. query .. "': " .. total .. " matches")
    return results, total
end

function Search:SetSort(key)
    if key ~= "name" and key ~= "id" and key ~= "price" then return end
    local settings = VA.settings.aux
    if settings.sort == key then settings.ascending = not settings.ascending
    else settings.sort = key; settings.ascending = true end
end

function AuxFind_Run(query) return Search:Run(query) end
function AuxFind_Open() if VA.AuxUI then VA.AuxUI:Show() else VA:Print("Aux UI module is disabled") end end
function AuxFind_HandleSlash(message)
    message = gsub(gsub(message or "", "^%s+", ""), "%s+$", "")
    if message == "" then AuxFind_Open() else Search:Run(message) end
end

SLASH_AUXFIND1 = "/auxfind"
SLASH_AUXFIND2 = "/afind"
SLASH_VANFIND1 = "/vanfind"
SlashCmdList["AUXFIND"] = AuxFind_HandleSlash
SlashCmdList["VANFIND"] = AuxFind_HandleSlash
