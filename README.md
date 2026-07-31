# Vanilla Toolkit

A modular World of Warcraft 1.12 addon for combat tracking, time-to-death warnings, auction history/economics, diagnostics, and Aux offline-database search. The code targets Lua 5.0 and the Vanilla global `event`, `arg1`, and `this` callback model.

## Modules

Modules are loaded in `vanilla-addon.toc`. Optional functionality can be removed by deleting or commenting out its TOC line.

- `vanilla_core.lua` — saved settings, diagnostics, module events, and frame-position persistence. Required.
- `combat_core.lua` — damage collection and persistent encounter history. Independent of the UI.
- `combat_ui.lua` — live combat windows and history window. Optional.
- `combat_warnings.lua` — low-HP/time-to-death alerts. Optional; requires combat core.
- `player_features.lua` — character/class-specific Crazyforg and Paladin conveniences. Optional.
- `ledger_core.lua` — ledger storage, summaries, views, and commands. Required by other ledger modules.
- `ledger_economics.lua` — confirmed post/bid capture, deposits, estimated AH cuts, and FIFO cost basis. Optional.
- `ledger_mail.lua` — auction system-message and mailbox collection. Optional.
- `ledger_ui.lua` — ledger table and minimap button. Optional.
- `aux_core.lua` — deterministic Aux DB search, price filters, and sorting. Independent of its UI.
- `aux_ui.lua` — debounced search window, filters, sortable columns, and minimap button. Optional.

## Commands

- `/vanilla status` — show loaded modules.
- `/vanilla diag on|off|show|clear` — capture and inspect unparsed messages and Lua errors.
- `/combatstats show|hide|history|clear|debug` — combat UI/history controls.
- `/combatwarn on|off|hpp N|ttd N|cooldown N` — persistent warning settings.
- `/ledger` — totals and command help.
- `/ledger ui` — open the ledger table.
- `/ledger view all|sold|expired|bought` — select ledger rows.
- `/ledger economics` — show revenue, known costs, lost deposits, estimated profit, and pending matches.
- `/ledger cut N` — set the estimated auction-house cut percentage.
- `/auxfind <words or item ID>` — search the Aux offline database.

## Auction economics

Economics are best-effort because Vanilla mail does not contain a complete accounting record:

- Accepted `StartAuction` calls provide item count and deposit.
- Accepted `PlaceAuctionBid` calls provide purchase price and quantity.
- Bought items create FIFO cost lots; later sales of the exact item name consume those lots.
- Sale mail is treated as net proceeds. Gross and AH cut are estimated using the saved cut rate (default 5%).
- Expired auctions count their captured deposit as lost.
- Profit remains visibly unknown when no matching purchase cost exists.

Existing `VanillaLedgerDB` sold, expired, and bought rows are retained. Shared settings and combat history live under `VanillaLedgerDB.addon`; `VanillaAddonDB` remains an in-memory compatibility alias.

## Testing

From the addon directory, static and mocked regression checks can be run with:

```sh
texlua tests/syntax.lua
texlua tests/smoke.lua
```

After updating the addon, use `/reload`, then check:

1. Direct and periodic damage update the combat windows.
2. `/combatstats history` shows a completed encounter.
3. `/ledger ui` opens existing ledger data.
4. Posting, buying, selling, and expiring a small auction updates `/ledger economics`.
5. `/auxfind` supports live debounced text search, min/max gold, cached-only filtering, and header sorting.

If a server uses different combat or auction text, enable `/vanilla diag on`, reproduce it, and inspect `/vanilla diag show`.
