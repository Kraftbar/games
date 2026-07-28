-- Aux offline DB search helper (Vanilla 1.12, Lua 5.0)
-- Early stub so /auxfind works even if later code fails
AuxFind_Run = AuxFind_Run or function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r initializing... (if this persists after /reload, there was a load error)")
end
if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r init") end

local AUXFIND_DEBUG = false
local function dbg(msg)
  if AUXFIND_DEBUG then DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind DEBUG]|r " .. tostring(msg)) end
end

local function coins(c)
  c = tonumber(c or 0) or 0
  local g = floor(c / 10000)
  local s = floor(mod(c, 10000) / 100)
  local cc = floor(mod(c, 100))
  if g > 0 then return format("%dg %ds %dc", g, s, cc) end
  if s > 0 then return format("%ds %dc", s, cc) end
  return format("%dc", cc)
end

local function arrlen(t)
  if getn then return getn(t) end
  if table and table.getn then return table.getn(t) end
  local n = 0; for _ in pairs(t) do n = n + 1 end; return n
end

local function AuxFind_DisplayLines(lines)
  local scroll = (getglobal and getglobal("CombatInfoWindowScroll")) or CombatInfoWindowScroll
  if not scroll or not scroll.AddMessage then
    scroll = (getglobal and getglobal("SecondsUntilDeathWindowScroll")) or SecondsUntilDeathWindowScroll
  end
  if scroll and scroll.AddMessage then
    if scroll.Clear then scroll:Clear() end
    for i = 1, arrlen(lines) do
      scroll:AddMessage(lines[i])
    end
    if scroll.ScrollToBottom then scroll:ScrollToBottom() end
  else
    for i = 1, arrlen(lines) do
      DEFAULT_CHAT_FRAME:AddMessage(lines[i])
    end
  end
end

local function AuxFind_RenderRows(self)
  local f = self
  if not f or not f.rows then return end
  local total = arrlen(f.resultRows or {})
  local maxOffset = max(0, total - (f.visibleRows or 1))
  if (f.resultOffset or 0) > maxOffset then f.resultOffset = maxOffset end
  if (f.resultOffset or 0) < 0 then f.resultOffset = 0 end

  f._syncSlider = true
  if f.resultSlider then
    f.resultSlider:SetMinMaxValues(0, maxOffset)
    f.resultSlider:SetValue(f.resultOffset or 0)
    if maxOffset > 0 then f.resultSlider:Show() else f.resultSlider:Hide() end
  end
  f._syncSlider = nil

  for i = 1, (f.visibleRows or 0) do
    local row = f.rows[i]
    local data = f.resultRows[(f.resultOffset or 0) + i]
    if row and data then
      if data.isMessage then
        row.cName:SetText(data.name or "")
        row.cId:SetText("")
        row.cPrice:SetText("")
      else
        row.cName:SetText(data.name or "")
        row.cId:SetText(data.id or "")
        row.cPrice:SetText(data.price or "")
      end
      row:Show()
    elseif row then
      row:Hide()
    end
  end
end

local function AuxFind_DisplayRows(rows, subtitle)
  local f = (getglobal and getglobal("AuxFindFrame")) or AuxFindFrame
  if not f then
    AuxFind_Open()
    f = (getglobal and getglobal("AuxFindFrame")) or AuxFindFrame
  end
  if not f or not f.rows then
    local lines = {}
    if subtitle and subtitle ~= "" then lines[1] = subtitle end
    for i = 1, arrlen(rows or {}) do
      local r = rows[i]
      lines[arrlen(lines) + 1] = format("- %s (%s): %s", tostring(r.name or ""), tostring(r.id or ""), tostring(r.price or ""))
    end
    if arrlen(lines) == 0 then lines[1] = "|cffffff00[AuxFind]|r No results." end
    AuxFind_DisplayLines(lines)
    return
  end
  f.resultRows = rows or {}
  f.resultOffset = 0
  if f.resultTitle then f.resultTitle:SetText(subtitle or "") end
  if f.RenderRows then f:RenderRows() end
end

local function AuxFind_DisplayMessage(msg)
  AuxFind_DisplayRows({{ isMessage = true, name = msg or "" }}, "")
end

local function faction_key()
  local realm = GetCVar("realmName") or "?"
  local faction = UnitFactionGroup("player") or "Alliance"
  return realm .. "|" .. faction
end

local function parse_post_value(v)
  -- format observed: "duration#min#buyout#?"; prices are in copper (may be decimals)
  if type(v) ~= "string" then return nil, nil end
  local _, _, _dur, minp, buy = string.find(v, "^(%d+)%#([%d%.]+)%#([%d%.]+)")
  if minp then minp = tonumber(minp) end
  if buy then buy = tonumber(buy) end
  return minp, buy
end

local function median_from_history(s)
  if type(s) ~= "string" then return nil end
  local vals, n = {}, 0
  for price in string.gfind(s, "([%d%.]+)@") do
    local v = tonumber(price)
    if v and v > 0 then n = n + 1; vals[n] = v end
  end
  if n == 0 then return nil end
  table.sort(vals)
  if mod(n, 2) == 1 then
    return vals[(n + 1) / 2]
  else
    return (vals[n / 2] + vals[n / 2 + 1]) / 2
  end
end

local function price_for_id(id)
  local key = faction_key()
  local fdb = aux.faction and aux.faction[key]
  local post = fdb and fdb.post or nil
  local hist = fdb and fdb.history or nil
  -- try exact suffix 0 first
  if post then
    local p = post[tostring(id) .. ":0"]
    if p then
      local minp, buy = parse_post_value(p)
      if minp and buy then return coins(minp) .. " | " .. coins(buy) end
    end
    -- otherwise any suffix
    for k, v in pairs(post) do
      if strfind(k, "^" .. tostring(id) .. ":") then
        local minp, buy = parse_post_value(v)
        if minp and buy then return coins(minp) .. " | " .. coins(buy) end
      end
    end
  end
  if hist then
    local best = nil
    if hist[tostring(id) .. ":0"] then best = hist[tostring(id) .. ":0"] end
    if not best then
      for k, v in pairs(hist) do
        if strfind(k, "^" .. tostring(id) .. ":") then best = v break end
      end
    end
    local med = median_from_history(best)
    if med and med > 0 then return "median ~ " .. coins(med) end
  end
  return "(no cached price)"
end

local function has_all_tokens(name, query)
  -- Normalize name to word tokens: replace non-alnum with spaces and pad
  name = strlower(name or "")
  name = gsub(name, "[^%w]+", " ")
  name = gsub(name, "%s+", " ")
  name = " " .. name .. " "
  for tok in string.gfind(strlower(query or ""), "(%w+)") do
    local needle = " " .. tok .. " "
    if not strfind(name, needle, 1, 1) then return false end
  end
  return true
end

-- Lightweight UI
function AuxFind_Open()
  local f = (getglobal and getglobal("AuxFindFrame")) or AuxFindFrame
  if not f then
    local fw, fh = 520, 320
    f = CreateFrame("Frame", "AuxFindFrame", UIParent)
    f:SetWidth(fw); f:SetHeight(fh)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10); title:SetText("Aux Search")
    local eb = CreateFrame("EditBox", "AuxFindEditBox", f, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
    eb:SetWidth(fw - 122); eb:SetHeight(20)
    eb:SetText("")
    local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    go:SetWidth(86); go:SetHeight(20)
    go:SetText("Search")
    go:SetPoint("LEFT", eb, "RIGHT", 6, 0)

    local resultTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resultTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -56)
    resultTitle:SetText("")
    f.resultTitle = resultTitle

    local tableWrap = CreateFrame("Frame", nil, f)
    tableWrap:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -72)
    tableWrap:SetWidth(fw - 20)
    tableWrap:SetHeight(fh - 82)
    f.tableWrap = tableWrap

    local rowAreaWidth = fw - 38
    local rowAreaHeight = fh - 106
    local rowHeight = 16
    local visibleRows = floor(rowAreaHeight / rowHeight)
    local colName, colId = 292, 72
    local colPrice = rowAreaWidth - (colName + colId + 8)
    if colPrice < 100 then colPrice = 100 end
    local xName = 0
    local xId = xName + colName + 4
    local xPrice = xId + colId + 4

    local function makeHeaderCell(xPos, width, text, justify)
      local bg = tableWrap:CreateTexture(nil, "BACKGROUND")
      bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
      bg:SetVertexColor(1, 1, 1, 0.20)
      bg:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", xPos, 0)
      bg:SetWidth(width)
      bg:SetHeight(16)
      local fs = tableWrap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", xPos + 3, -2)
      fs:SetWidth(width - 6)
      fs:SetJustifyH(justify or "LEFT")
      fs:SetText(text or "")
      return bg, fs
    end
    makeHeaderCell(xName, colName, "Item", "LEFT")
    makeHeaderCell(xId, colId, "ID", "RIGHT")
    makeHeaderCell(xPrice, colPrice, "Price", "RIGHT")

    local rowArea = CreateFrame("Frame", nil, tableWrap)
    rowArea:SetPoint("TOPLEFT", tableWrap, "TOPLEFT", 0, -20)
    rowArea:SetWidth(rowAreaWidth)
    rowArea:SetHeight(rowAreaHeight)
    rowArea:EnableMouseWheel(true)
    f.rowArea = rowArea

    local slider = CreateFrame("Slider", "AuxFindResultsSlider", tableWrap, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPRIGHT", tableWrap, "TOPRIGHT", 0, -20)
    slider:SetPoint("BOTTOMRIGHT", tableWrap, "BOTTOMRIGHT", 0, 0)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetValue(0)
    f.resultSlider = slider

    f.rows = {}
    f.visibleRows = visibleRows
    f.resultOffset = 0
    f.resultRows = {}
    f.RenderRows = AuxFind_RenderRows

    for i = 1, visibleRows do
      local r = CreateFrame("Frame", nil, rowArea)
      r:SetWidth(rowAreaWidth)
      r:SetHeight(rowHeight)
      r:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, -((i - 1) * rowHeight))

      local shade = (mod(i, 2) == 0) and 0.14 or 0.08
      local function makeCell(xPos, width, justify)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(1, 1, 1, shade)
        bg:SetPoint("TOPLEFT", r, "TOPLEFT", xPos, 0)
        bg:SetWidth(width)
        bg:SetHeight(rowHeight)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", r, "TOPLEFT", xPos + 3, 0)
        fs:SetWidth(width - 6)
        fs:SetJustifyH(justify or "LEFT")
        return bg, fs
      end

      local bgName, cName = makeCell(xName, colName, "LEFT")
      local bgId, cId = makeCell(xId, colId, "RIGHT")
      local bgPrice, cPrice = makeCell(xPrice, colPrice, "RIGHT")
      r.bgName = bgName
      r.bgId = bgId
      r.bgPrice = bgPrice
      r.cName = cName
      r.cId = cId
      r.cPrice = cPrice
      f.rows[i] = r
    end

    local function stepScroll(delta)
      local step = 3
      if IsShiftKeyDown and IsShiftKeyDown() then
        step = 10
      elseif IsControlKeyDown and IsControlKeyDown() then
        step = 1
      end
      local nextOffset = f.resultOffset or 0
      if delta > 0 then nextOffset = nextOffset - step else nextOffset = nextOffset + step end
      if nextOffset < 0 then nextOffset = 0 end
      f.resultOffset = nextOffset
      if f.RenderRows then f:RenderRows() end
    end
    rowArea:SetScript("OnMouseWheel", function() stepScroll(arg1) end)
    slider:SetScript("OnValueChanged", function()
      if f._syncSlider then return end
      local v = floor((this:GetValue() or 0) + 0.5)
      if v < 0 then v = 0 end
      f.resultOffset = v
      if f.RenderRows then f:RenderRows() end
    end)

    go:SetScript("OnClick", function()
      local q = eb:GetText() or ""
      AuxFind_Run(q)
    end)
    -- Enter key triggers immediate search
    eb:SetScript("OnEnterPressed", function()
      local q = this:GetText() or ""
      AuxFind_Run(q)
    end)
    eb:SetScript("OnTextChanged", function()
      local txt = this:GetText() or ""
      if strlen(txt) >= 3 then
        if (this._last_q or "") ~= txt and (GetTime() - (this._last_t or 0)) > 0.5 then
          this._last_q = txt; this._last_t = GetTime(); AuxFind_Run(txt)
        end
      end
    end)
    -- Allow closing with ESC
    UISpecialFrames = UISpecialFrames or {}
    local found = false
    for i = 1, (getn and getn(UISpecialFrames) or 0) do if UISpecialFrames[i] == "AuxFindFrame" then found = true break end end
    if not found then tinsert(UISpecialFrames, "AuxFindFrame") end
  end
  f:Show()
  if f.RenderRows then f:RenderRows() end
  local eb = (getglobal and getglobal("AuxFindEditBox")) or AuxFindEditBox
  if eb and eb.SetFocus then eb:SetFocus() end
end

function AuxFind_Run(query)
  query = tostring(query or "")
  query = string.gsub(query, "^%s+", "")
  query = string.gsub(query, "%s+$", "")
  local displayQuery = query
  if query == "" then query = "*" end
  -- Ensure our search window is open and reflect the query in the box
  AuxFind_Open()
  local eb = (getglobal and getglobal("AuxFindEditBox")) or AuxFindEditBox
  if eb and displayQuery ~= "" and eb.SetText then eb:SetText(displayQuery) end
  dbg("search: '" .. query .. "'")
  if not aux or not aux.account or not aux.account.item_ids then
    AuxFind_DisplayMessage("|cffffff00[AuxFind]|r Aux DB not available. Ensure aux-addon is enabled.")
    return
  end

  local is_id = nil
  do local _, _, d = string.find(query, "^(%d+)$"); if d then is_id = tonumber(d) end end
  local found, n = {}, 0
  for name, id in pairs(aux.account.item_ids) do
    if (is_id and tonumber(id) == is_id) or (not is_id and has_all_tokens(name, query)) then
      n = n + 1
      found[n] = { name = name, id = id }
      if n >= 50 then break end
    end
  end
  if n == 0 then
    AuxFind_DisplayMessage("|cffffff00[AuxFind]|r No matches for: " .. query)
    return
  end

  table.sort(found, function(a, b) return a.name < b.name end)
  local rows = {}
  local shown = 0
  for i = 1, n do
    local it = found[i]
    local priceText = price_for_id(it.id)
    shown = shown + 1
    rows[shown] = { name = it.name or "?", id = tostring(it.id or "?"), price = priceText or "(no cached price)" }
  end
  if shown == 0 then
    AuxFind_DisplayMessage("|cffffff00[AuxFind]|r No matches for: " .. query)
  else
    AuxFind_DisplayRows(rows, "|cffffff00[AuxFind]|r Results for '" .. query .. "' (" .. tostring(shown) .. ")")
  end
end

-- Static popup for quick prompts
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["VANILLA_AUX_FIND"] = {
  text = "Search Aux DB:",
  button1 = "Search",
  button2 = CANCEL,
  hasEditBox = 1,
  maxLetters = 64,
  OnAccept = function()
    local editBox = getglobal(this:GetName() .. "EditBox")
    local txt = editBox and editBox:GetText() or ""
    AuxFind_Run(txt)
  end,
  OnShow = function()
    local editBox = getglobal(this:GetName() .. "EditBox")
    if editBox then
      editBox:SetFocus()
      editBox._auxfind_lastq = ""
      editBox._auxfind_lastt = 0
      editBox:SetScript("OnTextChanged", function()
        local txt = this:GetText() or ""
        if strlen(txt) >= 3 then
          local now = GetTime()
          if txt ~= (this._auxfind_lastq or "") and (now - (this._auxfind_lastt or 0)) > 0.5 then
            this._auxfind_lastq = txt
            this._auxfind_lastt = now
            AuxFind_Run(txt)
          end
        end
      end)
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- Minimap button (created after PLAYER_LOGIN to ensure Minimap exists)
local positions = {
  { point = "TOPRIGHT", dx = -8, dy = -8 },
  { point = "TOPLEFT",  dx =  8, dy = -8 },
  { point = "BOTTOMLEFT", dx =  8, dy =  8 },
  { point = "BOTTOMRIGHT", dx = -8, dy =  8 },
}
local posIndex = 1
local function AuxFind_PositionButton(btn)
  local p = positions[posIndex]
  btn:ClearAllPoints()
  local anchor = Minimap or UIParent
  btn:SetPoint(p.point, anchor, p.point, p.dx, p.dy)
end

local function AuxFind_CreateButton()
  if AuxSearchMinimapButton then return AuxSearchMinimapButton end
  dbg("creating minimap button; Minimap=" .. tostring(Minimap))
  local parent = Minimap or UIParent
  local btn = CreateFrame("Button", "AuxSearchMinimapButton", parent)
  btn:SetWidth(31); btn:SetHeight(31)
  btn:SetFrameStrata("HIGH"); btn:SetFrameLevel(10)
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  AuxFind_PositionButton(btn)
  btn:SetMovable(true)
  btn:EnableMouse(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function() btn:StartMoving() end)
  btn:SetScript("OnDragStop", function() btn:StopMovingOrSizing() end)
  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetWidth(52); overlay:SetHeight(52)
  overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetWidth(20); icon:SetHeight(20)
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  btn.icon = icon
  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:SetText("Aux Search", 1, 1, 1)
    GameTooltip:AddLine("Left-click: Search Aux DB", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Drag: Free move", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Right-click: Snap to corner", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("/auxfind <text>", 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      posIndex = posIndex + 1; if posIndex > 4 then posIndex = 1 end
      AuxFind_PositionButton(btn)
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Button moved. Use right-click again to cycle.")
    else
      AuxFind_Open()
    end
  end)
  btn:Show()
  return btn
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  dbg("PLAYER_LOGIN; creating button")
  AuxFind_CreateButton()
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r loaded - use /auxfind <text>")
  -- Re-register slash on login to be extra safe
  SLASH_AUXFIND1 = "/auxfind"
  SLASH_AUXFIND2 = "/afind"
  SlashCmdList["AUXFIND"] = function(msg)
    msg = msg or ""
    msg = string.gsub(msg, "^%s+", "")
    msg = string.gsub(msg, "%s+$", "")
    if msg == "" then
      AuxFind_Open()
    elseif msg == "icon" or msg == "button" then
      local btn = AuxFind_CreateButton()
      if btn then
        posIndex = posIndex + 1; if posIndex > 4 then posIndex = 1 end
        AuxFind_PositionButton(btn)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Button cycled. Right-click to move again.")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Could not create button.")
      end
    elseif msg == "center" then
      local btn = AuxFind_CreateButton()
      if btn then btn:ClearAllPoints(); btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0); btn:Show() end
    elseif msg == "debug on" then
      AUXFIND_DEBUG = true
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Debug enabled")
    elseif msg == "debug off" then
      AUXFIND_DEBUG = false
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Debug disabled")
    else
      AuxFind_Run(msg)
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r slash ready: /auxfind or /afind")
end)

-- Provide a dispatcher for external callers (window.lua fallback)
function AuxFind_HandleSlash(msg)
  if not msg or msg == "" then AuxFind_Open(); return end
  if msg == "icon" or msg == "button" then
    local btn = AuxFind_CreateButton(); if btn then posIndex = posIndex + 1; if posIndex > 4 then posIndex = 1 end; AuxFind_PositionButton(btn) end; return
  end
  if msg == "center" then local btn = AuxFind_CreateButton(); if btn then btn:ClearAllPoints(); btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0); btn:Show() end; return end
  if msg == "debug on" then AUXFIND_DEBUG = true; return end
  if msg == "debug off" then AUXFIND_DEBUG = false; return end
  AuxFind_Run(msg)
end

-- Slash command
SLASH_AUXFIND1 = "/auxfind"
SlashCmdList["AUXFIND"] = function(msg)
  msg = msg or ""
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  if msg == "" then
    AuxFind_Open()
  elseif msg == "icon" or msg == "button" then
    local btn = AuxFind_CreateButton()
    if btn then
      posIndex = posIndex + 1; if posIndex > 4 then posIndex = 1 end
      AuxFind_PositionButton(btn)
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Button cycled. Right-click to move again.")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Could not create button.")
    end
  elseif msg == "center" then
    local btn = AuxFind_CreateButton()
    if btn then
      btn:ClearAllPoints()
      btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      btn:Show()
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Button moved to screen center.")
    end
  elseif msg == "debug on" then
    AUXFIND_DEBUG = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Debug enabled")
  elseif msg == "debug off" then
    AUXFIND_DEBUG = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Debug disabled")
  else
    AuxFind_Run(msg)
  end
end
