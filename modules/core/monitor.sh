# ================================================================
#   modules/monitor.sh - Main monitoring loop
# ================================================================

# ┌─────────────────────────────────────────┐
# │            ACTION QUEUE                 │
# └─────────────────────────────────────────┘
#
# Modules call action_queue_push "name" when their timer fires.
# The main loop calls action_queue_run once per iteration — only
# one inventory action runs at a time, the rest wait their turn.

declare -ga _ACTION_QUEUE=()

action_queue_push() {
    local action="$1"
    for item in "${_ACTION_QUEUE[@]}"; do
        [ "$item" = "$action" ] && return   # already queued
    done
    _ACTION_QUEUE+=("$action")
    echo "[$(date '+%H:%M:%S')] [Queue] Queued: $action (depth: ${#_ACTION_QUEUE[@]})"
}

action_queue_run() {
    local log_file="$1"
    [ ${#_ACTION_QUEUE[@]} -eq 0 ] && return
    local action="${_ACTION_QUEUE[0]}"
    _ACTION_QUEUE=("${_ACTION_QUEUE[@]:1}")
    echo "[$(date '+%H:%M:%S')] [Queue] Running: $action"
    case "$action" in
        merchant)           _merchant_run "$log_file" ;;
        strange_controller) _strange_controller_run ;;
        biome_randomizer)   _biome_randomizer_run ;;
        custom_item:*)      _custom_item_run "${action#custom_item:}" ;;
    esac
}

_LIVE_RELOAD=false

ticks_run() {
    local log_file="$1"
    local now; now=$(date +%s)

    if $_LIVE_RELOAD; then
        _LIVE_RELOAD=false
        [ -f /tmp/sols_rng_live.conf ] && source /tmp/sols_rng_live.conf
        echo "[$(date '+%H:%M:%S')] [Live] Module settings reloaded"
    fi

    antiafk_tick

    # Defensive: source config without `declare -ga CUSTOM_USE_ITEMS=()` would
    # leave it as a plain string, breaking `${ARR[@]}` below.
    if ! declare -p CUSTOM_USE_ITEMS &>/dev/null; then
        declare -ga CUSTOM_USE_ITEMS=()
    fi

    if [[ "$MERCHANT_ENABLED" == "true" ]]; then
        (( now - MERCHANT_LAST < MERCHANT_INTERVAL )) || { MERCHANT_LAST=$now; action_queue_push "merchant"; }
    fi

    if [[ "$STRANGE_CONTROLLER_ENABLED" == "true" ]]; then
        (( now - STRANGE_CONTROLLER_LAST < ${STRANGE_CONTROLLER_INTERVAL:-1200} )) || { STRANGE_CONTROLLER_LAST=$now; action_queue_push "strange_controller"; }
    fi

    if [[ "$BIOME_RANDOMIZER_ENABLED" == "true" ]]; then
        (( now - BIOME_RANDOMIZER_LAST < ${BIOME_RANDOMIZER_INTERVAL:-2100} )) || { BIOME_RANDOMIZER_LAST=$now; action_queue_push "biome_randomizer"; }
    fi

    for entry in "${CUSTOM_USE_ITEMS[@]:-}"; do
        [ -z "$entry" ] && continue
        local name="${entry%%|*}"
        local interval="${entry##*|}"
        local key="${name// /_}"
        local last="${_CUSTOM_ITEM_LAST[$key]:-0}"
        (( now - last < ${interval:-300} )) || { _CUSTOM_ITEM_LAST["$key"]=$now; action_queue_push "custom_item:${name}"; }
    done

    action_queue_run "$log_file"
}

# ┌─────────────────────────────────────────┐
# │           START MONITORING              │
# └─────────────────────────────────────────┘

start_monitoring() {
    echo "╔══════════════════════════════════════════╗"
    echo "║   Aluen's Macro v${VERSION}                     ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    # Dependency check
    command -v curl &>/dev/null || {
        echo "[ERROR] curl not found: sudo apt install curl"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    }

    if $ANTIAFK_ENABLED; then
        if command -v xdotool &>/dev/null; then
            echo "[✓] AntiAFK enabled (every ${ANTIAFK_INTERVAL}s)"
        else
            echo "[!] xdotool not found — AntiAFK disabled"
            echo "    sudo apt install xdotool"
            ANTIAFK_ENABLED=false
        fi
    else
        echo "[i] AntiAFK disabled"
    fi

    # If any module using key simulation is enabled — do a test jump to trigger
    # the Remote Control permission prompt before monitoring begins
    if $ANTIAFK_ENABLED || ${MERCHANT_ENABLED:-false} || ${STRANGE_CONTROLLER_ENABLED:-false} || ${BIOME_RANDOMIZER_ENABLED:-false} || [ "${#CUSTOM_USE_ITEMS[@]}" -gt 0 ]; then
        if command -v xdotool &>/dev/null; then
            echo "[*] Requesting remote control permission..."
            xdotool key space 2>/dev/null
            sleep 0.3
            echo "[✓] Remote control permission requested"
        fi
    fi

    # Config validation
    if ! validate_webhook_url; then
        echo "[!] ERROR: Webhook URL is not set or invalid!"
        echo "    Go to Settings and enter a valid Discord Webhook URL"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    fi

    if ! validate_server_invite; then
        echo "[!] ERROR: Server Invite is not set or invalid!"
        echo "    Go to Settings and enter the Sol's RNG server link"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    fi

    # Send startup notification
    echo "[*] Sending startup notification..."
    send_startup_notification
    echo ""

    # Find log
    echo "[*] Looking for Sober log..."
    local log_file=""
    local attempts=0
    while [ -z "$log_file" ] && [ $attempts -lt 12 ]; do
        log_file=$(find_latest_log)
        if [ -z "$log_file" ]; then
            echo "[!] Log not found. Launch Sol's RNG via Sober... (attempt $((attempts+1))/12)"
            sleep 5
            ((attempts++))
        fi
    done

    if [ -z "$log_file" ]; then
        echo "[ERROR] Could not find Sober log file after 60 seconds"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    fi

    echo "[✓] Log: $log_file"
    echo "[✓] Monitoring started. Waiting for biomes..."
    echo ""

    local current_biome=""
    # First tick fires immediately on startup.
    ANTIAFK_LAST=0

    # Strange Controller, Biome Randomizer and custom items fire 10 seconds after start.
    local _now; _now=$(date +%s)
    STRANGE_CONTROLLER_LAST=$(( _now - ${STRANGE_CONTROLLER_INTERVAL:-1200} + 10 ))
    BIOME_RANDOMIZER_LAST=$(( _now - ${BIOME_RANDOMIZER_INTERVAL:-2100} + 10 ))
    custom_items_init

    # FIFO for line passing
    local fifo
    fifo=$(mktemp -u /tmp/sols_rng_XXXXXX)
    mkfifo "$fifo"

    local tail_pid=""
    local monitoring_active=true
    local cleanup_done=false

    start_tail() {
        [ -n "$tail_pid" ] && kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null
        tail -F -n 0 "$log_file" >> "$fifo" 2>/dev/null &
        tail_pid=$!
    }

    cleanup() {
        $cleanup_done && return
        cleanup_done=true

        monitoring_active=false

        # Release any keys that may be held (e.g. merchant walk-away)
        if command -v xdotool &>/dev/null; then
            xdotool keyup s 2>/dev/null
            xdotool keyup space 2>/dev/null
        fi

        # Kill any child xdotool/tail processes still running
        pkill -P $$ 2>/dev/null || true

        [ -n "$tail_pid" ] && kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null

        exec 3>&- 2>/dev/null
        exec 3<&- 2>/dev/null
        rm -f "$fifo" 2>/dev/null

        echo ""
        echo "[*] Stopping monitoring..."
        local session_end; session_end=$(date +%s)
        local session_duration=$(( session_end - session_start ))
        echo "[*] Sending stop notification..."
        send_stop_notification "$session_duration"
        echo "[✓] Monitoring stopped"
        echo ""
    }

    # Trap both Ctrl+C (INT) and SIGTERM (sent by GUI stop button)
    # SIGUSR1 = live reload of module toggles from GUI
    #
    # `read -t 2` on a FIFO blocks even when a signal arrives — Bash does
    # not interrupt built-in `read` on signal delivery. To make Stop instant,
    # we run the reader in a background child. SIGALRM interrupts the
    # blocking read inside the child and it exits with rc=142, freeing the
    # parent immediately.
    _reader_pid=""
    _stop_reader() {
        if [ -n "$_reader_pid" ] && kill -0 "$_reader_pid" 2>/dev/null; then
            kill -ALRM "$_reader_pid" 2>/dev/null
            # Give the child up to ~500ms to exit cleanly.
            local i=0
            while [ $i -lt 10 ] && kill -0 "$_reader_pid" 2>/dev/null; do
                sleep 0.05
                i=$((i + 1))
            done
            kill -9 "$_reader_pid" 2>/dev/null
            wait "$_reader_pid" 2>/dev/null
        fi
        _reader_pid=""
    }
    cleanup() {
        $cleanup_done && return
        cleanup_done=true

        monitoring_active=false
        _stop_reader

        # Release any keys that may be held (e.g. merchant walk-away)
        if command -v xdotool &>/dev/null; then
            xdotool keyup s 2>/dev/null
            xdotool keyup space 2>/dev/null
        fi

        # Kill any child xdotool/tail processes still running
        pkill -P $$ 2>/dev/null || true

        [ -n "$tail_pid" ] && kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null

        exec 3>&- 2>/dev/null
        exec 3<&- 2>/dev/null
        rm -f "$fifo" 2>/dev/null
        rm -f "${fifo}.line" 2>/dev/null

        echo ""
        echo "[*] Stopping monitoring..."
        local session_end; session_end=$(date +%s)
        local session_duration=$(( session_end - session_start ))
        echo "[*] Sending stop notification..."
        send_stop_notification "$session_duration"
        echo "[✓] Monitoring stopped"
        echo ""
    }

    trap cleanup INT TERM
    trap '_LIVE_RELOAD=true' USR1

    start_tail
    exec 3<> "$fifo"

    # Record session start time
    local session_start=$(date +%s)

    # _read_one_line: read one line from fd $1 with 2s timeout, write to stdout.
    # SIGALRM (sent by cleanup) interrupts the blocking read — child exits 142.
    _read_one_line() {
        local _fd="$1"
        local _line=""
        IFS= read -r -t 2 -u "$_fd" _line
        local _rc=$?
        [ $_rc -eq 0 ] && printf '%s\n' "$_line"
        return $_rc
    }

    while $monitoring_active; do
        local line=""

        # Run the reader in a background subshell. stdout is redirected to a
        # temp file so the parent can pick it up after wait returns.
        _reader_pid=""
        : > "${fifo}.line"
        _read_one_line 3 > "${fifo}.line" 2>/dev/null &
        _reader_pid=$!
        # wait blocks until the reader exits (line read → rc=0, timeout → rc=142,
        # or SIGALRM-interrupted read → rc=142). In all cases we drop back here
        # immediately — no 2-second lag on Stop.
        wait "$_reader_pid" 2>/dev/null
        _reader_pid=""

        if [ -s "${fifo}.line" ]; then
            line=$(cat "${fifo}.line")
        fi

        if [ -n "$line" ]; then
            local raw_biome
            raw_biome=$(parse_biome_from_line "$line")
            [ -z "$raw_biome" ] && continue

            local biome
            biome=$(normalize_biome "$raw_biome")

            if [ "$biome" != "$current_biome" ]; then
                if [ -n "$current_biome" ]; then
                    echo "[$(date '+%H:%M:%S')] << Biome ended: $current_biome"
                    should_notify "$current_biome" && send_webhook "$current_biome" "ended"
                fi
                echo "[$(date '+%H:%M:%S')] >> Biome started: $biome"
                should_notify "$biome" && send_webhook "$biome" "started"
                current_biome="$biome"
            fi
        fi

        ticks_run "$log_file"

        # Switch to a new log only if the current one is deleted (session ended)
        if ! [ -f "$log_file" ]; then
            local new_log
            new_log=$(find_latest_log)
            if [ -n "$new_log" ]; then
                log_file="$new_log"
                current_biome=""
                start_tail
            fi
        fi
    done

    # Run cleanup (sends stop notification) after loop exits
    cleanup

    # Reset trap
    trap - INT TERM

    exit 0
}
