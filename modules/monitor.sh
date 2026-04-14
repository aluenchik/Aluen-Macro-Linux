# ================================================================
#   modules/monitor.sh - Main monitoring loop
# ================================================================

# ┌─────────────────────────────────────────┐
# │           START MONITORING              │
# └─────────────────────────────────────────┘

start_monitoring() {
    clear
    echo "╔══════════════════════════════════════════╗"
    echo "║   Sol's RNG Biome Macro v${VERSION}             ║"
    echo "║   Linux (Wayland) + Sober                ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Press Ctrl+C to stop"
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
            echo "    sudo pacman -S xdotool"
            ANTIAFK_ENABLED=false
        fi
    else
        echo "[i] AntiAFK disabled"
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
    # First tick fires after 30s so the user can quickly confirm AntiAFK works,
    # then normal ANTIAFK_INTERVAL takes over.
    ANTIAFK_LAST=$(( $(date +%s) - ANTIAFK_INTERVAL + 30 ))

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
        [ -n "$tail_pid" ] && kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null

        exec 3>&- 2>/dev/null
        exec 3<&- 2>/dev/null
        rm -f "$fifo" 2>/dev/null
    }

    # Set trap for Ctrl+C
    trap cleanup INT

    start_tail
    exec 3<> "$fifo"

    # Record session start time
    local session_start=$(date +%s)

    while $monitoring_active; do
        if IFS= read -r -t 2 line <&3; then
            [ -z "$line" ] && continue

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

        antiafk_tick

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

    # Run cleanup after loop exits
    cleanup

    # Reset trap
    trap - INT

    echo ""
    echo "[*] Stopping monitoring..."

    # Calculate session duration
    local session_end; session_end=$(date +%s)
    local session_duration=$(( session_end - session_start ))

    echo "[*] Sending stop notification..."
    send_stop_notification "$session_duration"

    echo "[✓] Monitoring stopped"
    echo ""
    exit 0
}
