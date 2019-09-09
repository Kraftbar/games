AutoBiographer_DebugWindow = nil
AutoBiographer_EventWindow = nil
AutoBiographer_MainWindow = nil

local Controller = AutoBiographer_Controller

function Toggle_DebugWindow()
  if (not AutoBiographer_DebugWindow) then
  
    local debugLogs = Controller:GetLogs()
    
    --parent frame 
    local frame = CreateFrame("Frame", "AutoBiographerDebug", AutoBiographer_MainWindow, "BasicFrameTemplateWithInset") 
    frame:SetSize(750, 650) 
    frame:SetPoint("CENTER") 
    
    frame:SetScript("OnHide", 
      function(self)
        AutoBiographer_DebugWindow = nil 
      end
    )

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0);
    frame.title:SetText("AutoBiographer Debug Window")
    
    --scrollframe 
    local scrollframe = CreateFrame("ScrollFrame", nil, frame) 
    scrollframe:SetPoint("TOPLEFT", 10, -25) 
    scrollframe:SetPoint("BOTTOMRIGHT", -10, 10) 
    scrollframe:SetBackdrop( { 
      bgFile = "Interface/FrameGeneral/UI-Background-Marble", 
      edgeFile = nil, tile = false, tileSize = 0, edgeSize = 0, 
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    });

    --scrollbar 
    local scrollbar = CreateFrame("Slider", nil, scrollframe, "UIPanelScrollBarTemplate") 
    scrollbar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -16) 
    scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 16)
    scrollbar:SetMinMaxValues(1, (#debugLogs * 20) + 20) 
    scrollbar:SetValueStep(1) 
    scrollbar.scrollStep = 1 
    scrollbar:SetValue(0) 
    scrollbar:SetWidth(16) 
    scrollbar:SetScript("OnValueChanged",
      function (self, value) 
        self:GetParent():SetVerticalScroll(value) 
      end
    )
    local scrollbg = scrollbar:CreateTexture(nil, "BACKGROUND") 
    scrollbg:SetAllPoints(scrollbar) 
    scrollbg:SetTexture(0, 0, 0, 0.4) 
    frame.scrollbar = scrollbar 

    --content frame 
    local content = CreateFrame("Frame", nil, scrollframe) 
    content:SetSize(1, 1) 
    
    --texts
    local index = 0
    for i = #debugLogs, 1, -1 do
      local font = "GameFontWhite"
      if (debugLogs[i].Level == AutoBiographerEnum.LogLevel.Verbose) then font = "GameFontDisable"
      elseif (debugLogs[i].Level == AutoBiographerEnum.LogLevel.Debug) then font = "GameFontDisable"
      elseif (debugLogs[i].Level == AutoBiographerEnum.LogLevel.Information) then font = "GameFontWhite"
      elseif (debugLogs[i].Level == AutoBiographerEnum.LogLevel.Warning) then font = "GameFontNormal"
      elseif (debugLogs[i].Level == AutoBiographerEnum.LogLevel.Error) then font = "GameFontRed"
      elseif (debugLogs[i].Level == AutoBiographerEnum.LogLevel.Fatal) then font = "GameFontRed"
      end
      
      local text = content:CreateFontString(nil, "OVERLAY", font)
      text:SetPoint("TOPLEFT", 5, -15 * index) 
      text:SetText(debugLogs[i].Text)
      index = index + 1
    end
    
    scrollframe.content = content
    scrollframe:SetScrollChild(content)
    
    frame.LogsUpdated = function () return end
    
    AutoBiographer_DebugWindow = frame
  else
    AutoBiographer_DebugWindow:Hide()
    AutoBiographer_DebugWindow = nil
  end
end

