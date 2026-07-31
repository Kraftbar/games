local files = {
    "vanilla_core.lua", "combat_core.lua", "combat_ui.lua", "combat_warnings.lua", "player_features.lua",
    "ledger_core.lua", "ledger_economics.lua", "ledger_mail.lua", "ledger_ui.lua", "aux_core.lua", "aux_ui.lua",
}
for _, filename in ipairs(files) do
    local chunk, err = loadfile(filename)
    if not chunk then error(err) end
    print(filename .. ": syntax ok")
end
