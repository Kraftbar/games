---------------------------------
-- Helpful Dev Code
---------------------------------
SLASH_RELOADUI1 = "/rl"; -- new slash command for reloading UI
SlashCmdList.RELOADUI = ReloadUI;

SLASH_FRAMESTK1 = "/fs"; -- new slash command for showing framestack tool
SlashCmdList.FRAMESTK = function()
	LoadAddOn("Blizzard_DebugTools");
	FrameStackTooltip_Toggle();
end

-- allows using left and right buttons to move through the chat 'edit' box
for i = 1, NUM_CHAT_WINDOWS do
	_G["ChatFrame"..i.."EditBox"]:SetAltArrowKeyMode(false);
end




---------------------------------
-- Project Code Below
---------------------------------      
local AutoBeggar = CreateFrame("Frame", "MUI_BuffFrame", UIParent, "BasicFrameTemplateWithInset");
AutoBeggar:SetSize(260, 360);
AutoBeggar:SetPoint("CENTER"); -- Doesn't need to be ("CENTER", UIParent, "CENTER")

AutoBeggar:SetMovable(true)
AutoBeggar:EnableMouse(true)
AutoBeggar:RegisterForDrag("LeftButton")

AutoBeggar.title = AutoBeggar:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
AutoBeggar.title:SetPoint("LEFT", AutoBeggar.TitleBg, "LEFT", 5, 0);
AutoBeggar.title:SetText("Personal Finance Helper");
--AutoBeggar.title:SetFont("Fonts\\FRIZQT__.ttf", 11, "OUTLINE");




---------------------------------
-- Enables movable 
---------------------------------
local frame = CreateFrame("Frame", "DragFrame2", UIParent)
AutoBeggar:SetMovable(true)
AutoBeggar:EnableMouse(true)
AutoBeggar:RegisterForDrag("LeftButton")
AutoBeggar:SetScript("OnDragStart", AutoBeggar.StartMoving)
AutoBeggar:SetScript("OnDragStop", AutoBeggar.StopMovingOrSizing)




---------------------------------
-- Buttons
---------------------------------
-- Save Button:
AutoBeggar.slapBtn = CreateFrame("Button", nil, AutoBeggar, "GameMenuButtonTemplate");
AutoBeggar.slapBtn:SetPoint("CENTER", AutoBeggar, "TOP", 0, -70);
AutoBeggar.slapBtn:SetSize(100, 20);
AutoBeggar.slapBtn:SetText("Slap");
AutoBeggar.slapBtn:SetNormalFontObject("GameFontNormal");
AutoBeggar.slapBtn:SetHighlightFontObject("GameFontHighlight");

AutoBeggar.slapBtn:SetScript("OnClick", function(self, arg1)
	DoEmote("slap")
end)



-- Earn money Button:
AutoBeggar.earnBtn = CreateFrame("Button", nil, AutoBeggar, "GameMenuButtonTemplate");
AutoBeggar.earnBtn:SetPoint("TOP", AutoBeggar.slapBtn, "BOTTOM", 0, -10);
AutoBeggar.earnBtn:SetSize(100, 20);
AutoBeggar.earnBtn:SetText("Earn money");
AutoBeggar.earnBtn:SetNormalFontObject("GameFontNormal");
AutoBeggar.earnBtn:SetHighlightFontObject("GameFontHighlight");

AutoBeggar.earnBtn:SetScript("OnClick", function(self, arg1)
    print("Hello, i need some money")
end)



-- Leave Button:
AutoBeggar.leaveBtn = CreateFrame("Button", nil, AutoBeggar, "GameMenuButtonTemplate");
AutoBeggar.leaveBtn:SetPoint("TOP", AutoBeggar.earnBtn, "BOTTOM", 0, -10);
AutoBeggar.leaveBtn:SetSize(100, 20);
AutoBeggar.leaveBtn:SetText("I need to go");
AutoBeggar.leaveBtn:SetNormalFontObject("GameFontNormal");
AutoBeggar.leaveBtn:SetHighlightFontObject("GameFontHighlight");



------ HS
hsBtn = CreateFrame("Button", "DevilskittenUseItemButton", UIParent, "ActionButtonTemplate, InsecureActionButtonTemplate")
local type = "item"
local id = 6948
local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
hsBtn:SetAttribute("type", "item")
hsBtn:SetAttribute("*item1", name) 
hsBtn:SetAttribute("itemid", id)
hsBtn:SetText(name)
hsBtn.icon:SetTexture(icon)
hsBtn:SetAttribute("checkselfcast","1")
hsBtn:SetAttribute("checkfocuscast","1")
hsBtn:SetAttribute("enabled", true)
hsBtn:SetPoint("TOP", 0, -150)
hsBtn:SetSize(32, 32)
hsBtn:Hide();
-- messes up the casting
    -- hsBtn:SetScript("OnClick", function(self, arg1)
    --     hsBtn:Hide();
    -- end)
----- HS


AutoBeggar.leaveBtn:SetScript("OnClick", function(self, arg1)
    SendChatMessage(" I have had enough of you peasant" ,"SAY" ,"Common" );
    hsBtn:Show();
end)

--
--

  if(event == "CHAT_MSG_SAY") then
      if(strlower(arg1) == strlower("")) then
        arg2, _ = strsplit("-", arg2);
        QuickLayer_HandleRequest(arg2, true);
      end
  else
--
--


---------------------------------
-- Sliders
---------------------------------
-- Slider 1:
AutoBeggar.slider1 = CreateFrame("SLIDER", nil, AutoBeggar, "OptionsSliderTemplate");
AutoBeggar.slider1:SetPoint("TOP", AutoBeggar.leaveBtn, "BOTTOM", 0, -20);
AutoBeggar.slider1:SetMinMaxValues(1, 100);
AutoBeggar.slider1:SetValue(50);
AutoBeggar.slider1:SetValueStep(30);
AutoBeggar.slider1:SetObeyStepOnDrag(true);

-- Slider 2:
AutoBeggar.slider2 = CreateFrame("SLIDER", nil, AutoBeggar, "OptionsSliderTemplate");
AutoBeggar.slider2:SetPoint("TOP", AutoBeggar.slider1, "BOTTOM", 0, -20);
AutoBeggar.slider2:SetMinMaxValues(1, 100);
AutoBeggar.slider2:SetValue(40);
AutoBeggar.slider2:SetValueStep(30);
AutoBeggar.slider2:SetObeyStepOnDrag(true);

---------------------------------
-- Check Buttons
---------------------------------
-- Check Button 1:
AutoBeggar.checkBtn1 = CreateFrame("CheckButton", nil, AutoBeggar, "UICheckButtonTemplate");
AutoBeggar.checkBtn1:SetPoint("TOPLEFT", AutoBeggar.slider1, "BOTTOMLEFT", -10, -40);
AutoBeggar.checkBtn1.text:SetText("My Check Button!");

-- Check Button 2:
AutoBeggar.checkBtn2 = CreateFrame("CheckButton", nil, AutoBeggar, "UICheckButtonTemplate");
AutoBeggar.checkBtn2:SetPoint("TOPLEFT", AutoBeggar.checkBtn1, "BOTTOMLEFT", 0, -10);
AutoBeggar.checkBtn2.text:SetText("Another Check Button!");
AutoBeggar.checkBtn2:SetChecked(true);
