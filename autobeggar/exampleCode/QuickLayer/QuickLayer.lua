local blacklist = {}
local readyForInvite = false;
local outgoingInvite = nil;

function QuickLayerEvent(self, event, arg1, arg2, arg3, arg4, ...)
  if(event == "ADDON_LOADED" and QuickLayer_MessageBox == nil) then
    QuickLayer_CreateOptions();
    QuickLayer_AddonLoadedOptions();
    return;
  end
  if(event == "CHAT_MSG_ADDON") then
    arg4, _ = strsplit("-", arg4);
    if(arg1 == "QuickLayer") then
      if(arg3 == "WHISPER") then
        blacklist[arg4] = tonumber(arg2) + GetTime();
        return;
      end
      QuickLayer_HandleRequest(arg4, false)
      return;
    else
      return
    end
  end
  if(event == "CHAT_MSG_CHANNEL") then
    if(strfind(arg4, QuickLayer.channel) and strlower(arg1) == strlower(QuickLayer.message)) then
      arg2, _ = strsplit("-", arg2);
      QuickLayer_HandleRequest(arg2, false);
    end
  elseif(event == "CHAT_MSG_WHISPER") then
      if(strlower(arg1) == strlower(QuickLayer.message)) then
        arg2, _ = strsplit("-", arg2);
        QuickLayer_HandleRequest(arg2, true);
      end
  else
    QuickLayer_PartyEvent(event, arg1);
  end
end

function QuickLayer_HandleRequest(unitName, whisper)
    if(unitName == UnitName("player") and not IsInGroup()) then
      readyForInvite = true;
    elseif(QuickLayer_PlayerCanInvite() and QuickLayer_GroupThresholdMet() and (QuickLayer_BlacklistTest(unitName) or whisper)) then
      InviteUnit(unitName);
      outgoingInvite = unitName;
      return;
    end
end

function QuickLayer_PartyEvent(event, name)
  if(event == "PARTY_INVITE_REQUEST") then
    name, _ = strsplit("-", name);
    QuickLayer_AcceptInvite(name);
  else
    QuickLayer_HandleBlacklist();
  end
end

function QuickLayer_BlacklistTest(name)
  if(blacklist[name] == nil or blacklist[name] <= GetTime()) then
    return true
  end
  return false
end

function QuickLayer_PlayerCanInvite()
  return ((IsInGroup() and (UnitIsGroupAssistant("player") or UnitIsGroupLeader("player"))) or not IsInGroup());
end

function QuickLayer_GroupThresholdMet()
  local members = GetNumGroupMembers();
  return (IsInRaid() and members < 40 and true and QuickLayer.inviteInRaid) or (IsInGroup() and members < QuickLayer.inviteThreshold)
    or (not IsInGroup() and QuickLayer.inviteThreshold ~= 0)
end

function QuickLayer_AcceptInvite(name)
  if(readyForInvite) then
    if(blacklist[name] ~= nil and blacklist[name] > GetTime()) then
      DeclineGroup();
      local payload = blacklist[name] - GetTime();
      C_ChatInfo.SendAddonMessage("QuickLayer", payload, "WHISPER", name);
      StaticPopup_Hide("PARTY_INVITE");
      return
    end
    AcceptGroup();
    StaticPopup_Hide("PARTY_INVITE");
    blacklist[name] = (GetTime() + QuickLayer.delay);
    readyForInvite = false;
  end
end

function QuickLayer_HandleBlacklist()
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      if(UnitName("raid" .. i) ~= nil) then
        blacklist[UnitName("raid" .. i)] = (GetTime() + QuickLayer.delay);
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumGroupMembers() do
      if(UnitName("party" .. i) ~= nil) then
        blacklist[UnitName("party" .. i)] = (GetTime() + QuickLayer.delay);
      end
    end
  end
end

function TargetIsInvited(name)
  return name == outgoingInvite
end

function QuickLayer_FindGroup()
  if(QuickLayer.guild) then
    C_ChatInfo.SendAddonMessage("QuickLayer", "I" , "GUILD")
  end
  if(QuickLayer.channel ~= nil) then
    for i=1,15 do
      local id, name = GetChannelName(i);
      if(name ~= nil and string.lower(name) == string.lower(QuickLayer.channel)) then
        SendChatMessage(QuickLayer.message, "CHANNEL", nil, id);
      end
    end
  end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", QuickLayerEvent);
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PARTY_INVITE_REQUEST")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("ADDON_LOADED")
C_ChatInfo.RegisterAddonMessagePrefix("QuickLayer");
SLASH_QUICKLAYER1 = "/l"
SLASH_QUICKLAYER2 = "/layer"
SlashCmdList["QUICKLAYER"] = QuickLayer_FindGroup;
