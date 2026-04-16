# ================================================================
#   modules/items.sh - Periodic item use from inventory
# ================================================================
#
# Depends on: merchant.sh loaded first
#   (_mclick, _mkey, _merchant_focus, MERCHANT_CAL_* variables)
# ================================================================

STRANGE_CONTROLLER_LAST=$(date +%s)
BIOME_RANDOMIZER_LAST=$(date +%s)

# ┌─────────────────────────────────────────┐
# │      GENERIC USE-ITEM FROM INVENTORY    │
# └─────────────────────────────────────────┘

# Open inventory → Items tab → search → select → Use → close.
# item_name must be lowercase (avoids Shift events going to the game).
_use_item_from_inventory() {
    local wid="$1"
    local item_name="$2"
    local pfx="[Items]"

    _merchant_focus "$wid"

    echo "[$(date '+%H:%M:%S')] $pfx Opening inventory..."
    _mclick "$MERCHANT_CAL_INV_X" "$MERCHANT_CAL_INV_Y"
    sleep 1.5

    echo "[$(date '+%H:%M:%S')] $pfx Clicking Items tab..."
    _mclick "$MERCHANT_CAL_ITEMS_TAB_X" "$MERCHANT_CAL_ITEMS_TAB_Y"
    sleep 0.8

    # Re-focus before text input — inventory animation may have broken focus
    _merchant_focus "$wid"

    echo "[$(date '+%H:%M:%S')] $pfx Searching: $item_name"
    _mclick "$MERCHANT_CAL_SEARCH_X" "$MERCHANT_CAL_SEARCH_Y"
    sleep 0.5

    xdotool key --window "$wid" --clearmodifiers ctrl+a 2>/dev/null
    sleep 0.15
    xdotool type --window "$wid" --clearmodifiers --delay 60 "$item_name" 2>/dev/null
    sleep 0.9

    # Re-focus before clicking item + Use
    _merchant_focus "$wid"

    echo "[$(date '+%H:%M:%S')] $pfx Selecting item..."
    _mclick "$MERCHANT_CAL_ITEM_X" "$MERCHANT_CAL_ITEM_Y"
    sleep 0.5

    echo "[$(date '+%H:%M:%S')] $pfx Clicking Use..."
    _mclick "$MERCHANT_CAL_USE_X" "$MERCHANT_CAL_USE_Y"
    sleep 1.0

    echo "[$(date '+%H:%M:%S')] $pfx Closing inventory..."
    _mclick "$MERCHANT_CAL_INV_X" "$MERCHANT_CAL_INV_Y"
    sleep 0.4
}

# ┌─────────────────────────────────────────┐
# │         STRANGE CONTROLLER              │
# └─────────────────────────────────────────┘

strange_controller_tick() {
    [[ "$STRANGE_CONTROLLER_ENABLED" == "true" ]] || return
    local now; now=$(date +%s)
    (( now - STRANGE_CONTROLLER_LAST < ${STRANGE_CONTROLLER_INTERVAL:-1200} )) && return
    STRANGE_CONTROLLER_LAST=$now
    action_queue_push "strange_controller"
}

_strange_controller_run() {
    local ts="[$(date '+%H:%M:%S')] [StrangeController]"

    if ! command -v xdotool &>/dev/null; then
        echo "$ts xdotool not found"
        return
    fi

    if [ "${MERCHANT_CAL_INV_X:-0}" -eq 0 ] && [ "${MERCHANT_CAL_INV_Y:-0}" -eq 0 ]; then
        echo "$ts Not calibrated — run calibration in Settings > Modules > Merchant"
        return
    fi

    local wid; wid=$(get_window_id)
    if [ -z "$wid" ]; then
        echo "$ts Sober window not found"
        return
    fi

    echo "$ts ─── Using Strange Controller ───"
    local prev; prev=$(xdotool getactivewindow 2>/dev/null)
    _use_item_from_inventory "$wid" "strange controller"
    [ -n "$prev" ] && [ "$prev" != "$wid" ] && xdotool windowactivate "$prev" 2>/dev/null
    echo "$ts ─── Done ───"
}

_strange_controller_toggle() {
    if [[ "$STRANGE_CONTROLLER_ENABLED" == "true" ]]; then
        save_config_value "STRANGE_CONTROLLER_ENABLED" "false"
        echo "[✓] Strange Controller disabled"
    else
        save_config_value "STRANGE_CONTROLLER_ENABLED" "true"
        echo "[✓] Strange Controller enabled"
    fi
    load_config
    read -p "Press Enter to continue..."
}

_strange_controller_set_interval() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║     STRANGE CONTROLLER INTERVAL          ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    local cur="${STRANGE_CONTROLLER_INTERVAL:-1200}"
    echo "Current: ${cur}s (every $(( cur / 60 )) min)"
    echo ""
    read -p "New interval in seconds [1200]: " val
    val="${val:-1200}"
    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 60 ]; then
        save_config_value "STRANGE_CONTROLLER_INTERVAL" "$val"
        echo "[✓] Interval set to ${val}s"
    else
        echo "[!] Invalid value (must be >= 60)"
    fi
    load_config
    read -p "Press Enter to continue..."
}

strange_controller_settings_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║       STRANGE CONTROLLER MODULE          ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        if [[ "$STRANGE_CONTROLLER_ENABLED" == "true" ]]; then
            echo "  Status   : ✓ Enabled"
        else
            echo "  Status   : ✗ Disabled"
        fi
        echo "  Interval : ${STRANGE_CONTROLLER_INTERVAL:-1200}s (every $(( ${STRANGE_CONTROLLER_INTERVAL:-1200} / 60 )) min)"
        echo ""
        echo "  Calibration shared with Merchant module."
        echo ""
        echo "1) Toggle Enable/Disable"
        echo "2) Set interval"
        echo "3) Back"
        echo ""
        read -p "Select [1-3]: " choice
        case $choice in
            1) _strange_controller_toggle ;;
            2) _strange_controller_set_interval ;;
            3) return ;;
            *) read ;;
        esac
    done
}

# ┌─────────────────────────────────────────┐
# │          BIOME RANDOMIZER               │
# └─────────────────────────────────────────┘

biome_randomizer_tick() {
    [[ "$BIOME_RANDOMIZER_ENABLED" == "true" ]] || return
    local now; now=$(date +%s)
    (( now - BIOME_RANDOMIZER_LAST < ${BIOME_RANDOMIZER_INTERVAL:-2100} )) && return
    BIOME_RANDOMIZER_LAST=$now
    action_queue_push "biome_randomizer"
}

_biome_randomizer_run() {
    local ts="[$(date '+%H:%M:%S')] [BiomeRandomizer]"

    if ! command -v xdotool &>/dev/null; then
        echo "$ts xdotool not found"
        return
    fi

    if [ "${MERCHANT_CAL_INV_X:-0}" -eq 0 ] && [ "${MERCHANT_CAL_INV_Y:-0}" -eq 0 ]; then
        echo "$ts Not calibrated — run calibration in Settings > Modules > Merchant"
        return
    fi

    local wid; wid=$(get_window_id)
    if [ -z "$wid" ]; then
        echo "$ts Sober window not found"
        return
    fi

    echo "$ts ─── Using Biome Randomizer ───"
    local prev; prev=$(xdotool getactivewindow 2>/dev/null)
    _use_item_from_inventory "$wid" "biome randomizer"
    [ -n "$prev" ] && [ "$prev" != "$wid" ] && xdotool windowactivate "$prev" 2>/dev/null
    echo "$ts ─── Done ───"
}

_biome_randomizer_toggle() {
    if [[ "$BIOME_RANDOMIZER_ENABLED" == "true" ]]; then
        save_config_value "BIOME_RANDOMIZER_ENABLED" "false"
        echo "[✓] Biome Randomizer disabled"
    else
        save_config_value "BIOME_RANDOMIZER_ENABLED" "true"
        echo "[✓] Biome Randomizer enabled"
    fi
    load_config
    read -p "Press Enter to continue..."
}

_biome_randomizer_set_interval() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║       BIOME RANDOMIZER INTERVAL          ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    local cur="${BIOME_RANDOMIZER_INTERVAL:-2100}"
    echo "Current: ${cur}s (every $(( cur / 60 )) min)"
    echo ""
    read -p "New interval in seconds [2100]: " val
    val="${val:-2100}"
    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 60 ]; then
        save_config_value "BIOME_RANDOMIZER_INTERVAL" "$val"
        echo "[✓] Interval set to ${val}s"
    else
        echo "[!] Invalid value (must be >= 60)"
    fi
    load_config
    read -p "Press Enter to continue..."
}

biome_randomizer_settings_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║        BIOME RANDOMIZER MODULE           ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        if [[ "$BIOME_RANDOMIZER_ENABLED" == "true" ]]; then
            echo "  Status   : ✓ Enabled"
        else
            echo "  Status   : ✗ Disabled"
        fi
        echo "  Interval : ${BIOME_RANDOMIZER_INTERVAL:-2100}s (every $(( ${BIOME_RANDOMIZER_INTERVAL:-2100} / 60 )) min)"
        echo ""
        echo "  Calibration shared with Merchant module."
        echo ""
        echo "1) Toggle Enable/Disable"
        echo "2) Set interval"
        echo "3) Back"
        echo ""
        read -p "Select [1-3]: " choice
        case $choice in
            1) _biome_randomizer_toggle ;;
            2) _biome_randomizer_set_interval ;;
            3) return ;;
            *) read ;;
        esac
    done
}
