#!/usr/bin/env bash
# ================================================================
#   Dependencies: curl, xdotool (for AntiAFK)
# ================================================================

# ┌─────────────────────────────────────────┐
# │             MACRO VERSION               │
# └─────────────────────────────────────────┘
VERSION="1.2"

# ┌─────────────────────────────────────────┐
# │           MODULE PATH SETUP             │
# └─────────────────────────────────────────┘

# Resolve the real script location (follow symlinks)
if [ -L "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
# Core lives in modules/core/ — project root is two levels up
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
CORE_DIR="${MODULES_DIR}/core"
MERCHANT_DIR="${MODULES_DIR}/merchant"

mkdir -p "$CORE_DIR" "$MERCHANT_DIR"

# ┌─────────────────────────────────────────┐
# │            LOAD MODULES                 │
# └─────────────────────────────────────────┘

check_core() {
    local f="${CORE_DIR}/${1}"
    if [ ! -f "$f" ]; then
        echo "[ERROR] Core module not found: modules/core/${1}"
        exit 1
    fi
}

check_merchant() {
    local f="${MERCHANT_DIR}/${1}"
    if [ ! -f "$f" ]; then
        echo "[ERROR] Merchant module not found: modules/merchant/${1}"
        exit 1
    fi
}

# Core (always loaded)
check_core "settings.sh"
check_core "discord.sh"
check_core "biome_parser.sh"
check_core "antiafk.sh"
check_core "monitor.sh"

source "${CORE_DIR}/settings.sh"
source "${CORE_DIR}/discord.sh"
source "${CORE_DIR}/biome_parser.sh"
source "${CORE_DIR}/antiafk.sh"
source "${CORE_DIR}/monitor.sh"

# Merchant module
check_merchant "merchant.sh"
source "${MERCHANT_DIR}/merchant.sh"

# Items module (Strange Controller, Biome Randomizer)
ITEMS_MODULE="${MODULES_DIR}/items.sh"
if [ ! -f "$ITEMS_MODULE" ]; then
    echo "[ERROR] Module not found: modules/items.sh"
    exit 1
fi
source "$ITEMS_MODULE"

# ┌─────────────────────────────────────────┐
# │            UPDATE CHECK                 │
# └─────────────────────────────────────────┘

check_for_updates() {
    command -v curl &>/dev/null || return

    local api_url="https://api.github.com/repos/aluenchik/Aluen-Macro-Linux/releases/latest"
    local response
    response=$(curl -s --max-time 5 "$api_url" 2>/dev/null)
    [ -z "$response" ] && return

    local latest
    latest=$(printf '%s' "$response" | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [ -z "$latest" ] && return

    local latest_clean="${latest#v}"

    if [ "$latest_clean" != "$VERSION" ]; then
        echo "╔══════════════════════════════════════════╗"
        echo "║           UPDATE AVAILABLE               ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "  Current version : v${VERSION}"
        echo "  Latest version  : ${latest}"
        echo ""
        echo "  https://github.com/aluenchik/Aluen-Macro-Linux"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# ┌─────────────────────────────────────────┐
# │              MAIN MENU                  │
# └─────────────────────────────────────────┘

show_main_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║   Sol's RNG Macro v${VERSION}                   ║"
        echo "║   Linux (Wayland) + Sober                ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "1) Start monitoring"
        echo "2) Settings"
        echo "3) Info"
        echo "4) Exit"
        echo ""
        read -p "Select option [1-4]: " choice

        case $choice in
            1) start_monitoring ;;
            2) show_settings_menu ;;
            3) show_info ;;
            4) exit 0 ;;
            *) echo "Invalid choice. Press Enter..."; read ;;
        esac
    done
}

# ┌─────────────────────────────────────────┐
# │            SETTINGS MENU                │
# └─────────────────────────────────────────┘

show_settings_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║               SETTINGS                   ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "1) Discord Webhook URL"
        echo "   Current: ${WEBHOOK_URL:0:50}..."
        echo ""
        echo "2) Roblox Server Link"
        echo "   Current: ${SERVER_INVITE:0:50}..."
        echo ""
        echo "3) AntiAFK"
        if $ANTIAFK_ENABLED; then
            echo "   Status: Enabled (interval: ${ANTIAFK_INTERVAL}s)"
        else
            echo "   Status: Disabled"
        fi
        echo ""
        echo "4) Modules"
        echo "5) Edit config manually"
        echo "6) AntiAFK diagnostics"
        echo "7) Back"
        echo ""
        read -p "Select option [1-7]: " choice

        case $choice in
            1) edit_webhook_url; load_config ;;
            2) edit_server_invite; load_config ;;
            3) toggle_antiafk; load_config ;;
            4) show_modules_menu ;;
            5) edit_config_manual; load_config ;;
            6) diagnose_window ;;
            7) return ;;
            *) echo "Invalid choice. Press Enter..."; read ;;
        esac
    done
}

# ┌─────────────────────────────────────────┐
# │            MODULES MENU                 │
# └─────────────────────────────────────────┘

show_modules_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║               MODULES                    ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "1) Merchant"
        if [[ "$MERCHANT_ENABLED" == "true" ]]; then
            echo "   Status: Enabled (every ${MERCHANT_INTERVAL:-300}s)"
        else
            echo "   Status: Disabled"
        fi
        echo ""
        echo "2) Strange Controller"
        if [[ "$STRANGE_CONTROLLER_ENABLED" == "true" ]]; then
            echo "   Status: Enabled (every $(( ${STRANGE_CONTROLLER_INTERVAL:-1200} / 60 )) min)"
        else
            echo "   Status: Disabled"
        fi
        echo ""
        echo "3) Biome Randomizer"
        if [[ "$BIOME_RANDOMIZER_ENABLED" == "true" ]]; then
            echo "   Status: Enabled (every $(( ${BIOME_RANDOMIZER_INTERVAL:-2100} / 60 )) min)"
        else
            echo "   Status: Disabled"
        fi
        echo ""
        echo "4) Back"
        echo ""
        read -p "Select option [1-4]: " choice

        case $choice in
            1) merchant_settings_menu; load_config ;;
            2) strange_controller_settings_menu; load_config ;;
            3) biome_randomizer_settings_menu; load_config ;;
            4) return ;;
            *) echo "Invalid choice. Press Enter..."; read ;;
        esac
    done
}

# ┌─────────────────────────────────────────┐
# │                 INFO                    │
# └─────────────────────────────────────────┘

show_info() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║                 INFO                     ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Aluen's Macro Linux v${VERSION}"
    echo ""
    echo "Platform: Linux + Sober"
    echo "Author: Aluen"
    echo ""
    echo "DEPENDENCIES:"
    echo "  • curl (required)"
    echo "  • X11: xdotool (for AntiAFK)"
    echo ""
    echo "CONFIGURATION:"
    echo "  File: $CONFIG_FILE"
    echo ""
    read -p "Press Enter to return to menu..."
}

# ┌─────────────────────────────────────────┐
# │        ANTIAFK DIAGNOSTICS              │
# └─────────────────────────────────────────┘

diagnose_window() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║         ANTIAFK DIAGNOSTICS              ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    local session_type="${XDG_SESSION_TYPE:-unknown}"
    echo "Session type : $session_type"
    echo "DISPLAY      : ${DISPLAY:-not set}"
    echo "WAYLAND      : ${WAYLAND_DISPLAY:-not set}"
    echo ""

    echo "═══════════════════════════════════════════"
    echo "AVAILABLE TOOLS:"
    echo ""
    for tool in xdotool wmctrl ydotool wtype hyprctl swaymsg wlrctl; do
        if command -v "$tool" &>/dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done

    if [ -n "$DISPLAY" ]; then
        echo ""
        echo "═══════════════════════════════════════════"
        echo "WINDOW SEARCH (X11/XWayland):"
        echo ""

        if command -v xdotool &>/dev/null; then
            echo "xdotool --class 'sober.org.vinegarhq.Sober':"
            local result
            result=$(xdotool search --class "sober.org.vinegarhq.Sober" 2>/dev/null | head -1)
            if [ -n "$result" ]; then
                echo "  ✓ ID: $result"
            else
                echo "  ✗ Not found"
            fi
        fi

        if command -v wmctrl &>/dev/null; then
            echo ""
            echo "wmctrl -lx (Sober):"
            local wm_result
            wm_result=$(wmctrl -lx 2>/dev/null | grep -i "sober")
            if [ -n "$wm_result" ]; then
                echo "  ✓ $wm_result"
            else
                echo "  ✗ Not found"
            fi
        fi
    fi

    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo ""
        echo "═══════════════════════════════════════════"
        echo "PROCESS SEARCH (native Wayland):"
        echo ""

        echo "Sober (/proc/*/exe -> /app/bin/sober):"
        if ls -la /proc/*/exe 2>/dev/null | grep -q " -> /app/bin/sober$"; then
            echo "  ✓ Process found"
        else
            echo "  ✗ Process not found (Sober not running?)"
        fi

        if command -v busctl &>/dev/null; then
            echo ""
            echo "KDE KWin (window focus):"
            if busctl --user list 2>/dev/null | grep -q "org.kde.KWin"; then
                echo "  ✓ KWin available via DBus"
            else
                echo "  ✗ KWin not found"
            fi
        fi

        if command -v hyprctl &>/dev/null; then
            echo ""
            echo "hyprctl clients (Sober):"
            if hyprctl clients -j 2>/dev/null | grep -qi '"class": "sober"'; then
                echo "  ✓ Found"
            else
                echo "  ✗ Not found"
            fi
        fi

        if command -v swaymsg &>/dev/null; then
            echo ""
            echo "swaymsg get_tree (Sober):"
            if swaymsg -t get_tree 2>/dev/null | grep -qi '"app_id": "sober"'; then
                echo "  ✓ Found"
            else
                echo "  ✗ Not found"
            fi
        fi

        if command -v wlrctl &>/dev/null; then
            echo ""
            echo "wlrctl window list (Sober):"
            if wlrctl window list 2>/dev/null | grep -qi "sober"; then
                echo "  ✓ Found"
            else
                echo "  ✗ Not found"
            fi
        fi
    fi

    echo ""
    echo "═══════════════════════════════════════════"
    echo "FINAL CHECK (get_window_id):"
    echo ""

    local wid
    wid=$(get_window_id)

    if [ -n "$wid" ]; then
        echo "[✓] WINDOW FOUND!"
        if [ "$wid" != "wayland" ]; then
            local window_name
            window_name=$(xdotool getwindowname "$wid" 2>/dev/null)
            echo "    Mode: X11/XWayland"
            echo "    ID: $wid"
            echo "    Name: $window_name"
        else
            echo "    Mode: native Wayland"
        fi
        echo ""
        echo "AntiAFK can send keystrokes."
    else
        echo "[!] WINDOW NOT FOUND"
        echo ""
        echo "Possible reasons:"
        echo "  1. Sober/Roblox is not running"
        echo "  2. Window is minimized or hidden"
        echo ""
        if [ -n "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
            echo "You are on native Wayland. Install a tool for your compositor:"
            echo "  Hyprland : built-in (hyprctl)"
            echo "  Sway     : built-in (swaymsg)"
            echo "  Other    : sudo pacman -S wlrctl"
            echo ""
            echo "To send keystrokes install one of:"
            echo "  ydotool  : sudo pacman -S ydotool"
            echo "             systemctl --user enable --now ydotool"
            echo "  wtype    : sudo pacman -S wtype"
        else
            echo "Install wmctrl: sudo pacman -S wmctrl"
            echo "Make sure the Sober window is visible on screen"
        fi
    fi

    echo ""
    read -p "Press Enter to return to menu..."
}

# ┌─────────────────────────────────────────┐
# │              ENTRY POINT                │
# └─────────────────────────────────────────┘

main() {
    load_config
    if [[ "${1:-}" == "--monitor" ]]; then
        start_monitoring
        return
    fi
    check_for_updates
    show_main_menu
}

main "$@"
