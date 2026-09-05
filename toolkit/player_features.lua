-- Optional character/class-specific conveniences.

local VA = VanillaAddon
VA:RegisterModule("player-features", true)

-- Player identity is unavailable at file-load time on a fresh login (only on
-- /reload), so all character-specific setup waits for PLAYER_READY.
VA:On("PLAYER_READY", function()
    local playerName = UnitName("player")
    local _, playerClass = UnitClass("player")

    if playerName == "Crazyforg" then
        local phrases = {
            lowHealth = "Baa aramba baa bom baa barooumba!",
            critHit = "Ring ding ding ding daa baa!",
            enteredCombat = "Let's goooo! Bom bom baa da bom!",
            leftCombat = "All clear! Boing boing boing!",
        }
        local lastLowHealth = 0
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
        frame:RegisterEvent("UNIT_HEALTH")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function()
            if event == "CHAT_MSG_COMBAT_SELF_CRITS" then SendChatMessage(phrases.critHit, "SAY")
            elseif event == "PLAYER_REGEN_DISABLED" then SendChatMessage(phrases.enteredCombat, "SAY")
            elseif event == "PLAYER_REGEN_ENABLED" then SendChatMessage(phrases.leftCombat, "SAY")
            elseif event == "UNIT_HEALTH" and arg1 == "player" then
                local maximum = UnitHealthMax("player") or 0
                if maximum > 0 and UnitHealth("player") / maximum < 0.25 and GetTime() - lastLowHealth > 15 then
                    lastLowHealth = GetTime()
                    SendChatMessage(phrases.lowHealth, "SAY")
                end
            end
        end)
    end

    if playerClass == "PALADIN" then
        local button = CreateFrame("Button", "WisdomButton", UIParent, "UIPanelButtonTemplate")
        button:SetWidth(120); button:SetHeight(30)
        VA:ApplyFramePosition("wisdomButton", button, "BOTTOMRIGHT", -20, 20)
        VA:MakeMovable(button, "wisdomButton")
        button:SetText("Bless Wisdom")
        button:SetScript("OnClick", function() CastSpellByName("Blessing of Wisdom") end)
        local function hasWisdom()
            for i = 1, 16 do if UnitBuff("player", i) == "Interface\\Icons\\Spell_Holy_SealOfWisdom" then return true end end
            return false
        end
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_AURAS_CHANGED")
        frame:SetScript("OnEvent", function() if hasWisdom() then button:Hide() else button:Show() end end)
        if hasWisdom() then button:Hide() else button:Show() end
    end
end)
