# ================================================================
#   modules/menu.sh - Menu interface
# ================================================================

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
        echo "4) Edit config manually"
        echo "5) AntiAFK diagnostics"
        echo "6) Back"
        echo ""
        read -p "Select option [1-6]: " choice

        case $choice in
            1) edit_webhook_url; load_config ;;
            2) edit_server_invite; load_config ;;
            3) toggle_antiafk; load_config ;;
            4) edit_config_manual; load_config ;;
            5) diagnose_window ;;
            6) return ;;
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
    echo "FEATURES:"
    echo "  • Real-time biome monitoring"
    echo "  • Discord notifications via Webhook"
    echo "  • AntiAFK system with xdotool"
    echo "  • Auto-reconnect on new session"
    echo ""
    echo "DEPENDENCIES:"
    echo "  • curl (required)"
    echo "  • X11: xdotool (for AntiAFK)"
    echo ""
    echo "CONFIGURATION:"
    echo "  File: $CONFIG_FILE"
    echo ""
    echo "REQUIREMENTS:"
    echo "  1. Set Discord Webhook URL"
    echo "  2. Set Roblox server link"
    echo "  3. Launch Sol's RNG via Sober"
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

    # Display server info
    local session_type="${XDG_SESSION_TYPE:-unknown}"
    echo "Session type : $session_type"
    echo "DISPLAY      : ${DISPLAY:-not set}"
    echo "WAYLAND      : ${WAYLAND_DISPLAY:-not set}"
    echo ""

    # Tool availability
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

    # X11/XWayland window search
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

    # Native Wayland window search
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
