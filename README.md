# Whispers

**Author:** Lydya  
**Version:** 2.0.0  
**Game:** Made for FFXI on HorizonXI
**Description:** A chat replacement addon that organizes incoming messages into tabs and provides a quick-reply input box. 

Version 2.0 has seen a refocus on the important messages: LS, Tells, Party and Say. All the rest is sent to the default FFXI window. The messages captured and displayed by Whispers are supressed from the default FFXI chat window.

The combat log window was removed and moved to it's own addon called Combatlog. https://github.com/Lydya-nick77/combatlog

---

## Features

- **Tabbed chat window** — separate tabs for All, LS 1, LS 2, Party, Say, and individual tell senders
- **All tab** — read-only merged view of every tab sorted by time
- **Unread indicators** — blinking tab highlight when a new message arrives in a background tab
- **Auto-translate support** — auto-translate phrases rendered with colored braces
- **24-hour TTL** — messages older than 24 hours are automatically pruned on load
- **Input character limit** — matches the FFXI in-game chat character cap 

---

## Commands

| Command | Description |
|---|---|
| `/whispers` | Open the settings window |
| `/whispers chat` | Toggle the chat window on/off |
| `/whispers help` | Print command list to the FFXI chat log |

---

## Settings window

Open with `/whispers`. From there you can adjust:

- **Font scale** — global UI font size
- **Message font scale** — font size for chat messages only
- **Chat TTL** — how many seconds messages are kept (default: 86400 = 24 h)
- **Max messages per tab** — oldest messages are trimmed when the cap is reached (default: 300)
- **Unread blinking** — toggle and configure blink per tab
- **Per-tab color overrides**
- **Window background opacity**

---

## Data location

Messages are saved per character under the Ashita config directory:

```
<Ashita install>\config\addons\Whispers\<charname>\messages.dat
```

Settings (window position, font scales, colors, etc.) are saved by the Ashita `settings` module:

```
<Ashita install>\config\addons\Whispers\<charname>\settings.json
```
