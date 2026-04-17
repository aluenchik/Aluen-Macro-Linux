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

    
    echo "[$(date '+%H:%M:%S')] $pfx Closing inventory..."
    _mclick "$MERCHANT_CAL_INV_X" "$MERCHANT_CAL_INV_Y"
    sleep 0.4
}

# ┌─────────────────────────────────────────┐
# │         SHARED ITEM-RUN HELPER          │
# └─────────────────────────────────────────┘

_run_item_action() {
    local tag="$1" item_name="$2"
    local ts="[$(date '+%H:%M:%S')] [$tag]"

    if ! command -v xdotool &>/dev/null; then
        echo "$ts xdotool not found"; return
    fi
    if [ "${MERCHANT_CAL_INV_X:-0}" -eq 0 ] && [ "${MERCHANT_CAL_INV_Y:-0}" -eq 0 ]; then
        echo "$ts Not calibrated — run calibration in Settings"; return
    fi
    local wid; wid=$(get_window_id)
    if [ -z "$wid" ]; then
        echo "$ts Sober window not found"; return
    fi

    echo "$ts ─── Using $item_name ───"
    local prev; prev=$(xdotool getactivewindow 2>/dev/null)
    _use_item_from_inventory "$wid" "$item_name"
    [ -n "$prev" ] && [ "$prev" != "$wid" ] && xdotool windowactivate "$prev" 2>/dev/null
    echo "$ts ─── Done ───"
}

# ┌─────────────────────────────────────────┐
# │      STRANGE CONTROLLER / RANDOMIZER    │
# └─────────────────────────────────────────┘

_strange_controller_run() { _run_item_action "StrangeController" "strange controller"; }
_biome_randomizer_run()   { _run_item_action "BiomeRandomizer"   "biome randomizer";  }

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

_custom_item_run() { _run_item_action "Item: $1" "${1,,}"; }
