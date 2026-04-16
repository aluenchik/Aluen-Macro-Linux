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
# Caller must ensure the target window is raised & focused first.
_mclick() {
    local x="$1" y="$2"
    xdotool mousemove --sync "$x" "$y" 2>/dev/null
    sleep 0.15
    xdotool click --clearmodifiers 1 2>/dev/null
    sleep 0.05
}

_mkey() {
    local wid="$1" key="$2"
    xdotool key --window "$wid" --clearmodifiers "$key" 2>/dev/null
}

# Bring Sober window to the top and focus it.
_merchant_focus() {
    local wid="$1"
    xdotool windowraise "$wid" 2>/dev/null
    sleep 0.15
    xdotool windowactivate --sync "$wid" 2>/dev/null
    sleep 0.2
    xdotool windowfocus --sync "$wid" 2>/dev/null
    sleep 0.35
}

# ┌─────────────────────────────────────────┐
# │        USE TELEPORTER FLOW              │
# └─────────────────────────────────────────┘

_merchant_use_teleporter() {
    local wid="$1"
    local ts="[$(date '+%H:%M:%S')] [Merchant]"

    # Raise Sober and focus it before doing anything
    _merchant_focus "$wid"

    # ── Step 1: Open inventory ──────────────────────────
    echo "$ts Opening inventory..."
    _mclick "$MERCHANT_CAL_INV_X" "$MERCHANT_CAL_INV_Y"
    sleep 1.5   # wait for inventory panel to animate open

    # ── Step 2: Items tab ──────────────────────────────
    echo "$ts Clicking Items tab..."
    _mclick "$MERCHANT_CAL_ITEMS_TAB_X" "$MERCHANT_CAL_ITEMS_TAB_Y"
    sleep 0.8

    # ── Step 3: Search box → type item name ───────────
    echo "$ts Clicking search box..."
    _mclick "$MERCHANT_CAL_SEARCH_X" "$MERCHANT_CAL_SEARCH_Y"
    sleep 0.5

    # Clear any previous query, then type — lowercase avoids
    # accidental Shift events going to the game
    xdotool key --window "$wid" --clearmodifiers ctrl+a 2>/dev/null
    sleep 0.15
    xdotool type --window "$wid" --clearmodifiers --delay 60 "merchant teleporter" 2>/dev/null
    sleep 0.9

    # ── Step 4: Select item from results ──────────────
    echo "$ts Selecting item..."
    _mclick "$MERCHANT_CAL_ITEM_X" "$MERCHANT_CAL_ITEM_Y"
    sleep 0.5

    # ── Step 5: Use button → teleport ─────────────────
    echo "$ts Pressing Use..."
    _mclick "$MERCHANT_CAL_USE_X" "$MERCHANT_CAL_USE_Y"
    sleep 3.5   # wait for teleport to complete

    # Re-focus after teleport (game may have stolen/lost focus)
    _merchant_focus "$wid"

    # ── Step 6: Interact with NPC ─────────────────────
    echo "$ts Pressing E to interact with NPC..."
    _mkey "$wid" e
    sleep 1.2

    # ── Step 7: Click through dialogue ────────────────
    echo "$ts Clicking through dialogue..."
    for _ in {1..5}; do
        _mclick "$MERCHANT_CAL_DIALOG_X" "$MERCHANT_CAL_DIALOG_Y"
        sleep 0.55
    done
    sleep 0.8

    # ── Step 8: Open shop ─────────────────────────────
    echo "$ts Clicking Shop button..."
    _mclick "$MERCHANT_CAL_SHOP_X" "$MERCHANT_CAL_SHOP_Y"
    sleep 2.0
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

    local -n _buy_items
    case "$DETECTED_MERCHANT_NAME" in
        Mari)   _buy_items=MARI_BUY_ITEMS ;;
        Jester) _buy_items=JESTER_BUY_ITEMS ;;
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

    # Re-focus Sober — OCR took several seconds, window may have lost focus
    _merchant_focus "$wid"

    while IFS='|' read -r name cx cy; do
        [ -z "$name" ] && continue
        echo "$ts   Buying: $name at ($cx, $cy)"
        _mclick "$cx" "$cy"
        sleep 0.6
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
            rm -f "$shot"
            _merchant_send_discord "" "**Merchant: ${DETECTED_MERCHANT_NAME}** has appeared!"
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

# ┌─────────────────────────────────────────┐
# │           CALIBRATION                   │
# └─────────────────────────────────────────┘

merchant_calibrate() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║       MERCHANT CALIBRATION               ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    if ! command -v xdotool &>/dev/null; then
        echo "[!] xdotool not found: sudo pacman -S xdotool"
        read -p "Press Enter..."; return
    fi

    local inv_x=0 inv_y=0
    local items_tab_x=0 items_tab_y=0
    local search_x=0 search_y=0
    local item_x=0 item_y=0
    local use_x=0 use_y=0
    local shop_x=0 shop_y=0
    local dialog_x=0 dialog_y=0
    local buy_x=0 buy_y=0

    _capture_mouse() {
        local label="$1"
        echo ""
        echo "  >>> ${label}"
        echo "      Нажми Enter, затем за 3 секунды наведи мышь на кнопку."
        read -p "      Enter: " </dev/tty
        local i
        for i in 3 2 1; do
            printf "\r      Захват через %s..." "$i"
            sleep 1
        done
        local pos
        pos=$(xdotool getmouselocation 2>/dev/null)
        MCAP_X=$(echo "$pos" | grep -oP 'x:\K[0-9]+')
        MCAP_Y=$(echo "$pos" | grep -oP 'y:\K[0-9]+')
        echo -e "\r      Сохранено: ($MCAP_X, $MCAP_Y)   "
    }

    echo "=== Шаг 1/3 — Обычный вид игры ==="
    echo ""
    echo "Убедись что инвентарь закрыт."
    _capture_mouse "кнопку инвентаря (рюкзак)"
    inv_x=$MCAP_X; inv_y=$MCAP_Y

    echo ""
    echo "=== Шаг 2/3 — Инвентарь открыт ==="
    echo ""
    echo "В игре:"
    echo "  1. Открой инвентарь → вкладка Items"
    echo "  2. Найди Merchant Teleporter"
    echo "  3. Кликни на предмет (чтобы появилась кнопка Use)"
    _capture_mouse "вкладку Items"
    items_tab_x=$MCAP_X; items_tab_y=$MCAP_Y

    _capture_mouse "поле поиска (Search)"
    search_x=$MCAP_X; search_y=$MCAP_Y

    _capture_mouse "Merchant Teleporter (в списке)"
    item_x=$MCAP_X; item_y=$MCAP_Y

    _capture_mouse "кнопку Use"
    use_x=$MCAP_X; use_y=$MCAP_Y

    echo ""
    echo "=== Шаг 3/3 — Рядом с мерчантом ==="
    echo ""
    echo "В игре:"
    echo "  1. Телепортируйся к мерчанту вручную"
    echo "  2. Нажми E рядом с NPC — появятся кнопки диалога и Shop"
    _capture_mouse "кнопку пропуска диалога (стрелка/Next)"
    dialog_x=$MCAP_X; dialog_y=$MCAP_Y

    _capture_mouse "кнопку Shop"
    shop_x=$MCAP_X; shop_y=$MCAP_Y

    _capture_mouse "кнопку Purchase (кнопка покупки внутри магазина)"
    buy_x=$MCAP_X; buy_y=$MCAP_Y

    save_config_value "MERCHANT_CAL_INV_X"       "$inv_x"
    save_config_value "MERCHANT_CAL_INV_Y"       "$inv_y"
    save_config_value "MERCHANT_CAL_ITEMS_TAB_X" "$items_tab_x"
    save_config_value "MERCHANT_CAL_ITEMS_TAB_Y" "$items_tab_y"
    save_config_value "MERCHANT_CAL_SEARCH_X"    "$search_x"
    save_config_value "MERCHANT_CAL_SEARCH_Y"    "$search_y"
    save_config_value "MERCHANT_CAL_ITEM_X"      "$item_x"
    save_config_value "MERCHANT_CAL_ITEM_Y"      "$item_y"
    save_config_value "MERCHANT_CAL_USE_X"       "$use_x"
    save_config_value "MERCHANT_CAL_USE_Y"       "$use_y"
    save_config_value "MERCHANT_CAL_SHOP_X"      "$shop_x"
    save_config_value "MERCHANT_CAL_SHOP_Y"      "$shop_y"
    save_config_value "MERCHANT_CAL_DIALOG_X"    "$dialog_x"
    save_config_value "MERCHANT_CAL_DIALOG_Y"    "$dialog_y"
    save_config_value "MERCHANT_CAL_BUY_X"       "$buy_x"
    save_config_value "MERCHANT_CAL_BUY_Y"       "$buy_y"

    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║     CALIBRATION COMPLETE ✓               ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "  Inv button  : ($inv_x, $inv_y)"
    echo "  Items tab   : ($items_tab_x, $items_tab_y)"
    echo "  Search box  : ($search_x, $search_y)"
    echo "  Item        : ($item_x, $item_y)"
    echo "  Use button  : ($use_x, $use_y)"
    echo "  Dialogue    : ($dialog_x, $dialog_y)"
    echo "  Shop button : ($shop_x, $shop_y)"
    echo "  Buy button  : ($buy_x, $buy_y)"
    echo ""
    read -p "Press Enter to continue..."
}

# ┌─────────────────────────────────────────┐
# │          SETTINGS SUBMENU               │
# └─────────────────────────────────────────┘

_merchant_toggle() {
    if [[ "$MERCHANT_ENABLED" == "true" ]]; then
        save_config_value "MERCHANT_ENABLED" "false"
        echo "[✓] Merchant module disabled"
    else
        save_config_value "MERCHANT_ENABLED" "true"
        echo "[✓] Merchant module enabled"
    fi
    load_config
    read -p "Press Enter to continue..."
}

_merchant_set_interval() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║       MERCHANT CHECK INTERVAL            ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Current: ${MERCHANT_INTERVAL}s (every $(( MERCHANT_INTERVAL / 60 )) min)"
    echo ""
    echo "Merchant spawns ~every 10 min, lasts 2.5 min."
    echo "Recommended: 300s (5 min)"
    echo ""
    read -p "New interval in seconds [300]: " val
    val="${val:-300}"
    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 60 ]; then
        save_config_value "MERCHANT_INTERVAL" "$val"
        echo "[✓] Interval set to ${val}s"
    else
        echo "[!] Invalid value (must be >= 60)"
    fi
    load_config
    read -p "Press Enter to continue..."
}

# Known item lists per merchant
_MARI_ALL_ITEMS=(
    "Lucky Potion"
    "Lucky Potion L"
    "Lucky Potion XL"
    "Speed Potion"
    "Speed Potion L"
    "Speed Potion XL"
    "Mixed Potion"
    "Fortune Spoid I"
    "Fortune Spoid II"
    "Fortune Spoid III"
    "Gear A"
    "Gear B"
    "Lucky Penny"
    "Void Coin"
)

_JESTER_ALL_ITEMS=(
    "Lucky Potion"
    "Speed Potion"
    "Random Potion Sack"
    "Stella's Star"
    "Rune of Wind"
    "Rune of Frost"
    "Rune of Rainstorm"
    "Rune of Hell"
    "Rune of Galaxy"
    "Rune of Corruption"
    "Rune of Nothing"
    "Rune of Everything"
    "Strange Potion I"
    "Strange Potion II"
    "Stella's Candle"
    "Oblivion Potion"
    "Potion of Bound"
    "Merchant Tracker"
    "Heavenly Potion"
)


# Toggle menu for one merchant's buy list.
# Args: label  config_key  all_items_var
_toggle_buy_menu() {
    local label="$1"
    local config_key="$2"
    local -n _all="$3"
    local -n _selected="$config_key"

    # Build index-based enabled array
    local -a en=()
    local i
    for (( i=0; i<${#_all[@]}; i++ )); do
        en[$i]=0
        for sel in "${_selected[@]}"; do
            [[ "${sel,,}" == "${_all[$i],,}" ]] && en[$i]=1 && break
        done
    done

    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        printf  "║   AUTO-BUY: %-29s║\n" "$label"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        for (( i=0; i<${#_all[@]}; i++ )); do
            if [ "${en[$i]}" -eq 1 ]; then
                printf "  %2d) [✓] %s\n" "$(( i+1 ))" "${_all[$i]}"
            else
                printf "  %2d) [ ] %s\n" "$(( i+1 ))" "${_all[$i]}"
            fi
        done
        echo ""
        echo "   0) Save & Back"
        echo ""
        read -p "Toggle item number (0 to save): " choice

        if [ "$choice" = "0" ]; then
            local new_items=()
            for (( i=0; i<${#_all[@]}; i++ )); do
                [ "${en[$i]}" -eq 1 ] && new_items+=("${_all[$i]}")
            done
            local arr_str=""
            for item in "${new_items[@]}"; do
                arr_str+="\"${item}\" "
            done
            arr_str="${arr_str% }"
            if grep -q "^${config_key}=" "$CONFIG_FILE" 2>/dev/null; then
                sed -i "s|^${config_key}=.*|${config_key}=(${arr_str})|" "$CONFIG_FILE"
            else
                echo "${config_key}=(${arr_str})" >> "$CONFIG_FILE"
            fi
            load_config
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#_all[@]}" ]; then
            local idx=$(( choice - 1 ))
            [ "${en[$idx]}" -eq 1 ] && en[$idx]=0 || en[$idx]=1
        fi
    done
}

_merchant_configure_buy() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║           AUTO-BUY ITEMS                 ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "1) Mari   (${#MARI_BUY_ITEMS[@]} selected)"
        echo "2) Jester (${#JESTER_BUY_ITEMS[@]} selected)"
        echo "3) Back"
        echo ""
        read -p "Select [1-3]: " choice
        case $choice in
            1) _toggle_buy_menu "Mari"   "MARI_BUY_ITEMS"   _MARI_ALL_ITEMS ;;
            2) _toggle_buy_menu "Jester" "JESTER_BUY_ITEMS" _JESTER_ALL_ITEMS ;;
            3) return ;;
            *) read ;;
        esac
    done
}

_merchant_reset_calibration() {
    save_config_value "MERCHANT_CAL_INV_X"       "29"
    save_config_value "MERCHANT_CAL_INV_Y"       "516"
    save_config_value "MERCHANT_CAL_ITEMS_TAB_X" "1258"
    save_config_value "MERCHANT_CAL_ITEMS_TAB_Y" "347"
    save_config_value "MERCHANT_CAL_SEARCH_X"    "1002"
    save_config_value "MERCHANT_CAL_SEARCH_Y"    "386"
    save_config_value "MERCHANT_CAL_ITEM_X"      "841"
    save_config_value "MERCHANT_CAL_ITEM_Y"      "484"
    save_config_value "MERCHANT_CAL_USE_X"       "682"
    save_config_value "MERCHANT_CAL_USE_Y"       "591"
    save_config_value "MERCHANT_CAL_SHOP_X"      "637"
    save_config_value "MERCHANT_CAL_SHOP_Y"      "933"
    save_config_value "MERCHANT_CAL_DIALOG_X"    "792"
    save_config_value "MERCHANT_CAL_DIALOG_Y"    "861"
    save_config_value "MERCHANT_CAL_BUY_X"       "1122"
    save_config_value "MERCHANT_CAL_BUY_Y"       "667"
    echo "[✓] Calibration reset to 1920x1080 defaults"
    read -p "Press Enter to continue..."
}

merchant_settings_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════╗"
        echo "║         MERCHANT MODULE                  ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""

        if [[ "$MERCHANT_ENABLED" == "true" ]]; then
            echo "  Status     : ✓ Enabled"
        else
            echo "  Status     : ✗ Disabled"
        fi
        echo "  Interval   : ${MERCHANT_INTERVAL:-300}s (every $(( ${MERCHANT_INTERVAL:-300} / 60 )) min)"

        if [ "${MERCHANT_CAL_INV_X:-0}" -gt 0 ] || [ "${MERCHANT_CAL_INV_Y:-0}" -gt 0 ]; then
            echo "  Calibrated : ✓ Yes"
        else
            echo "  Calibrated : ✗ No"
        fi

        echo "  Auto-buy   : Mari: ${#MARI_BUY_ITEMS[@]} item(s) | Jester: ${#JESTER_BUY_ITEMS[@]} item(s)"
        echo ""
        echo "1) Toggle Enable/Disable"
        echo "2) Set check interval"
        echo "3) Run calibration wizard"
        echo "4) Reset calibration to defaults (1920x1080)"
        echo "5) Configure auto-buy items"
        echo "6) Back"
        echo ""
        read -p "Select [1-6]: " choice

        case $choice in
            1) _merchant_toggle ;;
            2) _merchant_set_interval ;;
            3) merchant_calibrate; load_config ;;
            4) _merchant_reset_calibration; load_config ;;
            5) _merchant_configure_buy ;;
            6) return ;;
            *) read ;;
        esac
    done
}
