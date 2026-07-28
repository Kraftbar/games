-- WHC server compatibility (WOW-HC.com) without the official addon.
-- Sends the login handshake so the server enables world chat and broadcasts
-- for this client, then hides the ::whc:: protocol lines the server streams
-- over CHAT_MSG_SYSTEM afterwards. Steps aside entirely if the real WOW_HC
-- addon is loaded, so both can be installed without fighting over the hooks.

local WHC_COMPAT_VERSION = "2.1" -- version string the official addon reports

local function whcAddonLoaded()
    if WHC then return true end
    if IsAddOnLoaded and IsAddOnLoaded("WOW_HC") then return true end
    return false
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    if whcAddonLoaded() then return end

    -- Server broadcasts (world chat relay, death announcements) arrive as
    -- creature say, which the default chat frame filters out.
    ChatFrame_AddMessageGroup(DEFAULT_CHAT_FRAME, "CREATURE")

    -- Identify as the official addon; the server gates addon features on this.
    SendChatMessage(".whc version " .. WHC_COMPAT_VERSION, "WHISPER", GetDefaultLanguage(), UnitName("player"))

    -- Hide the ::whc:: control lines (auction config, group finder data, ...)
    -- the server streams once the handshake is done.
    local origChatFrameOnEvent = ChatFrame_OnEvent
    ChatFrame_OnEvent = function(ev)
        if ev == "CHAT_MSG_SYSTEM" and type(arg1) == "string" and string.find(string.lower(arg1), "^::whc::") then
            return
        end
        origChatFrameOnEvent(ev)
    end

    -- Join world a few seconds late so it does not shuffle General off slot 1
    -- (ordering issue noted in the official addon's own TODO list).
    loginFrame.joinAt = GetTime() + 5
    loginFrame:SetScript("OnUpdate", function()
        if GetTime() < (this.joinAt or 0) then return end
        this:SetScript("OnUpdate", nil)
        JoinChannelByName("world", nil, DEFAULT_CHAT_FRAME)
    end)
end)
