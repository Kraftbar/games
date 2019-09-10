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
AutoBeggar.saveBtn = CreateFrame("Button", nil, AutoBeggar, "GameMenuButtonTemplate");
AutoBeggar.saveBtn:SetPoint("CENTER", AutoBeggar, "TOP", 0, -70);
AutoBeggar.saveBtn:SetSize(100, 20);
AutoBeggar.saveBtn:SetText("Save");
AutoBeggar.saveBtn:SetNormalFontObject("GameFontNormal");
AutoBeggar.saveBtn:SetHighlightFontObject("GameFontHighlight");

--AutoBeggar.saveBtn:SetPushedFontObject(""); -- removed from API
--AutoBeggar.saveBtn:SetDisabledFontObject(" "); -- requires a name (cannot be empty!)

-- Reset Button:
AutoBeggar.resetBtn = CreateFrame("Button", nil, AutoBeggar, "GameMenuButtonTemplate");
AutoBeggar.resetBtn:SetPoint("TOP", AutoBeggar.saveBtn, "BOTTOM", 0, -10);
AutoBeggar.resetBtn:SetSize(140, 40);
AutoBeggar.resetBtn:SetText("Reset");
AutoBeggar.resetBtn:SetNormalFontObject("GameFontNormal");
AutoBeggar.resetBtn:SetHighlightFontObject("GameFontHighlight");

-- Load Button:
AutoBeggar.loadBtn = CreateFrame("Button", nil, AutoBeggar, "GameMenuButtonTemplate");
AutoBeggar.loadBtn:SetPoint("TOP", AutoBeggar.resetBtn, "BOTTOM", 0, -10);
AutoBeggar.loadBtn:SetSize(140, 40);
AutoBeggar.loadBtn:SetText("Load");
AutoBeggar.loadBtn:SetNormalFontObject("GameFontNormalLarge");
AutoBeggar.loadBtn:SetHighlightFontObject("GameFontHighlightLarge");

---------------------------------
-- Sliders
---------------------------------
-- Slider 1:
AutoBeggar.slider1 = CreateFrame("SLIDER", nil, AutoBeggar, "OptionsSliderTemplate");
AutoBeggar.slider1:SetPoint("TOP", AutoBeggar.loadBtn, "BOTTOM", 0, -20);
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
