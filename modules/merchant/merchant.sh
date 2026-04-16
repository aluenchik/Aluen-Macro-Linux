# ================================================================
#   modules/merchant.sh - Merchant automation module
# ================================================================

# Resolve own directory if MERCHANT_DIR not set by macro.sh
if [ -z "$MERCHANT_DIR" ]; then
    MERCHANT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

MERCHANT_LAST=$(date +%s)
STRANGE_CONTROLLER_LAST=$(date +%s)
BIOME_RANDOMIZER_LAST=$(date +%s)

# ┌─────────────────────────────────────────┐
# │           SCREENSHOT TOOL               │
# └─────────────────────────────────────────┘

_take_screenshot() {
    local outfile="$1"
    if command -v spectacle &>/dev/null; then
        timeout 8 spectacle -b -f -o "$outfile" 2>/dev/null
        sleep 0.3
        [ -s "$outfile" ] && return 0
    fi
    if command -v grim &>/dev/null; then
        timeout 5 grim "$outfile" 2>/dev/null && return 0
    fi
    if command -v scrot &>/dev/null; then
        timeout 5 scrot "$outfile" 2>/dev/null && return 0
    fi
    return 1
}

# ┌─────────────────────────────────────────┐
# │        DISCORD NOTIFICATION             │
# └─────────────────────────────────────────┘

_merchant_send_discord() {
    local screenshot="$1"
    local note="$2"
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local footer_text; footer_text=$(get_footer_text)
    local escaped_note; escaped_note=$(escape_json_string "$note")

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "🏪 Merchant Detected!",
    "description": "${escaped_note}\n\nJoin my Discord:\nhttps://discord.gg/nQFyFsRPaG",
    "color": 16766720,
    "footer": {"text": "${footer_text}"},
    "timestamp": "${timestamp}",
    "image": {"url": "attachment://merchant.png"}
  }]
}
EOF
)

    local http_code
    if [ -f "$screenshot" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -F "payload_json=${payload}" \
            -F "file=@${screenshot};filename=merchant.png" \
            "$WEBHOOK_URL" 2>/dev/null)
    else
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$WEBHOOK_URL" 2>/dev/null)
    fi

    if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
        echo "[$(date '+%H:%M:%S')] [Merchant] Screenshot sent to Discord (HTTP $http_code)"
    else
        echo "[$(date '+%H:%M:%S')] [Merchant] Discord error (HTTP $http_code)"
    fi
}

# ┌─────────────────────────────────────────┐
# │           XDOTOOL HELPERS               │
# └─────────────────────────────────────────┘

# Move mouse and click at absolute screen coordinates.
_mclick() {
    local x="$1" y="$2"
    xdotool mousemove --sync "$x" "$y" 2>/dev/null
    xdotool click 1 2>/dev/null
    sleep 0.15
}

_mkey() {
    local wid="$1" key="$2"
    xdotool key --window "$wid" "$key" 2>/dev/null
}

# Bring Sober window to focus.
_merchant_focus() {
    local wid="$1"
    xdotool windowactivate --sync "$wid" 2>/dev/null
    sleep 0.5
}

# ┌─────────────────────────────────────────┐
# │        USE TELEPORTER FLOW              │
# └─────────────────────────────────────────┘

_merchant_use_teleporter() {
    local wid="$1"
    local ts="[$(date '+%H:%M:%S')] [Merchant]"

    # ── Steps 1-5: Use Merchant Teleporter (via items module) ─────
    echo "$ts Using Merchant Teleporter..."
    _merchant_teleporter_use "$wid"

    # ── Wait for teleport ──────────────────────────────────────────
    sleep 1

    # ── Step 6: Interact with NPC ─────────────────────────────────
    echo "$ts Pressing E to interact with NPC..."
    _mkey "$wid" e
    sleep 0.6

    # ── Step 7: Click through dialogue ────────────────────────────
    echo "$ts Clicking through dialogue..."
    for _ in {1..5}; do
        _mclick "$MERCHANT_CAL_DIALOG_X" "$MERCHANT_CAL_DIALOG_Y"
        sleep 0.3
    done
    sleep 0.3

    # ── Step 8: Open shop ─────────────────────────────────────────
    echo "$ts Clicking Shop button..."
    _mclick "$MERCHANT_CAL_SHOP_X" "$MERCHANT_CAL_SHOP_Y"
    sleep 1.0
}

# ┌─────────────────────────────────────────┐
# │           AUTO-BUY ITEMS                │
# └─────────────────────────────────────────┘

DETECTED_MERCHANT_NAME="Unknown"

# Step 1 — identify merchant from screenshot (no items passed)
_merchant_detect() {
    local shot="$1"
    local ts="[$(date '+%H:%M:%S')] [Merchant]"
    DETECTED_MERCHANT_NAME="Unknown"

    local line
    line=$(python3 "${MERCHANT_DIR}/shop_ocr.py" "$shot" "$MERCHANT_CAL_BUY_Y" 2>/dev/null \
           | grep "^MERCHANT:" | head -1)
    [[ "$line" == MERCHANT:* ]] && DETECTED_MERCHANT_NAME="${line#MERCHANT:}"
    echo "$ts Merchant: $DETECTED_MERCHANT_NAME"
}

# Step 2 — buy items for the already-detected merchant from screenshot
_merchant_buy_from_shop() {
    local wid="$1"
    local shot="$2"
    local ts="[$(date '+%H:%M:%S')] [Merchant]"

    if [ "${MERCHANT_CAL_BUY_X:-0}" -eq 0 ] && [ "${MERCHANT_CAL_BUY_Y:-0}" -eq 0 ]; then
        echo "$ts Auto-buy: buy button not calibrated, skipping"
        return
    fi

    local -n _buy_items _max_items
    case "$DETECTED_MERCHANT_NAME" in
        Mari)   _buy_items=MARI_BUY_ITEMS; _max_items=MARI_MAX_ITEMS ;;
        Jester) _buy_items=JESTER_BUY_ITEMS; _max_items=JESTER_MAX_ITEMS ;;
        Rin)
            echo "$ts Auto-buy: Rin detected — scan only, skipping buy"
            return
            ;;
        *)
            echo "$ts Auto-buy: merchant not identified, skipping"
            return
            ;;
    esac

    [ ${#_buy_items[@]} -eq 0 ] && {
        echo "$ts Auto-buy: no items configured for $DETECTED_MERCHANT_NAME"
        return
    }

    local results
    results=$(python3 "${MERCHANT_DIR}/shop_ocr.py" "$shot" "$MERCHANT_CAL_BUY_Y" \
              "${_buy_items[@]}" 2>/dev/null | grep -v "^MERCHANT:")

    if [ -z "$results" ]; then
        echo "$ts Auto-buy: no configured items found in shop"
        return
    fi

    while IFS='|' read -r name cx cy; do
        [ -z "$name" ] && continue
        echo "$ts   Buying: $name at ($cx, $cy)"
        _mclick "$cx" "$cy"
        sleep 0.6
        # Set to max if configured for this item
        local _use_max=false
        for _m in "${_max_items[@]:-}"; do
            [ "${_m,,}" = "${name,,}" ] && _use_max=true && break
        done
        if $_use_max && [ "${MERCHANT_CAL_MAX_X:-0}" -ne 0 ]; then
            echo "$ts   Setting to max..."
            _mclick "$MERCHANT_CAL_MAX_X" "$MERCHANT_CAL_MAX_Y"
            sleep 0.3
        fi
        _mclick "$MERCHANT_CAL_BUY_X" "$MERCHANT_CAL_BUY_Y"
        echo "$ts   Purchased: $name"
        sleep 0.5
    done <<< "$results"
}

# ┌─────────────────────────────────────────┐
# │              MAIN TICK                  │
# └─────────────────────────────────────────┘

merchant_tick() {
    local log_file="$1"
    [[ "$MERCHANT_ENABLED" == "true" ]] || return
    local now; now=$(date +%s)
    (( now - MERCHANT_LAST < MERCHANT_INTERVAL )) && return
    MERCHANT_LAST=$now
    action_queue_push "merchant"
}

_merchant_run() {
    local log_file="$1"
    local ts="[$(date '+%H:%M:%S')] [Merchant]"

    if ! command -v xdotool &>/dev/null; then
        echo "$ts xdotool not found — module disabled"
        return
    fi

    if [ "${MERCHANT_CAL_INV_X:-0}" -eq 0 ] && [ "${MERCHANT_CAL_INV_Y:-0}" -eq 0 ]; then
        echo "$ts Not calibrated — run calibration in Settings > Modules > Merchant"
        return
    fi

    local wid; wid=$(get_window_id)
    if [ -z "$wid" ]; then
        echo "$ts Sober window not found, skipping"
        return
    fi

    echo "$ts ─── Merchant check started ───"

    local prev; prev=$(xdotool getactivewindow 2>/dev/null)
    _merchant_focus "$wid"

    local pre_lines; pre_lines=$(wc -l < "$log_file" 2>/dev/null || echo 0)

    _merchant_use_teleporter "$wid"

    echo "$ts Waiting for shop to load..."
    local shop_ok=false
    local elapsed=0
    while [ $elapsed -lt 8 ]; do
        sleep 1
        (( elapsed++ ))
        local new_lines
        new_lines=$(tail -n +"$((pre_lines + 1))" "$log_file" 2>/dev/null)
        if echo "$new_lines" | grep -q "merchant npc"; then
            shop_ok=true
            break
        fi
    done

    if $shop_ok; then
        echo "$ts Shop loaded!"
        local shot="/tmp/merchant_$(date +%s).png"

        if ! command -v tesseract &>/dev/null; then
            echo "$ts tesseract not found — skipping detection and auto-buy"
            _merchant_send_discord "" "**Merchant appeared!**"
        elif ! _take_screenshot "$shot"; then
            echo "$ts Screenshot failed — skipping detection and auto-buy"
            _merchant_send_discord "" "**Merchant appeared!** (no screenshot)"
        else
            # Step 1: identify merchant
            _merchant_detect "$shot"
            # Step 2: buy items (only if merchant known)
            _merchant_buy_from_shop "$wid" "$shot"
            _merchant_send_discord "$shot" "**Merchant: ${DETECTED_MERCHANT_NAME}** has appeared!"
            rm -f "$shot"
        fi

        echo "$ts Walking away (holding S)..."
        xdotool keydown --window "$wid" --clearmodifiers s 2>/dev/null
        sleep 4
        xdotool keyup --window "$wid" s 2>/dev/null
    else
        echo "$ts No merchant found (timeout — merchant may not be active)"
        echo "$ts Closing inventory..."
        _mclick "$MERCHANT_CAL_INV_X" "$MERCHANT_CAL_INV_Y"
        sleep 0.4
    fi

    [ -n "$prev" ] && [ "$prev" != "$wid" ] && xdotool windowactivate "$prev" 2>/dev/null

    echo "$ts ─── Done ───"
}


