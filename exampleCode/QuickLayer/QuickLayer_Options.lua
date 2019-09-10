QuickLayer = {
  message = "layer",
  delay = 1800,
  channel = "layer",
  guild = true,
  whisper = true,
  inviteThreshold = 4,
  inviteInRaid = false,
}

function QuickLayer_AddonLoadedOptions()
  QuickLayer_MessageBox:SetText(QuickLayer.channel);
  QuickLayer_ChannelBox:SetText(QuickLayer.message);
  QuickLayer_DelayBox:SetText(QuickLayer.delay);
  QuickLayer_DelayBox:SetCursorPosition(0)
  QuickLayer_ChannelBox:SetCursorPosition(0)
  QuickLayer_MessageBox:SetCursorPosition(0)
  QuickLayer_GuildCheck:SetChecked(QuickLayer.guild);
  QuickLayer_WhisperCheck:SetChecked(QuickLayer.whisper);
  QuickLayer_RaidInvite:SetChecked(QuickLayer.inviteInRaid);
end

function QuickLayer_CreateOptions()
  local options = CreateFrame("Frame", "QuickLayer_Options")
  options.name = "QuickLayer"
  InterfaceOptions_AddCategory(options);
  QuickLayer_Options_CreateLabel(0, 0, "QuickLayer Config");
  QuickLayer_Options_CreateLabel(0, 40, "Invite Message")
  QuickLayer_Options_CreateEditbox(160, 40, false, "QuickLayer_MessageBox")
	QuickLayer_MessageBox:SetScript("OnTextChanged", function()
		if(QuickLayer_MessageBox:IsNumeric()) then
			QuickLayer.message = QuickLayer_MessageBox:GetNumber();
    else
      QuickLayer.message = QuickLayer_MessageBox:GetText();
		end
	end);

  QuickLayer_Options_CreateLabel(0, 80, "Invite Channel")
  QuickLayer_Options_CreateEditbox(160, 80, false, "QuickLayer_ChannelBox")
	QuickLayer_ChannelBox:SetScript("OnTextChanged", function()
		if(QuickLayer_ChannelBox:IsNumeric()) then
			QuickLayer.channel = QuickLayer_ChannelBox:GetNumber();
    else
      QuickLayer.channel = QuickLayer_ChannelBox:GetText();
		end
	end);

  QuickLayer_Options_CreateLabel(0, 120, "Invite Cooldown")
  QuickLayer_Options_CreateEditbox(160, 120, true, "QuickLayer_DelayBox")
	QuickLayer_DelayBox:SetScript("OnTextChanged", function()
		if(QuickLayer_DelayBox:IsNumeric()) then
			QuickLayer.delay = QuickLayer_DelayBox:GetNumber();
    else
      QuickLayer.delay = QuickLayer_DelayBox:GetText();
		end
	end);

  QuickLayer_Options_CreateCheckbutton(-5, 160, "QuickLayer_GuildCheck","Guild Chat Invite");
  QuickLayer_GuildCheck:SetScript("OnClick", function()
  			QuickLayer.guild = QuickLayer_GuildCheck:GetChecked();
		end);
  QuickLayer_Options_CreateCheckbutton(-5, 200, "QuickLayer_WhisperCheck","Whisper Invite");
  QuickLayer_WhisperCheck:SetScript("OnClick", function()
  			QuickLayer.whisper = QuickLayer_WhisperCheck:GetChecked();
		end);
  QuickLayer_Options_CreateCheckbutton(-5, 240, "QuickLayer_RaidInvite","Invite in Raid");
  QuickLayer_RaidInvite:SetScript("OnClick", function()
  			QuickLayer.inviteInRaid = QuickLayer_RaidInvite:GetChecked();
		end);

    QuickLayer_Options_CreateLabel(0, 280, "Invite Group Threshold");
    QuickLayer_Options_CreateThresholdMenu(180, 280)
end

function QuickLayer_Options_CreateLabel(xOffset, yOffset, text)
  local uiObject = QuickLayer_Options:CreateFontString(nil, "Overlay");
  uiObject:SetPoint("TOPLEFT", xOffset + 16, -yOffset - 16);
	uiObject:SetTextColor(1, 0.8, 0);
  uiObject:SetFont("Fonts\\FRIZQT__.TTF", 16);
  uiObject:SetText(text);
end

function QuickLayer_Options_CreateCheckbutton(xOffset, yOffset, name, text)
  local uiObject = CreateFrame("CheckButton", name, QuickLayer_Options, "ChatConfigCheckButtonTemplate");
  uiObject:SetPoint("TOPLEFT", xOffset + 16, -yOffset - 16);
  getglobal(name .. 'Text'):SetText(text);
end

function QuickLayer_Options_CreateThresholdMenu(xOffset, yOffset)
  local uiObject = CreateFrame("Frame", nil, QuickLayer_Options, "UIDropDownMenuTemplate");
  uiObject:SetPoint("TOPLEFT", xOffset + 16, -yOffset - 12);
  UIDropDownMenu_JustifyText(uiObject, "LEFT");
  UIDropDownMenu_Initialize(uiObject, MyDropDownMenu_OnLoad);
  UIDropDownMenu_SetWidth(uiObject, 60)
  UIDropDownMenu_SetText(uiObject, QuickLayer.inviteThreshold)
  UIDropDownMenu_Initialize(uiObject, function(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    for i = 0,4 do
     info.text = i
     info.func = self.SetValue
     info.checked = info.text == QuickLayer.inviteThreshold;
     if(info.checked) then
       UIDropDownMenu_SetText(uiObject, info.text)
     end
     info.arg1 = info.text;
     UIDropDownMenu_AddButton(info);
    end
  end)

  function uiObject:SetValue(newValue)
    QuickLayer.inviteThreshold = newValue
    UIDropDownMenu_SetText(uiObject, newValue)
    CloseDropDownMenus()
  end
end

function QuickLayer_Options_CreateEditbox(xOffset, yOffset, numeric, name, text)
  local uiObject = CreateFrame("EditBox", name, QuickLayer_Options, "InputBoxTemplate");
  uiObject:SetPoint("TOPLEFT", QuickLayer_Options, "TOPLEFT", xOffset, -yOffset + 13);
  uiObject:SetWidth(140);
  uiObject:SetHeight(80);
  uiObject:SetMaxLetters(25);
	uiObject:SetAutoFocus(false);
  if(numeric) then
	  uiObject:SetMaxLetters(4);
    uiObject:SetNumeric()
  end
	uiObject:SetScript("OnEnterPressed", function()
		uiObject:ClearFocus();
	end);
  return uiObject;
end
