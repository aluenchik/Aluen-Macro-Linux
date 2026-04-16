# Aluen's Macro — Linux

Sol's RNG biome macro for Linux.  
Detects biomes in real time via Sober logs and sends Discord webhook notifications.

## Features

- Real-time biome detection via Sober log parsing
- Discord embed notifications on biome start / end
- Role ping for rare biomes
- **AntiAFK** — sends jump keystroke to the Sober window automatically
- **Merchant automation** — uses Merchant Teleporter, detects which merchant appeared, auto-buys configured items, sends screenshot to Discord
- **Strange Controller** — uses item from inventory on a timer
- **Biome Randomizer** — uses item from inventory on a timer
- **Custom Use Items** — use any inventory item on a configurable cooldown
- Auto-buy with optional "set to max" quantity support (Mari & Jester)
- Calibration templates — save and switch between screen layouts
- GUI with live log, update notifications, dark theme

## Requirements

| Tool | Purpose |
|---|---|
| [Sober](https://sober.vinegarhq.org/) | Roblox on Linux (Flatpak) |
| `curl` | Discord webhooks |
| `xdotool` | AntiAFK, Merchant, inventory automation |
| `python3` + `tesseract` | Merchant OCR (optional, for auto-detect & auto-buy) |
| `spectacle` / `grim` / `scrot` | Screenshots for Discord (optional) |
| `python3-pillow` / `Pillow` | Logo display in GUI (optional) |

> **Note:** xdotool requires X11. Enable the X11 windowing system for Sober in **Flatseal**.

## Installation

```bash
git clone https://github.com/aluenchik/Aluen-Macro-Linux
cd Aluen-Macro-Linux
pip install pillow   # optional, for logo in GUI
python3 gui.py
```

## Usage

Launch the GUI:
```bash
python3 gui.py
```

Or start monitoring directly (headless):
```bash
bash macro.sh --monitor
```

## Configuration

Config is created automatically at `~/.config/sols_rng/config.conf` on first launch.  
All settings are managed through the GUI — no manual editing required.

### Key settings

| Key | Description |
|---|---|
| `WEBHOOK_URL` | Discord webhook URL |
| `SERVER_INVITE` | Roblox server invite link |
| `ANTIAFK_ENABLED` | `true` / `false` |
| `ANTIAFK_INTERVAL` | Seconds between keypresses (default: `300`) |
| `NOTIFY_ONLY` | Biomes to notify about (empty = all) |
| `PING_FOR` | Biomes that trigger role ping |
| `MERCHANT_ENABLED` | Enable merchant automation |
| `MERCHANT_INTERVAL` | Seconds between merchant checks (default: `300`) |
| `MARI_BUY_ITEMS` | Items to auto-buy from Mari |
| `MARI_MAX_ITEMS` | Mari items to buy with max quantity |
| `JESTER_BUY_ITEMS` | Items to auto-buy from Jester |
| `JESTER_MAX_ITEMS` | Jester items to buy with max quantity |
| `STRANGE_CONTROLLER_ENABLED` | Enable Strange Controller auto-use |
| `STRANGE_CONTROLLER_INTERVAL` | Cooldown in seconds (default: `1200`) |
| `BIOME_RANDOMIZER_ENABLED` | Enable Biome Randomizer auto-use |
| `BIOME_RANDOMIZER_INTERVAL` | Cooldown in seconds (default: `2100`) |
| `CUSTOM_USE_ITEMS` | Custom items to use on a timer (`"Name\|cooldown"`) |

## Calibration

The macro clicks specific screen coordinates for inventory actions.  
Default values are set for **1920×1080**. If your layout differs, use the **Pick** buttons in Settings → Calibration to recalibrate.

Calibration presets can be saved, loaded and deleted from the template dropdown.

## Platform

Tested on Arch Linux · KDE Plasma · Wayland + XWayland · Sober
