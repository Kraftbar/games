-- Optional low-health / time-to-death warnings.

local VA = VanillaAddon
local Warnings = { lastAt = 0 }
VA.CombatWarnings = Warnings
VA:RegisterModule("combat-warnings", Warnings)

function Warnings:Estimate()
    local maxHealth = UnitHealthMax("player") or 0
    local health = UnitHealth("player") or 0
    if maxHealth <= 0 then return 0, 0, 0, 0 end
    local dtps, attackers = VA.Combat:GetRecent()
    if dtps <= 0 then dtps = VA.Combat:GetSnapshot().dtps or 0 end
    local ttd = dtps > 0 and health / dtps or 0
    return ttd, health / maxHealth, dtps, attackers
end

function Warnings:Check()
    local settings = VA.settings.warnings
    if not settings.enabled or not UnitAffectingCombat("player") then return end
    local now = GetTime()
    if now - self.lastAt < (settings.cooldown or 8) then return end
    local ttd, healthPct, _, attackers = self:Estimate()
    if healthPct < (settings.hpPct or 0.35) and ttd > 0 and ttd <= (settings.ttd or 5) then
        self.lastAt = now
        local message = format("LOW HP! TTD %.1fs (HP %d%%, attackers %d)", ttd, floor(healthPct * 100 + 0.5), attackers or 0)
        UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1, 1, 5)
        if VA.CombatUI and VA.CombatUI.death then
            VA.CombatUI.death.scroll:AddMessage("|cffff0000" .. message .. "|r")
        end
        VA:Diag("warning", message)
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function()
    if (this.nextCheck or 0) > GetTime() then return end
    this.nextCheck = GetTime() + 0.5
    Warnings:Check()
end)

SLASH_COMBATWARN1 = "/combatwarn"
SlashCmdList["COMBATWARN"] = function(message)
    local _, _, command, argument = strfind(message or "", "^(%S+)%s*(.*)$")
    command = strlower(command or "status")
    local value = tonumber(argument)
    local settings = VA.settings.warnings
    if command == "on" then settings.enabled = true
    elseif command == "off" then settings.enabled = false
    elseif command == "ttd" and value and value > 0 then settings.ttd = value
    elseif command == "hpp" and value and value > 0 and value <= 100 then settings.hpPct = value / 100
    elseif command == "cooldown" and value and value >= 0 then settings.cooldown = value
    else
        VA:Print(format("Warnings %s: HP %d%%, TTD %.1fs, cooldown %.1fs. Commands: on|off|hpp N|ttd N|cooldown N",
            settings.enabled and "on" or "off", floor(settings.hpPct * 100 + 0.5), settings.ttd, settings.cooldown))
        return
    end
    VA:Print("Warning settings updated")
end
