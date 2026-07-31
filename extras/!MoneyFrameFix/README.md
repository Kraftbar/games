# !MoneyFrameFix

A standalone World of Warcraft 1.12 compatibility fix for this error:

```text
Interface\FrameXML\MoneyFrame.lua:185: attempt to perform arithmetic on local 'money' (a nil value)
```

Puppeteer's bundled HealComm-1.0 library creates a hidden `GameTooltipTemplate` during addon loading. Its static child money frame can update before `staticMoney` is initialized. Blizzard's 1.12 `MoneyFrame_Update` then attempts arithmetic on `nil`.

The addon loads early and makes shared static money frames return `0` instead of `nil`. It also records unexpected nil-money calls for diagnosis.

## Installation

Copy the entire `!MoneyFrameFix` directory directly into `Interface/AddOns`, beside `vanilla-addon`:

```text
Interface/AddOns/!MoneyFrameFix/!MoneyFrameFix.toc
Interface/AddOns/vanilla-addon/vanilla-addon.toc
```

Do not leave it nested inside `vanilla-addon/extras`; WoW does not discover nested addons. Keep the leading `!` so the fix loads before other addons, then fully restart WoW.

Use `/moneyfix` to display captured nil-money calls. The old `/moneyprobe` command remains as an alias.
