# ================================================================
#   modules/items.sh - Periodic item use from inventory
# ================================================================
#
# Depends on: merchant.sh loaded first
#   (_mclick, _mkey, _merchant_focus, MERCHANT_CAL_* variables)
# ================================================================

STRANGE_CONTROLLER_LAST=$(date +%s)
BIOME_RANDOMIZER_LAST=$(date +%s)
declare -gA _CUSTOM_ITEM_LAST=()

# ┌─────────────────────────────────────────┐
# │      GENERIC USE-ITEM FROM INVENTORY    │
# └─────────────────────────────────────────┘

# Open inventory → Items tab → search → select → Use → close.
# item_name must be lowercase (avoids Shift events going to the game).
_use_item_from_inventory() {
    local wid="$1"
    local item_name="$2"
    local close_inv="${3:-true}"   # pass "false" to skip closing inventory
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

    if [ "$close_inv" != "false" ]; then
        echo "[$(date '+%H:%M:%S')] $pfx Closing inventory..."
        _mclick "$MERCHANT_CAL_INV_X" "$MERCHANT_CAL_INV_Y"
        sleep 0.4
    fi
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

# ┌─────────────────────────────────────────┐
# │        MERCHANT TELEPORTER              │
# └─────────────────────────────────────────┘

_merchant_teleporter_use() {
    local wid="$1"
    _use_item_from_inventory "$wid" "merchant teleporter" false
}

# ┌─────────────────────────────────────────┐
# │          CUSTOM USE ITEMS               │
# └─────────────────────────────────────────┘

custom_items_init() {
    local now; now=$(date +%s)
    for entry in "${CUSTOM_USE_ITEMS[@]:-}"; do
        [ -z "$entry" ] && continue
        local name="${entry%%|*}"
        local key; key="${name// /_}"
        _CUSTOM_ITEM_LAST["$key"]=$now
    done
}

custom_items_tick() {
    for entry in "${CUSTOM_USE_ITEMS[@]:-}"; do
        [ -z "$entry" ] && continue
        local name="${entry%%|*}"
        local interval="${entry##*|}"
        local key; key="${name// /_}"
        local now; now=$(date +%s)
        local last="${_CUSTOM_ITEM_LAST[$key]:-0}"
        (( now - last < ${interval:-300} )) && continue
        _CUSTOM_ITEM_LAST["$key"]=$now
        action_queue_push "custom_item:${name}"
    done
}

_custom_item_run() {
    local item_name="$1"
    local ts="[$(date '+%H:%M:%S')] [Item: $item_name]"

    if ! command -v xdotool &>/dev/null; then
        echo "$ts xdotool not found"
        return
    fi

    if [ "${MERCHANT_CAL_INV_X:-0}" -eq 0 ] && [ "${MERCHANT_CAL_INV_Y:-0}" -eq 0 ]; then
        echo "$ts Not calibrated — run calibration in Settings"
        return
    fi

    local wid; wid=$(get_window_id)
    if [ -z "$wid" ]; then
        echo "$ts Sober window not found"
        return
    fi

    echo "$ts ─── Using $item_name ───"
    local prev; prev=$(xdotool getactivewindow 2>/dev/null)
    _use_item_from_inventory "$wid" "${item_name,,}"
    [ -n "$prev" ] && [ "$prev" != "$wid" ] && xdotool windowactivate "$prev" 2>/dev/null
    echo "$ts ─── Done ───"
}

