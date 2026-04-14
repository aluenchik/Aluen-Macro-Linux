# Aluen's Macro — Linux

Sol's RNG biome macro for Linux.  
Detects biomes in real time via Sober logs and sends Discord webhook notifications

## Features

- Real-time biome detection via Sober log parsing
- Discord embed notifications on biome start / end
- `@everyone` ping for rare biomes
- AntiAFK — sends jump keystroke to Sober automatically
- Session duration in stop notification
- Server invite link in every notification

## Requirements

| Tool | Purpose |
|---|---|
| [Sober](https://sober.vinegarhq.org/) | Roblox on Linux (Flatpak) |
| `curl` | Discord webhooks |
| `xdotool` | AntiAFK (requires X11 for Sober in Flatseal) |

## Installation

```bash
git clone https://github.com/aluenchik/Aluen-Macro-Linux
cd Aluen-Macro-Linux
chmod +x macro.sh
./macro.sh
```

# Configuration
Config is created automatically at ~/.config/sols_rng/config.conf on first launch.

Edit via the Settings menu or manually.

# Key	Description
| Key | Description |
|---|---|
| `WEBHOOK_URL` | Discord webhook URL |
| `SERVER_INVITE` | Roblox VIP server link |
| `ANTIAFK_ENABLED` | `true` / `false` |
| `ANTIAFK_INTERVAL` | Seconds between keypresses (default: `300`) |
| `NOTIFY_ONLY` | Biomes to notify about (empty = all) |
| `PING_FOR` | Biomes that trigger `@everyone` |

# AntiAFK
Sends a jump keystroke directly to the Sober window at a set interval without stealing focus.

# Requires X11: enable the X11 windowing system for Sober in Flatseal.

<img width="574" height="181" alt="image" src="https://github.com/user-attachments/assets/cc054bdd-a9d2-4d9e-9d2c-28460c5074bc" />

Use Settings → AntiAFK diagnostics to verify detection.

# Platform
Tested on Arch Linux · KDE Plasma · (Wayland + XWayland) / X11 · Sober
