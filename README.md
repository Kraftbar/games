# RoundNotify

## Config file location (CS2 only)

Place this file:



gamestate_integration_roundnotify.cfg


in:



Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\


Restart Counter-Strike 2 after placing the file.

---

## What it does
- Listens on `http://127.0.0.1:3000`
- Beeps when a **new round starts** (`round.phase = freezetime`)
- Intended for use while **alt-tabbed**

---

## TODO
- Do not beep if CS2 window is already focused
